import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_moja_mreza_method_channel.dart';
import 'src/modeli.dart';
import 'src/webview_moja_mreza.dart';

/// Prijavljeni HTTP transport prema mojamreza.hep.hr.
///
/// Platforma se brine samo za prijavu (WebView, e-Građani/Certilia) i za
/// `GET` unutar te sesije. Parsiranje i redoslijed zahtjeva su u Dartu
/// ([FlutterMojaMreza.uvezi]), pa su isti na svim platformama.
///
/// Ekran prijave ostaje otvoren od [prijava] do [zatvori] i za vrijeme
/// dohvata prikazuje poruku iz [napredak].
abstract class FlutterMojaMrezaPlatform extends PlatformInterface {
  FlutterMojaMrezaPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMojaMrezaPlatform _instance =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
      ? MethodChannelFlutterMojaMreza()
      : WebViewMojaMreza();

  /// Na iOS-u nativni SwiftUI + WKWebView ([MethodChannelFlutterMojaMreza]),
  /// drugdje `webview_flutter` ([WebViewMojaMreza]).
  static FlutterMojaMrezaPlatform get instance => _instance;

  static set instance(FlutterMojaMrezaPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Otvara ekran i čeka prijavu. Ako je sesija još živa, ne traži ništa od
  /// korisnika. Vraća `false` ako korisnik odustane.
  Future<bool> prijava(BuildContext context) {
    throw const MojaMrezaIznimka(MojaMrezaGreska.nepodrzano);
  }

  /// `GET` [putanja] (npr. `/Ocitanja?omm=0100031779`) s cookiejima sesije.
  Future<HepOdgovor> dohvati(String putanja) {
    throw const MojaMrezaIznimka(MojaMrezaGreska.nepodrzano);
  }

  /// Tekst ispod indikatora na ekranu dok traje dohvat.
  Future<void> napredak(String poruka) async {}

  /// Zatvara ekran. Sesija (cookieji) ostaje za idući uvoz.
  Future<void> zatvori() async {}

  /// Briše cookieje Moje mreže i NIAS-a, npr. za prijavu drugom osobom.
  Future<void> odjava() async {}
}
