// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_moja_mreza_platform_interface.dart';

/// Web nije podržan: preglednik zbog CORS-a ne može čitati mojamreza.hep.hr
/// iz druge domene, pa [prijava] i [dohvati] bacaju
/// `MojaMrezaGreska.nepodrzano` (zadano ponašanje platform interfacea).
class FlutterMojaMrezaWeb extends FlutterMojaMrezaPlatform {
  FlutterMojaMrezaWeb();

  static void registerWith(Registrar registrar) {
    FlutterMojaMrezaPlatform.instance = FlutterMojaMrezaWeb();
  }

  @override
  Future<String?> getPlatformVersion() async => web.window.navigator.userAgent;
}
