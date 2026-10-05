import 'package:flutter/widgets.dart';

import 'flutter_moja_mreza_platform_interface.dart';
import 'src/modeli.dart';
import 'src/parser.dart';

export 'src/modeli.dart';
export 'src/parser.dart' show MojaMrezaParser;

class FlutterMojaMreza {
  FlutterMojaMrezaPlatform get _p => FlutterMojaMrezaPlatform.instance;

  Future<String?> getPlatformVersion() => _p.getPlatformVersion();

  /// Prijava na Moju mrežu (e-Građani/Certilia) i uvoz svih OMM-ova
  /// prijavljene osobe s očitanjima i potrošnjom.
  ///
  /// Vraća `null` ako korisnik odustane od prijave. Baca [MojaMrezaIznimka]
  /// ako sesija istekne usred uvoza ili HTML ne izgleda kako očekujemo.
  /// Sve se parsira na uređaju; HEP cookieji ne napuštaju WebView.
  Future<HepUvoz?> uvezi(
    BuildContext context, {
    bool ocitanja = true,
    bool potrosnja = true,
  }) async {
    if (!await _p.prijava(context)) return null;
    try {
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

  /// Briše HEP i NIAS cookieje; idući [uvezi] traži novu prijavu.
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
