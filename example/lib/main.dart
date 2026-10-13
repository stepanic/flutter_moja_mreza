import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_platform_interface.dart';

import 'pocetna.dart';
import 'tema.dart';

void main() {
  if (kDebugMode && !kIsWeb) {
    FlutterMojaMrezaPlatform.instance = _SnimanjeHtmla(
      FlutterMojaMrezaPlatform.instance,
    );
  }
  DomovinaTema.registrirajLicence();
  runApp(
    MaterialApp(
      title: 'Domovina Energy',
      theme: DomovinaTema.svijetla(),
      // Tamna tema još ne postoji; tokeni su svijetli kao na webu.
      themeMode: ThemeMode.light,
      home: const Pocetna(),
    ),
  );
}

/// Samo debug: sprema sirovi HTML svake stranice u privremeni direktorij
/// (na simulatoru je to direktorij na Macu), za usporedbu s parserom.
/// Sadrži OIB, pa ne ide u repo bez anonimizacije.
class _SnimanjeHtmla extends FlutterMojaMrezaPlatform {
  _SnimanjeHtmla(this._p);

  final FlutterMojaMrezaPlatform _p;

  @override
  Future<String?> getPlatformVersion() => _p.getPlatformVersion();
  @override
  Future<bool> prijava(
    BuildContext context, {
    HepPortal portal = HepPortal.mojaMreza,
  }) => _p.prijava(context, portal: portal);
  @override
  Future<HepStanje> stanje() => _p.stanje();
  @override
  Future<void> napredak(String poruka) => _p.napredak(poruka);
  @override
  Future<void> zatvori() => _p.zatvori();
  @override
  Future<void> odjava() => _p.odjava();

  @override
  Future<HepOdgovor> dohvati(
    String putanja, {
    Map<String, String>? forma,
  }) async {
    final o = await _p.dohvati(putanja, forma: forma);
    final dir = Directory('${Directory.systemTemp.path}/moja_mreza_html')
      ..createSync();
    final ime = putanja.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    File('${dir.path}/$ime.html').writeAsStringSync(o.html);
    debugPrint('MOJA_MREZA_HTML ${dir.path}/$ime.html (${o.status}, ${o.url})');
    return o;
  }
}
