package com.example.flutter_moja_mreza

import android.app.Activity
import android.app.Dialog
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.ContextThemeWrapper
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.view.Window
import android.view.WindowInsets
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import org.json.JSONObject

/**
 * HEP portal: odakle kreće prijava, kako se zna da je gotova i na koje domene
 * smije glavni okvir. Isti podaci su u `MojaMrezaSesija.swift`.
 */
internal class HepPortal(
  val naslov: String,
  /** Origin, npr. `https://mojamreza.hep.hr`. */
  val baza: String,
  /** Tiha provjera je li sesija još živa; `null` znači uvijek prijava. */
  val pocetna: String?,
  /** Gdje korisnik počinje prijavu. */
  val prijava: String,
  /** Domene (i poddomene) na koje smije glavni okvir. Ostalo ide vanjskom pregledniku. */
  val dopustene: List<String>,
  /** Prijava gotova po URL-u nakon učitavanja (portal s punim stranicama). */
  val jePrijavljen: (String?) -> Boolean,
  /** Prijava gotova po JS izrazu (SPA koja ne mijenja stranicu); svake sekunde. */
  val jsPrijavljen: String?,
) {
  val host: String = Uri.parse(baza).host!!

  fun jeDopusten(host: String?): Boolean =
    host != null && dopustene.any { host == it || host.endsWith(".$it") }

  fun jeNaOriginu(url: String?): Boolean {
    val uri = url?.let(Uri::parse) ?: return false
    return uri.scheme == "https" && uri.host == host
  }

  companion object {
    /**
     * mojamreza.hep.hr: NIAS (e-Građani). Nakon SAML odgovora portal
     * preusmjerava na /Pocetna; neprijavljen zahtjev završava na naslovnici `/`.
     */
    val MOJA_MREZA = HepPortal(
      naslov = "Moja mreža",
      baza = "https://mojamreza.hep.hr",
      pocetna = "https://mojamreza.hep.hr/Pocetna",
      // Vraća auto-submit formu sa SAMLRequestom prema nias.gov.hr.
      prijava = "https://mojamreza.hep.hr/NiasSignOnRequest",
      dopustene = listOf("mojamreza.hep.hr", "nias.gov.hr", "certilia.com"),
      jePrijavljen = { url ->
        val uri = url?.let(Uri::parse)
        uri?.host == "mojamreza.hep.hr" && (uri.path ?: "").lowercase().startsWith("/pocetna")
      },
      jsPrijavljen = null,
    )

    /**
     * mojracun.hep.hr/elektra: Angular SPA, korisničko ime i lozinka. Nakon
     * prijave sama učita kupca (`api/promet/{kupacId}` i sl.), bez nove stranice.
     */
    val MOJ_RACUN = HepPortal(
      naslov = "Moj račun",
      baza = "https://mojracun.hep.hr",
      pocetna = null,
      prijava = "https://mojracun.hep.hr/elektra/login",
      dopustene = listOf("mojracun.hep.hr"),
      jePrijavljen = { false },
      jsPrijavljen = """
        performance.getEntriesByType('resource').some(e =>
          /\/elektra\/v1\/api\/(promet|potrosnja|ocitanja|obracun)\/\d+/.test(e.name))
      """.trimIndent(),
    )

    fun izImena(ime: String?): HepPortal = if (ime == "mojRacun") MOJ_RACUN else MOJA_MREZA
  }
}

/** Kod odgovara `MojaMrezaGreska` u Dartu (`lib/src/modeli.dart`). */
internal class MojaMrezaGreska(val kod: String, poruka: String? = null) : Exception(poruka)

/**
 * Jedan WebView od `prijava()` do `zatvori()`, u dijalogu preko cijelog ekrana.
 *
 * Podaci (cookieji, storage) su u zasebnom WebView profilu i brišu se pri
 * zatvaranju, pa NIAS sesija ne preživi uvoz. JS kanal za rezultat `fetch`a
 * postoji samo na originu odabranog portala. Nativni iOS par je
 * `ios/Classes/MojaMrezaSesija.swift`.
 */
