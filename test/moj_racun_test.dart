import 'dart:convert';
import 'dart:io';

import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixturei su stvarni odgovori Mojeg računa (2026-10-13), anonimizirani.
/// Iste provjere radi extension/test/mojracun.test.js.
String _tekst(String ime) =>
    File('test/fixtures/mojracun/$ime').readAsStringSync();
Object? _json(String ime) => jsonDecode(_tekst('$ime.json'));

void main() {
  test('ocitanja: datum iz ISO, način očitanja je opis', () {
    final o = MojRacunParser.ocitanja(_json('ocitanja'));
    expect(o, hasLength(3));
    expect(o.first.toJson(), {
      'datum': '2026-10-01',
      'opis': 'Procijenjeno od strane ODS-a',
      't1_kwh': 42947,
      't2_kwh': 15797,
    });
    expect(o.last.datum, DateTime(2019, 10, 1));
  });

  test('potrosnja: razdoblje "dd.mm.yyyy - dd.mm.yyyy", proizv je predano', () {
    final p = MojRacunParser.potrosnja(_json('potrosnja'));
    expect(p, hasLength(2));
    expect(p.first.toJson(), {
      'od': '2026-09-01',
      'do': '2026-09-30',
      't1_kwh': 171,
      't2_kwh': 70,
      'ukupno_kwh': 241,
      'predano_t1_kwh': 0,
      'predano_t2_kwh': 0,
    });
    expect(p.last.od, DateTime(2019, 10, 1));
    expect(p.last.doDatuma, DateTime(2019, 11, 4));
    expect([p.last.predanoT1, p.last.predanoT2], [12, 3]);
  });

  test('promet: rok samo za račune, prazni stringovi su null', () {
    final r = MojRacunParser.promet(_json('promet'));
    expect(r.stavke, hasLength(3));
    expect(r.stavke[0].toJson(), {
      'datum': '2026-10-24',
      'opis': 'Račun',
      'duguje_eur': 44.47,
      'potrazuje_eur': 0,
      'dospijeva': '2026-10-24',
      'poziv_na_broj': '2200000001-260920-7',
      'racun': '100000000002',
      'status': 'RED',
    });
    expect(r.stavke[1].toJson(), {
      'datum': '2026-09-28',
      'opis': 'Uplaćeno',
      'duguje_eur': 0,
      'potrazuje_eur': 45.78,
      'dospijeva': null,
      'poziv_na_broj': null,
      'racun': null,
      'status': null,
    });
    expect(r.saldo, 0);
    expect(r.saldoOpis, 'Dospjeli dug na dan 13.10.2026:');
  });

  test('zaglavlje Kupac: ime, ugovorni račun, OMM, adresa', () {
    final z = MojRacunParser.zaglavlje(_tekst('kupac.html'))!;
    expect(z.toJson(), {
      'ime': 'PERO PERIĆ',
      'ugovorni_racun': '2200000001',
      'omm': '0100031779',
      'adresa': 'ULICA 1, 10000 MJESTO, HR',
    });
  });

  test('kupacIds: iz URL-ova API-ja, zadnje korišteni zadnji', () {
    const b = 'https://mojracun.hep.hr/elektra/v1/api/';
    expect(
      MojRacunParser.kupacIds([
        '${b}obracun/cjenik',
        '${b}korisnik/prijava',
        '${b}potrosnja/1',
        '${b}promet/2',
        '${b}ocitanja/1',
      ]),
      ['2', '1'],
    );
  });

  test('neočekivan oblik baca iznimku', () {
    expect(() => MojRacunParser.ocitanja({}), throwsA(isA<MojaMrezaIznimka>()));
    expect(() => MojRacunParser.promet([]), throwsA(isA<MojaMrezaIznimka>()));
  });
}
