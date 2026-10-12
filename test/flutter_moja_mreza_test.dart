import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

String _fixture(String ime) =>
    File('test/fixtures/$ime.html').readAsStringSync();

/// Ista stranica, ali s drugim OMM-om odabranim u `#omm_select`.
String _drugiOdabran(String html) => html.replaceFirst(
  '<option value="0100031779" selected="selected">',
  '<option value="0100000001" selected="selected">',
);

class _LazniTransport
    with MockPlatformInterfaceMixin
    implements FlutterMojaMrezaPlatform {
  _LazniTransport(this.stranice);

  final Map<String, String> stranice;
  final trazeno = <String>[];
  final forme = <Map<String, String>>[];
  bool zatvoren = false;

  @override
  Future<String?> getPlatformVersion() async => '42';

  @override
  Future<bool> prijava(BuildContext context) async => true;

  @override
  Future<HepOdgovor> dohvati(
    String putanja, {
    Map<String, String>? forma,
  }) async {
    trazeno.add(putanja);
    if (forma != null) forme.add(forma);
    final html = stranice[putanja];
    return HepOdgovor(
      url: Uri.parse('https://mojamreza.hep.hr${html == null ? '/' : putanja}'),
      status: 200,
      html: html ?? '<html>naslovnica</html>',
    );
  }

  @override
  Future<void> napredak(String poruka) async {}

  @override
  Future<void> zatvori() async => zatvoren = true;

  @override
  Future<void> odjava() async {}
}

void main() {
  testWidgets('uvezi: Postavke pa Ocitanja i Potrosnja po OMM-u', (
    tester,
  ) async {
    final t = _LazniTransport({
      '/Postavke': _fixture('postavke'),
      '/Ocitanja?omm=0100031779': _fixture('ocitanja'),
      '/Potrosnja?omm=0100031779': _fixture('potrosnja'),
    });
    FlutterMojaMrezaPlatform.instance = t;

    await tester.pumpWidget(const SizedBox());
    final uvoz = await FlutterMojaMreza().uvezi(
      tester.element(find.byType(SizedBox)),
    );

    expect(t.trazeno, [
      '/Postavke',
      '/Ocitanja?omm=0100031779',
      '/Potrosnja?omm=0100031779',
    ]);
    expect(t.zatvoren, isTrue);
    final m = uvoz!.mjesta.single;
    expect(m.omm.omm, '0100031779');
    expect(
      m.omm.toJson().containsValue('12345678901'),
      isFalse,
      reason: 'OIB se ne uvozi',
    );
    expect(m.ocitanja.first.t1, 15343);
    expect(m.potrosnja.first.ukupno, 427);
  });

  testWidgets('uvezi: preusmjeravanje na naslovnicu = istekla sesija', (
    tester,
  ) async {
    final t = _LazniTransport({});
    FlutterMojaMrezaPlatform.instance = t;

    await tester.pumpWidget(const SizedBox());
    await expectLater(
      FlutterMojaMreza().uvezi(tester.element(find.byType(SizedBox))),
      throwsA(
        isA<MojaMrezaIznimka>().having(
          (e) => e.greska,
          'greska',
          MojaMrezaGreska.sesijaIstekla,
        ),
      ),
    );
    expect(t.zatvoren, isTrue);
  });

  testWidgets('uvezi: ?omm= koji ne promijeni odabir je greška', (
    tester,
  ) async {
    FlutterMojaMrezaPlatform.instance = _LazniTransport({
      '/Postavke': _fixture('postavke'),
      '/Ocitanja?omm=0100031779': _drugiOdabran(_fixture('ocitanja')),
    });

    await tester.pumpWidget(const SizedBox());
    await expectLater(
      FlutterMojaMreza().uvezi(tester.element(find.byType(SizedBox))),
      throwsA(
        isA<MojaMrezaIznimka>().having(
          (e) => e.greska,
          'greska',
          MojaMrezaGreska.neocekivanHtml,
        ),
      ),
    );
  });

  group('dostavi', () {
    _LazniTransport transport() => _LazniTransport({
      '/DostavaOcitanja': _fixture('dostava_ocitanja'),
      '/Omm/Dostava': '{"Status":1,"Opis":"ok"}',
    });

    testWidgets('šalje sva polja forme s očitanjem', (tester) async {
      final t = transport();
      FlutterMojaMrezaPlatform.instance = t;
      await tester.pumpWidget(const SizedBox());
      final r = await FlutterMojaMreza().dostavi(
        tester.element(find.byType(SizedBox)),
        t1: 15300,
        t2: 9000,
      );
      expect(r!.prihvaceno, isTrue);
      expect(t.trazeno, ['/DostavaOcitanja', '/Omm/Dostava']);
      expect(t.forme.single, {
        '__RequestVerificationToken': 'tok123',
        'encValue': 'ZW5j',
        'DostavaVM.Posalji': '0',
        'DostavaVM.Omm': '0100031779',
        'DostavaVM.Datum_Ocitanja': '12.10.2026.',
        'DostavaVM.Tarifa1': '15300',
        'DostavaVM.Tarifa2': '9000',
      });
      expect(t.zatvoren, isTrue);
    });

    testWidgets('izvan raspona ne šalje ništa', (tester) async {
      final t = transport();
      FlutterMojaMrezaPlatform.instance = t;
      await tester.pumpWidget(const SizedBox());
      final r = await FlutterMojaMreza().dostavi(
        tester.element(find.byType(SizedBox)),
        t1: 25300,
        t2: 9000,
      );
      expect(r!.poslano, isFalse);
      expect(r.forma!.rasponT1, (15283, 15600));
      expect(t.trazeno, ['/DostavaOcitanja']);
    });
  });
}
