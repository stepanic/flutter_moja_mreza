import 'dart:io';

import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixturei su stvarni reci s portala (2026-10-05), anonimizirani.
String _fixture(String ime) =>
    File('test/fixtures/$ime.html').readAsStringSync();

void main() {
  test('/Postavke: OMM je u <th scope="row">, OIB se ne uvozi', () {
    final omm = MojaMrezaParser.postavke(_fixture('postavke')).single;
    expect(omm.omm, '0100031779');
    expect(omm.brojBrojila, '87071794');
    expect(omm.korisnik, 'PERO PERIĆ');
    expect(omm.adresa, 'ULICA 1, MJESTO');
    expect(omm.tarifniModel, 'Kućanstvo NN Bijeli Mjesečno');
    expect(omm.toJson().values, isNot(contains('00000000000')));
  });

  test('/Ocitanja: stupac Status je <th> s ikonom', () {
    final o = MojaMrezaParser.ocitanja(_fixture('ocitanja'));
    expect(o, hasLength(3));
    expect(o.first.datum, DateTime(2026, 10, 5));
    expect(o.first.opis, 'Očitanje kupca');
    expect(o.first.t1, 15343);
    expect(o.first.t2, 9019);
    expect(o.last.opis, 'Očitanje od strane ODS-a');
    expect(o.last.t1, 0);
  });

  test('/Potrosnja: razdoblje "dd.mm.yyyy. - dd.mm.yyyy."', () {
    final p = MojaMrezaParser.potrosnja(_fixture('potrosnja'));
    expect(p, hasLength(2));
    expect(p.first.od, DateTime(2026, 9, 1));
    expect(p.first.doDatuma, DateTime(2026, 9, 30));
    expect(p.first.ukupno, 427);
    expect(p.last.od, DateTime(2023, 9, 21));
  });

  test('odabrani OMM', () {
    expect(MojaMrezaParser.odabraniOmm(_fixture('ocitanja')), '0100031779');
  });

  test('tablica bez očekivanih stupaca je neocekivanHtml', () {
    expect(
      () => MojaMrezaParser.ocitanja(
        '<table><thead><tr><th>Nešto</th></tr></thead></table>',
      ),
      throwsA(
        isA<MojaMrezaIznimka>().having(
          (e) => e.greska,
          'greska',
          MojaMrezaGreska.neocekivanHtml,
        ),
      ),
    );
  });
}
