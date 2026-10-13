import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'flutter_moja_mreza_platform_interface.dart';
import 'src/modeli.dart';
import 'src/moj_racun.dart';
import 'src/parser.dart';

export 'src/modeli.dart';
export 'src/moj_racun.dart';
export 'src/parser.dart' show MojaMrezaParser;

class FlutterMojaMreza {
  FlutterMojaMrezaPlatform get _p => FlutterMojaMrezaPlatform.instance;

  Future<String?> getPlatformVersion() => _p.getPlatformVersion();

  /// Prijava na Moju mrežu (e-Građani/Certilia) i uvoz svih OMM-ova
  /// prijavljene osobe s očitanjima i potrošnjom.
  ///
  /// Vraća `null` ako korisnik odustane od prijave. Baca [MojaMrezaIznimka]
  /// ako sesija istekne usred uvoza ili HTML ne izgleda kako očekujemo.
  /// Sve se parsira na uređaju; HEP cookieji ne napuštaju WebView i brišu se
  /// na kraju, pa svaki uvoz traži novu prijavu.
  Future<HepUvoz?> uvezi(
    BuildContext context, {
    bool ocitanja = true,
    bool potrosnja = true,
  }) async {
    try {
      if (!await _p.prijava(context)) return null;
      await _p.napredak('Dohvaćam mjerna mjesta…');
      final omms = MojaMrezaParser.postavke(await _stranica('/Postavke'));

      final mjesta = <HepMjernoMjesto>[];
      for (final (i, omm) in omms.indexed) {
        final oznaka = omms.length > 1 ? ' (${i + 1}/${omms.length})' : '';
        await _p.napredak('OMM ${omm.omm}$oznaka…');
        mjesta.add(
          HepMjernoMjesto(
            omm: omm,
            ocitanja: ocitanja
                ? MojaMrezaParser.ocitanja(
                    await _stranica('/Ocitanja', omm.omm),
                  )
                : const [],
            potrosnja: potrosnja
                ? MojaMrezaParser.potrosnja(
                    await _stranica('/Potrosnja', omm.omm),
                  )
                : const [],
          ),
        );
      }
      return HepUvoz(dohvaceno: DateTime.now(), mjesta: mjesta);
    } on MojaMrezaIznimka catch (e) {
      if (e.greska == MojaMrezaGreska.otkazano) return null;
      rethrow;
    } finally {
      await _p.zatvori();
    }
  }

  /// Prijava na Moj račun HEP Elektre (korisničko ime i lozinka) i uvoz
  /// kupaca s očitanjima, potrošnjom i prometom.
  ///
  /// Vraća `null` ako korisnik odustane. kupacId se čita iz zahtjeva koje je
  /// portal poslao nakon prijave, a ime, OMM i adresa iz zaglavlja „Kupac“,
  /// kao u extensionu (`extension/mojracun.js`). OIB se ne uzima.
  Future<MojRacunUvoz?> uveziMojRacun(BuildContext context) async {
    try {
      if (!await _p.prijava(context, portal: HepPortal.mojRacun)) return null;
      await _p.napredak('Dohvaćam kupce…');
      final stanje = await _p.stanje();
      final ids = MojRacunParser.kupacIds(stanje.resursi);
      if (ids.isEmpty) {
        throw const MojaMrezaIznimka(
          MojaMrezaGreska.neocekivanHtml,
          'Portal nije učitao nijednog kupca',
        );
      }
      // Zaglavlje pokazuje kupca čiji su podaci zadnji učitani.
      final zaglavlje = MojRacunParser.zaglavlje(stanje.html);

      final kupci = <MojRacunKupac>[];
      for (final (i, id) in ids.indexed) {
        final oznaka = ids.length > 1 ? ' (${i + 1}/${ids.length})' : '';
        await _p.napredak('Kupac $id$oznaka…');
        final promet = MojRacunParser.promet(await _api('promet/$id'));
        kupci.add(
          MojRacunKupac(
            kupacId: id,
            zaglavlje: id == ids.last && zaglavlje != null
                ? zaglavlje
                : const MojRacunZaglavlje(),
            saldo: promet.saldo,
            saldoOpis: promet.saldoOpis,
            ocitanja: MojRacunParser.ocitanja(await _api('ocitanja/$id')),
            potrosnja: MojRacunParser.potrosnja(await _api('potrosnja/$id')),
            promet: promet.stavke,
          ),
        );
      }
      return MojRacunUvoz(dohvaceno: DateTime.now(), kupci: kupci);
    } on MojaMrezaIznimka catch (e) {
      if (e.greska == MojaMrezaGreska.otkazano) return null;
      rethrow;
    } finally {
      await _p.zatvori();
    }
  }