internal class MojaMrezaSesija(private val activity: Activity, private val portal: HepPortal) {
  companion object {
    private const val TAG = "MojaMreza"
    private const val PROFIL = "flutter_moja_mreza"
    private const val KANAL = "MojaMrezaKanal"

    private val imaProfil get() = WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)

    /**
     * Briše cookieje i storage WebViewa. Bez podrške za profile (stari WebView)
     * to su podaci svih WebViewa aplikacije.
     */
    fun obrisiPodatke() {
      if (imaProfil) {
        val profil = ProfileStore.getInstance().getOrCreateProfile(PROFIL)
        profil.cookieManager.removeAllCookies(null)
        profil.webStorage.deleteAllData()
      } else {
        CookieManager.getInstance().removeAllCookies(null)
        WebStorage.getInstance().deleteAllData()
      }
    }
  }

  private enum class Faza { PROVJERA, PRIJAVA, RAD }

  private val debug = activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

  private val tema = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
    android.R.style.Theme_DeviceDefault_DayNight
  } else {
    android.R.style.Theme_DeviceDefault_Light_NoActionBar
  }

  /** Pogledi dobivaju boje teme dijaloga, ne aplikacije. */
  private val kontekst = ContextThemeWrapper(activity, tema)

  private val webView: WebView
  private val dialog: Dialog
  private val traka: ProgressBar
  private val sloj: View
  private val poruka: TextView

  private var faza = Faza.PROVJERA
  private var otkazano = false
  private var zatvoreno = false
  private var prijavaGotova: ((Result<Boolean>) -> Unit)? = null
  private var ucitavanje: ((Result<String?>) -> Unit)? = null
  private val zahtjevi = mutableMapOf<Int, (Result<Map<String, Any?>>) -> Unit>()
  private var sljedeciId = 0
  private val nit = Handler(Looper.getMainLooper())
  private var provjeraPrijave: Runnable? = null

  init {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
      throw MojaMrezaGreska("nepodrzano", "Android System WebView je prestar, ažurirajte ga.")
    }
    if (debug) WebView.setWebContentsDebuggingEnabled(true)

    webView = WebView(kontekst)
    // Mora prije bilo kakvog korištenja WebViewa.
    if (imaProfil) WebViewCompat.setProfile(webView, PROFIL)
    webView.settings.javaScriptEnabled = true
    webView.settings.domStorageEnabled = true
    webView.webViewClient = Klijent()
    WebViewCompat.addWebMessageListener(webView, KANAL, setOf(portal.baza)) { _, p, izvor, glavniOkvir, _ ->
      if (glavniOkvir && izvor.toString() == portal.baza) p.data?.let(::primljeno)
    }

    traka = ProgressBar(kontekst, null, android.R.attr.progressBarStyleHorizontal).apply {
      isIndeterminate = true
      visibility = View.INVISIBLE
    }
    poruka = TextView(kontekst).apply {
      gravity = Gravity.CENTER
      setPadding(dp(32), dp(16), dp(32), 0)
    }
    sloj = LinearLayout(kontekst).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setBackgroundColor(boja(android.R.attr.colorBackground))
      isClickable = true // ne propušta dodire WebViewu
      addView(ProgressBar(kontekst))
      addView(poruka)
    }

    val zaglavlje = LinearLayout(kontekst).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_VERTICAL
      setPadding(dp(4), 0, dp(4), 0)
      addView(Button(kontekst, null, android.R.attr.borderlessButtonStyle).apply {
        text = "Odustani"
        isAllCaps = false
        setOnClickListener { odustani() }
      })
      addView(TextView(kontekst).apply {
        text = portal.naslov
        gravity = Gravity.CENTER
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
      }, LinearLayout.LayoutParams(0, WRAP_CONTENT, 1f))
      // Prazno mjesto širine gumba, da naslov bude u sredini.
      addView(View(kontekst), LinearLayout.LayoutParams(dp(88), 1))
    }

    val sadrzaj = FrameLayout(kontekst).apply {
      addView(webView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
      addView(sloj, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))
    }

    val korijen = LinearLayout(kontekst).apply {
      orientation = LinearLayout.VERTICAL
      setBackgroundColor(boja(android.R.attr.colorBackground))
      addView(zaglavlje, LinearLayout.LayoutParams(MATCH_PARENT, dp(56)))
      addView(traka, LinearLayout.LayoutParams(MATCH_PARENT, dp(4)))
      addView(sadrzaj, LinearLayout.LayoutParams(MATCH_PARENT, 0, 1f))
      setOnApplyWindowInsetsListener { v, insets ->
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
          val i = insets.getInsets(WindowInsets.Type.systemBars() or WindowInsets.Type.ime())
          v.setPadding(i.left, i.top, i.right, i.bottom)
        } else {
          @Suppress("DEPRECATION")
          v.setPadding(
            insets.systemWindowInsetLeft, insets.systemWindowInsetTop,
            insets.systemWindowInsetRight, insets.systemWindowInsetBottom,
          )
        }
        insets
      }
    }

    dialog = object : Dialog(activity, tema) {
      @Deprecated("Deprecated in Java")
      override fun onBackPressed() {
        if (faza == Faza.PRIJAVA && webView.canGoBack()) webView.goBack() else odustani()
      }
    }.apply {
      requestWindowFeature(Window.FEATURE_NO_TITLE)
      setContentView(korijen)
      setCancelable(false)
      window?.apply {
        setLayout(MATCH_PARENT, MATCH_PARENT)
        setBackgroundDrawable(null)
        @Suppress("DEPRECATION")
        setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) setDecorFitsSystemWindows(false)
        @Suppress("DEPRECATION")
        statusBarColor = Color.TRANSPARENT
      }
    }
    prikaziPoruku("Provjeravam prijavu…")
  }

  // API za FlutterMojaMrezaPlugin. Sve na glavnoj niti.

  fun prijava(gotovo: (Result<Boolean>) -> Unit) {
    dialog.show()
    val pocetna = portal.pocetna ?: return trebaPrijava(gotovo)
    ucitaj(pocetna) { r ->
      when {
        otkazano -> gotovo(Result.success(false))
        r.isFailure -> gotovo(Result.failure(r.exceptionOrNull()!!))
        portal.jePrijavljen(r.getOrNull()) -> {
          faza = Faza.RAD
          prikaziPoruku("Prijavljen")
          gotovo(Result.success(true))
        }
        else -> trebaPrijava(gotovo)
      }
    }
  }

  private fun trebaPrijava(gotovo: (Result<Boolean>) -> Unit) {
    faza = Faza.PRIJAVA
    prikaziPoruku(null)
    prijavaGotova = gotovo
    webView.loadUrl(portal.prijava)
    portal.jsPrijavljen?.let(::pratiPrijavu)
  }

  /** SPA: svake sekunde [js] na stranici portala, dok ne vrati `true`. */
  private fun pratiPrijavu(js: String) {
    val r = object : Runnable {
      override fun run() {
        if (zatvoreno || faza != Faza.PRIJAVA) return
        if (!portal.jeNaOriginu(webView.url)) return nit.postDelayed(this, 1000).let {}
        webView.evaluateJavascript(js) { v ->
          if (zatvoreno || faza != Faza.PRIJAVA) return@evaluateJavascript
          if (v != "true") return@evaluateJavascript nit.postDelayed(this, 1000).let {}
          val g = prijavaGotova ?: return@evaluateJavascript
          prijavaGotova = null
          faza = Faza.RAD
          prikaziPoruku("Prijava uspjela")
          g(Result.success(true))
        }
      }
    }
    provjeraPrijave = r
    nit.postDelayed(r, 1000)
  }

  /**
   * `GET` unutar stranice, s cookiejima sesije. S [forma] je `POST`
   * form-urlencoded (kao jQuery `$.post`, za `/Omm/Dostava`).
   */
  fun dohvati(
    putanja: String,
    forma: Map<String, String>? = null,
    gotovo: (Result<Map<String, Any?>>) -> Unit,
  ) {
    if (otkazano) return gotovo(Result.failure(MojaMrezaGreska("otkazano")))
    // Samo putanja na istom originu, nikad drugi host.
    if (!putanja.startsWith("/") || putanja.startsWith("//")) {
      return gotovo(Result.failure(MojaMrezaGreska("mreza", "Putanja mora počinjati s /: $putanja")))
    }
    if (portal.jeNaOriginu(webView.url)) return posalji(putanja, forma, gotovo)
    // SPA (Moj račun) se ne smije ponovno učitati: kupci su u memoriji stranice.
    val pocetna = portal.pocetna
      ?: return gotovo(Result.failure(MojaMrezaGreska("mreza", "WebView nije na ${portal.host}")))
    ucitaj(pocetna) { r ->
      when {
        r.isFailure -> gotovo(Result.failure(r.exceptionOrNull()!!))
        !portal.jeNaOriginu(r.getOrNull()) ->
          gotovo(Result.failure(MojaMrezaGreska("mreza", "WebView nije na ${portal.host}")))
        else -> posalji(putanja, forma, gotovo)
      }
    }
  }

  /** Trenutna stranica: URL, HTML i URL-ovi zahtjeva (Resource Timing). */
  fun stanje(gotovo: (Result<Map<String, Any?>>) -> Unit) {
    if (otkazano) return gotovo(Result.failure(MojaMrezaGreska("otkazano")))
    if (!portal.jeNaOriginu(webView.url)) {
      return gotovo(Result.failure(MojaMrezaGreska("mreza", "WebView nije na ${portal.host}")))
    }
    izvrsi(
      "({ url: location.href, html: document.documentElement.outerHTML, " +
        "resursi: performance.getEntriesByType('resource').map(e => e.name) })",
      gotovo,
    )
  }

  fun napredak(tekst: String) {
    faza = Faza.RAD
    prikaziPoruku(tekst)
  }

  /** Zatvara ekran i briše sve podatke sesije. */
  fun zatvori() {
    if (zatvoreno) return
    zatvoreno = true
    otkazi()
    provjeraPrijave?.let(nit::removeCallbacks)
    provjeraPrijave = null
    dialog.dismiss()
    webView.stopLoading()
    webView.clearHistory()
    webView.clearCache(true)
    obrisiPodatke()
    webView.destroy()
  }

  /** Odjava na serveru (isti URL kao logout_url u zaglavlju e-Građana), pa [zatvori]. */
  fun odjava(gotovo: () -> Unit) {
    if (zatvoreno) return gotovo()
    if (portal !== HepPortal.MOJA_MREZA) {
      zatvori()
      return gotovo()
    }
    ucitaj("${portal.baza}/Odjava") {
      zatvori()
      gotovo()
    }
  }

  // Interno

  /** Gumb „Odustani” ili natrag. */
  private fun odustani() {
    otkazano = true
    zatvori()
  }

  /** Završava sve što čeka, da Dart ne visi. */
  private fun otkazi() {
    val greska = MojaMrezaGreska("otkazano")
    prijavaGotova?.invoke(Result.success(false))
    prijavaGotova = null
    ucitavanje?.invoke(Result.failure(greska))
    ucitavanje = null
    val cekaju = zahtjevi.values.toList()
    zahtjevi.clear()
    cekaju.forEach { it(Result.failure(greska)) }
  }

  private fun ucitaj(url: String, gotovo: (Result<String?>) -> Unit) {
    ucitavanje?.invoke(Result.failure(MojaMrezaGreska("otkazano")))
    ucitavanje = gotovo
    webView.loadUrl(url)
  }

  private fun posalji(
    putanja: String,
    forma: Map<String, String>?,
    gotovo: (Result<Map<String, Any?>>) -> Unit,
  ) {
    val opcije = if (forma == null) "{ credentials: 'same-origin' }" else """
      { method: 'POST', credentials: 'same-origin',
        headers: { 'X-Requested-With': 'XMLHttpRequest' },
        body: new URLSearchParams(${JSONObject(forma as Map<*, *>)}) }
    """.trimIndent()
    izvrsi(
      """
      await (async () => {
        const r = await fetch(${JSONObject.quote(putanja)}, $opcije);
        return { url: r.url, status: r.status, html: await r.text() };
      })()
      """.trimIndent(),
      gotovo,
    )
  }

  /**
   * Izraz [izraz] (smije sadržavati `await`) na stranici portala; rezultat
   * (objekt) stiže kroz KANAL, jer evaluateJavascript ne čeka Promise.
   */
  private fun izvrsi(izraz: String, gotovo: (Result<Map<String, Any?>>) -> Unit) {
    val id = sljedeciId++
    zahtjevi[id] = gotovo
    webView.evaluateJavascript(
      """
      (async () => {
        try {
          const v = $izraz;
          $KANAL.postMessage(JSON.stringify({ id: $id, v }));
        } catch (e) {
          $KANAL.postMessage(JSON.stringify({ id: $id, greska: String(e) }));
        }
      })();
      """.trimIndent(),
      null,
    )
  }

  private fun primljeno(podaci: String) {
    val m = try {
      JSONObject(podaci)
    } catch (_: Exception) {
      return
    }
    val gotovo = zahtjevi.remove(m.optInt("id", -1)) ?: return
    if (m.has("greska")) {
      gotovo(Result.failure(MojaMrezaGreska("mreza", m.getString("greska"))))
    } else {
      val v = m.getJSONObject("v")
      val rezultat = mutableMapOf<String, Any?>("url" to v.getString("url"), "html" to v.getString("html"))
      if (v.has("status")) rezultat["status"] = v.getInt("status")
      v.optJSONArray("resursi")?.let { a -> rezultat["resursi"] = List(a.length()) { a.getString(it) } }
      gotovo(Result.success(rezultat))
    }
  }

  private fun prikaziPoruku(tekst: String?) {
    poruka.text = tekst ?: ""
    sloj.visibility = if (tekst == null) View.GONE else View.VISIBLE
  }

  /** Linkovi koji nisu http(s), npr. aplikacija Certilia, i nedopuštene domene idu sustavu. */
  private fun otvoriVani(url: String) {
    try {
      val intent = if (url.startsWith("intent:")) {
        Intent.parseUri(url, Intent.URI_INTENT_SCHEME).apply {
          addCategory(Intent.CATEGORY_BROWSABLE)
          component = null
          selector = null
        }
      } else {
        Intent(Intent.ACTION_VIEW, Uri.parse(url))
      }
      try {
        activity.startActivity(intent)
      } catch (e: ActivityNotFoundException) {
        val rezerva = intent.getStringExtra("browser_fallback_url") ?: throw e
        activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(rezerva)))
      }
    } catch (e: Exception) {
      Log.w(TAG, "Ne mogu otvoriti $url", e)
    }
  }

  private inner class Klijent : WebViewClient() {
    override fun onPageStarted(view: WebView, url: String, favicon: android.graphics.Bitmap?) {
      if (debug) Log.d(TAG, "navigacija ${Uri.parse(url).host}")
      if (faza == Faza.PRIJAVA) traka.visibility = View.VISIBLE
    }

    override fun onPageFinished(view: WebView, url: String) {
      traka.visibility = View.INVISIBLE
      ucitavanje?.let {
        ucitavanje = null
        it(Result.success(url))
      }
      if (faza == Faza.PRIJAVA && portal.jePrijavljen(url)) {
        val gotovo = prijavaGotova ?: return
        prijavaGotova = null
        faza = Faza.RAD
        prikaziPoruku("Prijava uspjela")
        gotovo(Result.success(true))
      }
    }

    override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
      if (!request.isForMainFrame) return
      traka.visibility = View.INVISIBLE
      ucitavanje?.let {
        ucitavanje = null
        it(Result.failure(MojaMrezaGreska("mreza", error.description.toString())))
      }
    }

    /**
     * Ne poziva se za POST (SAML forme), pa popis domena ne vrijedi za njih;
     * te forme šalju HEP i NIAS, ne treća strana.
     */
    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
      val url = request.url
      return when (url.scheme?.lowercase()) {
        "http", "https" -> {
          if (!request.isForMainFrame || portal.jeDopusten(url.host)) return false
          Log.i(TAG, "Domena nije na popisu, otvaram vani: ${url.host}")
          otvoriVani(url.toString())
          true
        }
        "about", "blob", "data", "javascript" -> false
        else -> {
          otvoriVani(url.toString())
          true
        }
      }
    }
  }

  private fun dp(v: Int) = (v * activity.resources.displayMetrics.density).toInt()

  private fun boja(atribut: Int): Int {
    val tv = TypedValue()
    kontekst.theme.resolveAttribute(atribut, tv, true)
    return tv.data
  }
}
