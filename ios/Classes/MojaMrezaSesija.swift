import SwiftUI
import UIKit
import WebKit

enum MojaMrezaGreska: Error {
  /// Kod odgovara `MojaMrezaGreska` u Dartu (`lib/src/modeli.dart`).
  case otkazano
  case mreza(String)

  var kod: String {
    switch self {
    case .otkazano: return "otkazano"
    case .mreza: return "mreza"
    }
  }

  var poruka: String? {
    if case .mreza(let p) = self { return p }
    return nil
  }
}

/// Jedan WKWebView od `prijava()` do `zatvori()`.
///
/// Za vrijeme dohvata WebView je ispod poluprozirnog sloja s porukom, ali
/// ostaje u hijerarhiji prozora, pa ga iOS ne pauzira. Pohrana je
/// `nonPersistent()` i nestaje sa WebViewom pri zatvaranju, pa NIAS sesija ne
/// preživi uvoz. Android par je `MojaMrezaSesija.kt`.
@MainActor
final class MojaMrezaSesija: NSObject, ObservableObject {
  static let shared = MojaMrezaSesija()

  static let baza = URL(string: "https://mojamreza.hep.hr")!
  static let pocetna = URL(string: "https://mojamreza.hep.hr/Pocetna")!
  /// Vraća auto-submit formu sa SAMLRequestom prema nias.gov.hr.
  static let nias = URL(string: "https://mojamreza.hep.hr/NiasSignOnRequest")!

  /// Domene (i poddomene) na koje smije glavni okvir. Ostalo ide u Safari.
  /// Isti popis je u `MojaMrezaSesija.kt`.
  static let dopustene = ["mojamreza.hep.hr", "nias.gov.hr", "certilia.com"]

  static func jeDopusten(_ host: String?) -> Bool {
    guard let host = host?.lowercased() else { return false }
    return dopustene.contains { host == $0 || host.hasSuffix("." + $0) }
  }

  enum Faza: Equatable {
    /// Tiho učitavanje /Pocetna: je li sesija još živa.
    case provjera
    /// Korisnik vidi NIAS i prijavljuje se.
    case prijava
    /// Prijavljen, Dart dohvaća stranice.
    case rad(String)
  }

  @Published private(set) var faza: Faza = .provjera
  @Published private(set) var ucitava = false

  private(set) var webView = MojaMrezaSesija.noviWebView()

  private var host: UIViewController?
  private var otkazano = false
  private var prijavaNastavak: CheckedContinuation<Bool, Never>?
  private var ucitavanjeNastavak: CheckedContinuation<URL?, Error>?

  private static func noviWebView() -> WKWebView {
    let cfg = WKWebViewConfiguration()
    cfg.websiteDataStore = .nonPersistent()
    // Bez ovoga UA nema "Safari", a neki pružatelji identiteta odbijaju
    // ugrađene preglednike.
    cfg.applicationNameForUserAgent = "Version/18.0 Mobile/15E148 Safari/604.1"
    let webView = WKWebView(frame: .zero, configuration: cfg)
    #if DEBUG
    if #available(iOS 16.4, *) { webView.isInspectable = true }
    #endif
    return webView
  }

  // MARK: - API za FlutterMojaMrezaPlugin

  func prijava() async throws -> Bool {
    otkazano = false
    faza = .provjera
    if host == nil {
      webView = Self.noviWebView()
      webView.navigationDelegate = self
      webView.uiDelegate = self
    }
    prikazi()

    let url = try await ucitaj(Self.pocetna)
    if otkazano { return false }
    if Self.jePrijavljen(url) {
      faza = .rad("Prijavljen")
      return true
    }

    faza = .prijava
    return await withCheckedContinuation { nastavak in
      prijavaNastavak = nastavak
      webView.load(URLRequest(url: Self.nias))
    }
  }

  /// `GET` unutar stranice, s cookiejima sesije.
  func dohvati(_ putanja: String) async throws -> [String: Any] {
    if otkazano { throw MojaMrezaGreska.otkazano }
    // Samo putanja na istom originu, nikad drugi host.
    guard putanja.hasPrefix("/"), !putanja.hasPrefix("//") else {
      throw MojaMrezaGreska.mreza("Putanja mora počinjati s /: \(putanja)")
    }
    if webView.url?.host != Self.baza.host {
      _ = try await ucitaj(Self.pocetna)
    }
    // JS se izvršava samo na originu Moje mreže.
    guard webView.url?.scheme == "https", webView.url?.host == Self.baza.host else {
      throw MojaMrezaGreska.mreza("WebView nije na \(Self.baza.host!)")
    }
    let js = """
      const r = await fetch(putanja, { credentials: 'same-origin' });
      return { url: r.url, status: r.status, html: await r.text() };
      """
    let rezultat: Any?
    do {
      rezultat = try await webView.callAsyncJavaScript(
        js, arguments: ["putanja": putanja], in: nil, contentWorld: .defaultClient)
    } catch {
      throw MojaMrezaGreska.mreza(error.localizedDescription)
    }
    if otkazano { throw MojaMrezaGreska.otkazano }
    guard let odgovor = rezultat as? [String: Any] else {
      throw MojaMrezaGreska.mreza("fetch nije vratio objekt")
    }
    return odgovor
  }

  func napredak(_ poruka: String) {
    faza = .rad(poruka)
  }

  /// Zatvara ekran; s WebViewom nestaje i njegova `nonPersistent` pohrana.
  func zatvori() {
    host?.dismiss(animated: true)
    host = nil
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView = Self.noviWebView()
  }

