// In order to *not* need this ignore, consider extracting the "web" version
// of your plugin as a separate package, instead of inlining it in the same
// package as the core of your plugin.
// ignore: avoid_web_libraries_in_flutter

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'flutter_moja_mreza_platform_interface.dart';

/// A web implementation of the FlutterMojaMrezaPlatform of the FlutterMojaMreza plugin.
class FlutterMojaMrezaWeb extends FlutterMojaMrezaPlatform {
  /// Constructs a FlutterMojaMrezaWeb
  FlutterMojaMrezaWeb();

  static void registerWith(Registrar registrar) {
    FlutterMojaMrezaPlatform.instance = FlutterMojaMrezaWeb();
  }

  /// Returns a [String] containing the version of the platform.
  @override
  Future<String?> getPlatformVersion() async {
    final version = web.window.navigator.userAgent;
    return version;
  }

  @override
  Future<void> openMojaMreza(BuildContext context) async {
    // NAPOMENA: Na web platformi ne možemo dohvatiti HTML sadržaj zbog CORS ograničenja.
    // Browser blokira pristup sadržaju s druge domene iz sigurnosnih razloga.
    // Za dohvaćanje HTML-a trebate:
    // 1. Proxy server koji će dohvatiti sadržaj
    // 2. Browser ekstenziju
    // 3. Koristiti samo mobilne platforme (Android/iOS)
    web.window.open('https://mojamreza.hep.hr/NiasSignOnRequest', '_blank');
  }
}
