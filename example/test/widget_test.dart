import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_moja_mreza_example/pocetna.dart';
import 'package:flutter_moja_mreza_example/podaci.dart';
import 'package:flutter_moja_mreza_example/tema.dart';

final _hep = {
  'dohvaceno': '2026-10-13T10:00:00Z',
  'mjesta': [
    {
      'omm': '0100031779',
      'korisnik': 'Pero Perić',
      'adresa': 'Školska 5, Zagreb',
      'tarifni_model': 'Kućanstvo NN Bijeli Mjesečno',
      'ocitanja': [
        {
          'datum': '2026-09-30',
          'opis': 'Očitanje kupca',
          't1_kwh': 12345,
          't2_kwh': 6789,
        },
      ],
      'potrosnja': [
        {'od': '2026-09-01', 'do': '2026-09-30', 't1_kwh': 171, 't2_kwh': 70},
        {'od': '2026-08-01', 'do': '2026-08-31', 't1_kwh': 200, 't2_kwh': 90},
      ],
    },
  ],
};

final _racun = {
  'dohvaceno': '2026-10-13T11:00:00Z',
  'kupci': [
    {
      'kupac_id': '10000001',
      'omm': '0100031779',
      'adresa': 'ŠKOLSKA 5',
      'ugovorni_racun': '2200000001',
      'saldo': {'iznos_eur': 0, 'opis': 'Dospjeli dug na dan 13.10.2026:'},
      'ocitanja': [
        {
          'datum': '2026-09-30',
          'opis': 'Kupac',
          't1_kwh': 12345,
          't2_kwh': 6789,
        },
        {'datum': '2026-08-31', 'opis': 'ODS', 't1_kwh': 12174, 't2_kwh': 6719},
      ],
      'potrosnja': [
        {
          'od': '2026-09-01',
          'do': '2026-09-30',
          't1_kwh': 171,
          't2_kwh': 70,
          'predano_t1_kwh': 5,
          'predano_t2_kwh': 1,
        },
        {'od': '2026-07-01', 'do': '2026-07-31', 't1_kwh': 150, 't2_kwh': 60},
      ],
      'promet': [
        {
          'datum': '2026-10-01',
          'opis': 'Račun',
          'duguje_eur': 44.47,
          'potrazuje_eur': 0,
          'dospijeva': '2026-10-24',
          'status': 'RED',
        },
        {
          'datum': '2026-09-28',
          'opis': 'Uplaćeno',
          'duguje_eur': 0,
          'potrazuje_eur': 45.78,
          'status': 'GREEN',
        },
      ],
    },
  ],
};

void main() {
  test('spojiMjesta spaja Moju mrežu i Moj račun po OMM-u', () {
    final m = spojiMjesta(hep: [_hep], racun: [_racun]).single;
    expect(m.adresa, 'Školska 5, Zagreb');
    expect(m.izvori, {Izvor.mojaMreza, Izvor.mojRacun});
    expect(m.ocitanja.map((o) => o.datum.month), [9, 8]);
    expect(m.potrosnja.map((p) => p.od.month), [9, 8, 7]);
    expect(m.potrosnja.first.predano, 6);
    expect(m.otvoreniRacun?.iznos, 44.47);
    expect(m.saldo, 0);
  });

  test('Isti OMM na dva računa: vrijedi noviji uvoz', () {
    Map<String, Object?> uvoz(String kada, String omm, String adresa) => {
      'dohvaceno': kada,
      'mjesta': [
        {'omm': omm, 'adresa': adresa},
      ],
    };
    final m = spojiMjesta(
      hep: [
        uvoz('2026-10-13T12:00:00Z', '0100031779', 'Novija'),
        uvoz('2026-10-12T12:00:00Z', '0100031779', 'Starija'),
        uvoz('2026-10-12T12:00:00Z', '0112024676', 'Drugo mjesto'),
      ],
      racun: [_racun],
    );
    expect(m.map((x) => x.adresa), ['Novija', 'Drugo mjesto']);
    expect(m.first.izvori, {Izvor.mojaMreza, Izvor.mojRacun});
  });

  test('Spremiste: više računa, zamjena istog i preseljenje', () async {
    SharedPreferences.setMockInitialValues({
      'uvoz-mojaMreza': jsonEncode(_hep),
      'poslano-mojaMreza': _hep['dohvaceno']!,
    });
    final sp = await Spremiste.otvori();
    final stari = sp.racuni(Izvor.mojaMreza).single;
    expect(stari.kljuc, 'mojaMreza:0100031779');
    expect(sp.poslan(stari), isTrue);

    final drugi = await sp.spremi(Izvor.mojaMreza, {
      'dohvaceno': '2026-10-13T12:00:00Z',
      'mjesta': [
        {'omm': '0112024676', 'korisnik': 'Ivan'},
        {'omm': '0112024677'},
      ],
    });
    expect(drugi.naziv, 'Ivan · 2 mjesta');
    expect(sp.racuni(Izvor.mojaMreza), hasLength(2));

    // Prvi račun s novim mjestom je i dalje isti račun.
    await sp.spremi(Izvor.mojaMreza, {
      'dohvaceno': '2026-10-13T13:00:00Z',
      'mjesta': [
        {'omm': '0100031779'},
        {'omm': '0100031780'},
      ],
    });
    expect(sp.racuni(Izvor.mojaMreza).map((r) => r.kljuc), [
      'mojaMreza:0112024676,0112024677',
      'mojaMreza:0100031779,0100031780',
    ]);

    await sp.ukloni(drugi);
    expect(sp.sviRacuni, hasLength(1));
  });

  test('Hr zapis', () {
    expect(Hr.broj(12345), '12.345');
    expect(Hr.broj(999), '999');
    expect(Hr.eur(1234.5), '1.234,50 €');
    expect(
      Hr.razdoblje(
        Razdoblje(od: DateTime(2026, 9), doDatuma: DateTime(2026, 9, 30)),
      ),
      'rujan 2026.',
    );
  });

  testWidgets('Prazan početni ekran nudi uvoz', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(theme: DomovinaTema.svijetla(), home: const Pocetna()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Uvezi s Moje mreže'), findsOneWidget);
    expect(find.text('Uvezi s Mojeg računa'), findsOneWidget);
  });

  testWidgets('Spremljeni uvoz se prikaže kao kartica mjesta', (tester) async {
    SharedPreferences.setMockInitialValues({
      'racuni-mojaMreza': jsonEncode([_hep]),
      'racuni-mojRacun': jsonEncode([_racun]),
    });
    await tester.pumpWidget(
      MaterialApp(theme: DomovinaTema.svijetla(), home: const Pocetna()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Školska 5, Zagreb'), findsOneWidget);
    expect(find.text('12.345 T1', findRichText: true), findsOneWidget);
    expect(find.text('Nema dospjelog duga'), findsOneWidget);
    expect(find.text('Moja mreža + Moj račun'), findsOneWidget);
    expect(find.text('POVEZANI RAČUNI (2)'), findsOneWidget);
    expect(find.text('Pero Perić'), findsOneWidget);

    await tester.tap(find.text('Školska 5, Zagreb'));
    await tester.pumpAndSettle();
    expect(find.text('Potrošnja'), findsOneWidget);
    expect(find.text('Računi'), findsOneWidget);
  });
}
