import 'package:flutter/services.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_method_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelFlutterMojaMreza();
  const channel = MethodChannel('flutter_moja_mreza');

  void odgovor(Future<Object?> Function(MethodCall) f) =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, f);

  tearDown(() => odgovor((_) async => null));

  test('getPlatformVersion', () async {
    odgovor((_) async => '42');
    expect(await platform.getPlatformVersion(), '42');
  });

  test('dohvati vraća HepOdgovor', () async {
    odgovor(
      (c) async => {
        'url': 'https://mojamreza.hep.hr/Postavke',
        'status': 200,
        'html': '<p>',
      },
    );
    final o = await platform.dohvati('/Postavke');
    expect(o.url.path, '/Postavke');
    expect(o.status, 200);
  });

  test('PlatformException kod postaje MojaMrezaGreska', () async {
    odgovor((_) async => throw PlatformException(code: 'otkazano'));
    expect(
      platform.dohvati('/Postavke'),
      throwsA(
        isA<MojaMrezaIznimka>().having(
          (e) => e.greska,
          'greska',
          MojaMrezaGreska.otkazano,
        ),
      ),
    );
  });
}