  func odjava() async {
    // Odjava na serveru (isti URL kao logout_url u zaglavlju e-Građana) ako
    // je prijava otvorena.
    if host != nil {
      _ = try? await ucitaj(Self.baza.appendingPathComponent("Odjava"))
      zatvori()
    }
    // Starije verzije su držale sesiju u .default() pohrani.
    let store = WKWebsiteDataStore.default()
    let tipovi = WKWebsiteDataStore.allWebsiteDataTypes()
    let zapisi = await store.dataRecords(ofTypes: tipovi).filter {
      $0.displayName.hasSuffix("hep.hr") || $0.displayName.hasSuffix("gov.hr")
    }
    await store.removeData(ofTypes: tipovi, for: zapisi)
  }

  /// Gumb „Odustani”.
  func odustani() {
    otkazano = true
    prijavaNastavak?.resume(returning: false)
    prijavaNastavak = nil
    ucitavanjeNastavak?.resume(throwing: MojaMrezaGreska.otkazano)
    ucitavanjeNastavak = nil
    zatvori()
  }

  // MARK: - Interno

  /// Nakon SAML odgovora NIAS-a portal preusmjerava na /Pocetna; neprijavljen
  /// zahtjev na bilo koju zaštićenu stranicu završava na naslovnici `/`.
  static func jePrijavljen(_ url: URL?) -> Bool {
    guard let url, url.host == baza.host else { return false }
    return url.path.lowercased().hasPrefix("/pocetna")
  }

  private func ucitaj(_ url: URL) async throws -> URL? {
    ucitavanjeNastavak?.resume(throwing: MojaMrezaGreska.otkazano)
    return try await withCheckedThrowingContinuation { nastavak in
      ucitavanjeNastavak = nastavak
      webView.load(URLRequest(url: url))
    }
  }

  private func prikazi() {
    guard host == nil else { return }
    let vc = UIHostingController(rootView: MojaMrezaView(sesija: self))
    // Zatvara se samo gumbom „Odustani”, da Dart sazna za to.
    vc.isModalInPresentation = true
    Self.najgornji()?.present(vc, animated: true)
    host = vc
  }

  private static func najgornji() -> UIViewController? {
    let prozor = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    var vc = prozor?.rootViewController
    while let sljedeci = vc?.presentedViewController { vc = sljedeci }
    return vc
  }
}

extension MojaMrezaSesija: WKNavigationDelegate, WKUIDelegate {
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    ucitava = true
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    ucitava = false
    if let nastavak = ucitavanjeNastavak {
      ucitavanjeNastavak = nil
      nastavak.resume(returning: webView.url)
    }
    if faza == .prijava, Self.jePrijavljen(webView.url), let nastavak = prijavaNastavak {
      prijavaNastavak = nil
      faza = .rad("Prijava uspjela")
      nastavak.resume(returning: true)
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    neuspjeh(error)
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    neuspjeh(error)
  }

  private func neuspjeh(_ error: Error) {
    ucitava = false
    // -999: učitavanje prekinuto novim učitavanjem, nije greška.
    if (error as NSError).code == NSURLErrorCancelled { return }
    if let nastavak = ucitavanjeNastavak {
      ucitavanjeNastavak = nil
      nastavak.resume(throwing: MojaMrezaGreska.mreza(error.localizedDescription))
    }
  }

  /// Linkovi koji nisu http(s), npr. otvaranje aplikacije Certilia, i glavni
  /// okvir na domeni izvan popisa idu sustavu.
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
  ) {
    guard let url = navigationAction.request.url, let shema = url.scheme?.lowercased() else {
      decisionHandler(.allow)
      return
    }
    #if DEBUG
    NSLog("MojaMreza navigacija %@", url.host ?? shema)
    #endif
    let glavniOkvir = navigationAction.targetFrame?.isMainFrame ?? true
    let vani: Bool
    switch shema {
    case "http", "https": vani = glavniOkvir && !Self.jeDopusten(url.host)
    case "about", "blob", "data": vani = false
    default: vani = true
    }
    if vani {
      NSLog("MojaMreza otvaram vani: %@", url.host ?? shema)
      UIApplication.shared.open(url)
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  /// `target="_blank"` otvara u istom WebViewu.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
    return nil
  }
}

struct MojaMrezaView: View {
  @ObservedObject var sesija: MojaMrezaSesija

  var body: some View {
    NavigationView {
      ZStack {
        WebViewPrikaz(webView: sesija.webView)
          .ignoresSafeArea(edges: .bottom)
        if let poruka = poruka {
          VStack(spacing: 16) {
            ProgressView()
            Text(poruka).font(.callout).multilineTextAlignment(.center)
          }
          .padding(32)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.regularMaterial)
        }
      }
      .navigationTitle("Moja mreža")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Odustani") { sesija.odustani() }
        }
        ToolbarItem(placement: .primaryAction) {
          if sesija.ucitava && sesija.faza == .prijava { ProgressView() }
        }
      }
    }
    .navigationViewStyle(.stack)
  }

  private var poruka: String? {
    switch sesija.faza {
    case .provjera: return "Provjeravam prijavu…"
    case .prijava: return nil
    case .rad(let p): return p
    }
  }
}

private struct WebViewPrikaz: UIViewRepresentable {
  let webView: WKWebView
  func makeUIView(context: Context) -> WKWebView { webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
