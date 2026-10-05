import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../flutter_moja_mreza_platform_interface.dart';
import 'modeli.dart';

/// Android (i sve osim iOS-a): isti ugovor kao nativni iOS dio, preko
/// `webview_flutter`. Rezultat `fetch`a vraća se kroz JavaScript kanal jer
/// `runJavaScriptReturningResult` ne čeka Promise.
class WebViewMojaMreza extends FlutterMojaMrezaPlatform {
  static final _baza = Uri.parse('https://mojamreza.hep.hr');
  static final _pocetna = _baza.resolve('/Pocetna');
  static final _nias = _baza.resolve('/NiasSignOnRequest');

  WebViewController? _kontroler;
  NavigatorState? _navigator;
  Route<void>? _ruta;
  final _poruka = ValueNotifier<String?>(null);
  final _ucitava = ValueNotifier<bool>(false);
  bool _prijavaUTijeku = false;
  bool _otkazano = false;
  Completer<bool>? _prijava;
  Completer<Uri?>? _ucitavanje;
  final _zahtjevi = <int, Completer<HepOdgovor>>{};
  int _sljedeciId = 0;

  static bool jePrijavljen(Uri? url) =>
      url != null &&
      url.host == _baza.host &&
      url.path.toLowerCase().startsWith('/pocetna');

  WebViewController get _webView => _kontroler ??= WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..addJavaScriptChannel('MojaMrezaKanal', onMessageReceived: _primljeno)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) => _ucitava.value = true,
        onPageFinished: _ucitano,
        onWebResourceError: (e) {
          if (e.isForMainFrame == false) return;
          _ucitava.value = false;
          final c = _ucitavanje;
          _ucitavanje = null;
          c?.completeError(
            MojaMrezaIznimka(MojaMrezaGreska.mreza, e.description),
          );
        },
      ),
    );

  @override
  Future<bool> prijava(BuildContext context) async {
    _otkazano = false;
    _poruka.value = 'Provjeravam prijavu…';
    _prikazi(context);

    final url = await _ucitaj(_pocetna);
    if (_otkazano) return false;
    if (jePrijavljen(url)) {
      _poruka.value = 'Prijavljen';
      return true;
    }

    _poruka.value = null;
    _prijavaUTijeku = true;
    final c = _prijava = Completer<bool>();
    await _webView.loadRequest(_nias);
    return c.future;
  }

  @override
  Future<HepOdgovor> dohvati(String putanja) async {
    if (_otkazano) throw const MojaMrezaIznimka(MojaMrezaGreska.otkazano);
    final trenutni = await _webView.currentUrl();
    if (trenutni == null || Uri.parse(trenutni).host != _baza.host) {
      await _ucitaj(_pocetna);
    }
    final id = _sljedeciId++;
    final c = _zahtjevi[id] = Completer<HepOdgovor>();
    await _webView.runJavaScript('''
(async () => {
  try {
    const r = await fetch(${jsonEncode(putanja)}, { credentials: 'same-origin' });
    const html = await r.text();
    MojaMrezaKanal.postMessage(JSON.stringify({ id: $id, url: r.url, status: r.status, html }));
  } catch (e) {
    MojaMrezaKanal.postMessage(JSON.stringify({ id: $id, greska: String(e) }));
  }
})();
''');
    return c.future;
  }

  @override
  Future<void> napredak(String poruka) async => _poruka.value = poruka;

  @override
  Future<void> zatvori() async {
    final ruta = _ruta;
    _ruta = null;
    if (ruta != null && ruta.isActive) _navigator?.removeRoute(ruta);
  }

  @override
  Future<void> odjava() async {
    // Odjava na serveru, pa brisanje cookieja HEP-a i NIAS-a.
    try {
      await _ucitaj(_baza.resolve('/Odjava'));
    } on MojaMrezaIznimka {
      // Svejedno brišemo cookieje.
    }
    await WebViewCookieManager().clearCookies();
    await _kontroler?.clearLocalStorage();
  }

  void _odustani() {
    _otkazano = true;
    const greska = MojaMrezaIznimka(MojaMrezaGreska.otkazano);
    _prijava?.complete(false);
    _prijava = null;
    _ucitavanje?.completeError(greska);
    _ucitavanje = null;
    for (final c in _zahtjevi.values) {
      c.completeError(greska);
    }
    _zahtjevi.clear();
    _ruta = null;
  }

  void _prikazi(BuildContext context) {
    if (_ruta != null) return;
    _navigator = Navigator.of(context);
    final ruta = _ruta = MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _EkranPrijave(
        kontroler: _webView,
        poruka: _poruka,
        ucitava: _ucitava,
      ),
    );
    // Zatvaranje bilo kojim putem (gumb, natrag) znači odustajanje, osim kad
    // ga zatvori zatvori().
    _navigator!.push(ruta).then((_) {
      if (_ruta == ruta) _odustani();
    });
  }

  Future<Uri?> _ucitaj(Uri url) {
    _ucitavanje?.completeError(
      const MojaMrezaIznimka(MojaMrezaGreska.otkazano),
    );
    final c = _ucitavanje = Completer<Uri?>();
    _webView.loadRequest(url);
    return c.future;
  }

  void _ucitano(String url) {
    _ucitava.value = false;
    final uri = Uri.tryParse(url);
    final c = _ucitavanje;
    _ucitavanje = null;
    c?.complete(uri);
    if (_prijavaUTijeku && jePrijavljen(uri)) {
      _prijavaUTijeku = false;
      _poruka.value = 'Prijava uspjela';
      _prijava?.complete(true);
      _prijava = null;
    }
  }

  void _primljeno(JavaScriptMessage poruka) {
    final Map<String, Object?> m;
    try {
      m = jsonDecode(poruka.message) as Map<String, Object?>;
    } catch (_) {
      return; // kanal vidi i NIAS, ignoriraj tuđe poruke
    }
    final c = _zahtjevi.remove(m['id']);
    if (c == null) return;
    if (m['greska'] != null) {
      c.completeError(
        MojaMrezaIznimka(MojaMrezaGreska.mreza, m['greska'] as String),
      );
    } else {
      c.complete(HepOdgovor.izMape(m));
    }
  }
}

class _EkranPrijave extends StatelessWidget {
  const _EkranPrijave({
    required this.kontroler,
    required this.poruka,
    required this.ucitava,
  });

  final WebViewController kontroler;
  final ValueNotifier<String?> poruka;
  final ValueNotifier<bool> ucitava;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moja mreža'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: ValueListenableBuilder(
            valueListenable: ucitava,
            builder: (_, u, _) => u
                ? const LinearProgressIndicator(minHeight: 2)
                : const SizedBox(height: 2),
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: kontroler),
          ValueListenableBuilder(
            valueListenable: poruka,
            builder: (context, p, _) => p == null
                ? const SizedBox.shrink()
                : ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(p, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
