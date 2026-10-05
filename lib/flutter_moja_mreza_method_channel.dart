import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'flutter_moja_mreza_platform_interface.dart';
import 'src/modeli.dart';

/// iOS: prijava i dohvat u nativnom SwiftUI ekranu s WKWebViewom
/// (`ios/Classes/MojaMrezaSesija.swift`).
class MethodChannelFlutterMojaMreza extends FlutterMojaMrezaPlatform {
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_moja_mreza');

  @override
  Future<String?> getPlatformVersion() =>
      methodChannel.invokeMethod<String>('getPlatformVersion');

  @override
  Future<bool> prijava(BuildContext context) => _poziv(
    () async => await methodChannel.invokeMethod<bool>('prijava') ?? false,
  );

  @override
  Future<HepOdgovor> dohvati(String putanja) => _poziv(() async {
    final m = await methodChannel.invokeMapMethod<Object?, Object?>('dohvati', {
      'putanja': putanja,
    });
    return HepOdgovor.izMape(m!);
  });

  @override
  Future<void> napredak(String poruka) =>
      methodChannel.invokeMethod('napredak', {'poruka': poruka});

  @override
  Future<void> zatvori() => methodChannel.invokeMethod('zatvori');

  @override
  Future<void> odjava() => methodChannel.invokeMethod('odjava');

  Future<T> _poziv<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PlatformException catch (e) {
      final greska =
          MojaMrezaGreska.values.where((g) => g.name == e.code).firstOrNull ??
          MojaMrezaGreska.mreza;
      throw MojaMrezaIznimka(greska, e.message);
    }
  }
}