  /// JSON s `/elektra/v1/api/…` Mojeg računa.
  Future<Object?> _api(String putanja) async {
    final o = await _p.dohvati('/elektra/v1/api/$putanja');
    if (o.status == 401 || o.status == 403) {
      throw const MojaMrezaIznimka(MojaMrezaGreska.sesijaIstekla);
    }
    if (o.status != 200) {
      throw MojaMrezaIznimka(
        MojaMrezaGreska.mreza,
        'HTTP ${o.status} za $putanja',
      );
    }
    try {
      return jsonDecode(o.html);
    } on FormatException {
      throw MojaMrezaIznimka(
        MojaMrezaGreska.neocekivanHtml,
        '$putanja nije JSON',
      );
    }
  }

  /// Dostava očitanja ([t1] = 1.8.1, [t2] = 1.8.2, cijeli kWh) za [omm]
  /// (zadano: OMM koji portal odabere). **Nepovratno:** pozivaj tek nakon što
  /// je korisnik potvrdio brojeve.
  ///
  /// Ako stranica pokazuje očekivani raspon, a vrijednost je izvan njega, ništa
  /// se ne šalje i vraća se `poslano: false` s rasponom, osim uz [svejedno].
  /// [svejedno] šalje i `DostavaVM.Posalji=1` (gumb „Dostavi svejedno“).
  /// Vraća `null` ako korisnik odustane od prijave.
  Future<HepDostava?> dostavi(
    BuildContext context, {
    required int t1,
    int? t2,
    String? omm,
    bool svejedno = false,
  }) async {
    try {
      if (!await _p.prijava(context)) return null;
      await _p.napredak('Pripremam dostavu očitanja…');
      final forma = MojaMrezaParser.dostavaForma(
        await _stranica('/DostavaOcitanja', omm),
      );
      final zaOmm = omm ?? forma.polja['DostavaVM.Omm'];
      bool izvan((int, int)? r, int? v) =>
          r != null && v != null && (v < r.$1 || v > r.$2);
      if (!svejedno &&
          (izvan(forma.rasponT1, t1) || izvan(forma.rasponT2, t2))) {
        return HepDostava(
          poslano: false,
          omm: zaOmm,
          forma: forma,
          upozorenje: true,
          opis: 'Vrijednost je izvan očekivanog raspona',
        );
      }
      if (forma.dvijeTarife && t2 == null) {
        throw const MojaMrezaIznimka(
          MojaMrezaGreska.neocekivanHtml,
          'Brojilo ima dvije tarife, nedostaje 1.8.2',
        );
      }
      await _p.napredak('Šaljem očitanje…');
      final odgovor = await _p.dohvati(
        forma.akcija,
        forma: {
          ...forma.polja,
          'DostavaVM.Posalji': svejedno ? '1' : '0',
          'DostavaVM.Omm': ?zaOmm,
          'DostavaVM.Tarifa1': '$t1',
          if (t2 != null) 'DostavaVM.Tarifa2': '$t2',
        },
      );
      if (odgovor.url.path == '/') {
        throw const MojaMrezaIznimka(MojaMrezaGreska.sesijaIstekla);
      }
      final Object? json;
      try {
        json = jsonDecode(odgovor.html);
      } on FormatException {
        throw MojaMrezaIznimka(
          MojaMrezaGreska.neocekivanHtml,
          'HTTP ${odgovor.status}, odgovor nije JSON',
        );
      }
      if (json is! Map) {
        throw const MojaMrezaIznimka(
          MojaMrezaGreska.neocekivanHtml,
          'Odgovor nije objekt',
        );
      }
      return HepDostava(
        poslano: true,
        status: (json['Status'] as num?)?.toInt(),
        opis: json['Opis'] as String?,
        upozorenje: json.containsKey('Posalji') && json['Status'] != 1,
        omm: zaOmm,
        forma: forma,
      );
    } on MojaMrezaIznimka catch (e) {
      if (e.greska == MojaMrezaGreska.otkazano) return null;
      rethrow;
    } finally {
      await _p.zatvori();
    }
  }

  /// Odjava na serveru i brisanje podataka WebViewa. [uvezi] ih ionako briše
  /// na kraju; ovo je za prekid usred rada i za stare instalacije.
  Future<void> odjava() => _p.odjava();

  /// HTML stranice, uz provjeru da je sesija živa i da je odabran [omm].
  Future<String> _stranica(String putanja, [String? omm]) async {
    final odgovor = await _p.dohvati(
      omm == null ? putanja : '$putanja?omm=${Uri.encodeQueryComponent(omm)}',
    );
    // Neprijavljen zahtjev server preusmjerava na naslovnicu.
    if (odgovor.url.path == '/') {
      throw const MojaMrezaIznimka(MojaMrezaGreska.sesijaIstekla);
    }
    if (odgovor.status != 200) {
      throw MojaMrezaIznimka(
        MojaMrezaGreska.mreza,
        'HTTP ${odgovor.status} za $putanja',
      );
    }
    if (omm != null) {
      final odabran = MojaMrezaParser.odabraniOmm(odgovor.html);
      if (odabran != null && odabran != omm) {
        throw MojaMrezaIznimka(
          MojaMrezaGreska.neocekivanHtml,
          '$putanja?omm=$omm vratio je OMM $odabran',
        );
      }
    }
    return odgovor.html;
  }
}
