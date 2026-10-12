/// Podaci uvezeni s Moje mreže (https://mojamreza.hep.hr).
///
/// OIB se namjerno ne uvozi iako je u istoj tablici kao OMM.
library;

String _datum(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Obračunsko mjerno mjesto, redak tablice na `/Postavke`.
class HepOmm {
  const HepOmm({
    required this.omm,
    this.brojBrojila,
    this.korisnik,
    this.adresa,
    this.tarifniModel,
  });

  /// 10 znamenki s vodećom nulom, npr. `0100031779`.
  final String omm;
  final String? brojBrojila;
  final String? korisnik;
  final String? adresa;

  /// Npr. `Kućanstvo NN Bijeli Mjesečno`.
  final String? tarifniModel;

  Map<String, Object?> toJson() => {
    'omm': omm,
    'broj_brojila': brojBrojila,
    'korisnik': korisnik,
    'adresa': adresa,
    'tarifni_model': tarifniModel,
  };

  @override
  String toString() => 'HepOmm($omm, $adresa)';
}

/// Stanje brojila, redak tablice na `/Ocitanja`.
class HepOcitanje {
  const HepOcitanje({
    required this.datum,
    required this.opis,
    this.t1,
    this.t2,
  });

  final DateTime datum;

  /// Npr. `Očitanje kupca`, `Očitanje od strane ODS-a`.
  final String opis;

  /// Stanje tarife 1 (viša) u kWh.
  final int? t1;

  /// Stanje tarife 2 (niža) u kWh; prazno kod jednotarifnih brojila.
  final int? t2;

  Map<String, Object?> toJson() => {
    'datum': _datum(datum),
    'opis': opis,
    't1_kwh': t1,
    't2_kwh': t2,
  };

  @override
  String toString() => 'HepOcitanje(${_datum(datum)}, $opis, $t1, $t2)';
}

/// Potrošnja za obračunsko razdoblje, redak tablice na `/Potrosnja`.
class HepPotrosnja {
  const HepPotrosnja({
    required this.od,
    required this.doDatuma,
    this.t1,
    this.t2,
  });

  final DateTime od;
  final DateTime doDatuma;
  final int? t1;
  final int? t2;

  int get ukupno => (t1 ?? 0) + (t2 ?? 0);

  Map<String, Object?> toJson() => {
    'od': _datum(od),
    'do': _datum(doDatuma),
    't1_kwh': t1,
    't2_kwh': t2,
    'ukupno_kwh': ukupno,
  };

  @override
  String toString() =>
      'HepPotrosnja(${_datum(od)}–${_datum(doDatuma)}, $t1, $t2)';
}

/// Jedan OMM sa svojim očitanjima i potrošnjom.
class HepMjernoMjesto {
  const HepMjernoMjesto({
    required this.omm,
    this.ocitanja = const [],
    this.potrosnja = const [],
  });

  final HepOmm omm;

  /// Najnovije prvo, kao na portalu.
  final List<HepOcitanje> ocitanja;

  /// Najnovije prvo, kao na portalu.
  final List<HepPotrosnja> potrosnja;

  Map<String, Object?> toJson() => {
    ...omm.toJson(),
    'ocitanja': [for (final o in ocitanja) o.toJson()],
    'potrosnja': [for (final p in potrosnja) p.toJson()],
  };
}

/// Rezultat jednog uvoza.
class HepUvoz {
  const HepUvoz({required this.dohvaceno, required this.mjesta});

  final DateTime dohvaceno;
  final List<HepMjernoMjesto> mjesta;

  Map<String, Object?> toJson() => {
    'izvor': 'https://mojamreza.hep.hr',
    'dohvaceno': dohvaceno.toUtc().toIso8601String(),
    'mjesta': [for (final m in mjesta) m.toJson()],
  };
}

/// Zašto uvoz nije uspio.
enum MojaMrezaGreska {
  /// Korisnik je zatvorio prijavu ili uvoz.
  otkazano,

  /// Server je preusmjerio na naslovnicu, prijava više ne vrijedi.
  sesijaIstekla,

  /// HTML ne izgleda kako parser očekuje (HEP je promijenio stranicu?).
  neocekivanHtml,

  /// Mreža ili WebView javili su grešku.
  mreza,

  /// Platforma nema implementaciju (npr. web zbog CORS-a).
  nepodrzano,
}

class MojaMrezaIznimka implements Exception {
  const MojaMrezaIznimka(this.greska, [this.poruka]);

  final MojaMrezaGreska greska;
  final String? poruka;

  @override
  String toString() =>
      'MojaMrezaIznimka(${greska.name}${poruka == null ? '' : ': $poruka'})';
}

/// Sirovi odgovor na `GET` unutar prijavljene sesije.
class HepOdgovor {
  const HepOdgovor({
    required this.url,
    required this.status,
    required this.html,
  });

  factory HepOdgovor.izMape(Map<Object?, Object?> m) => HepOdgovor(
    url: Uri.parse(m['url'] as String),
    status: (m['status'] as num).toInt(),
    html: m['html'] as String,
  );

  /// Konačni URL nakon preusmjeravanja.
  final Uri url;
  final int status;
  final String html;
}

/// Forma `/DostavaOcitanja`: skrivena polja (svježi tokeni) i očekivani raspon.
class HepDostavaForma {
  const HepDostavaForma({
    required this.akcija,
    required this.polja,
    this.rasponT1,
    this.rasponT2,
    this.rasponTekst = const [],
  });

  /// Tekst stranice oko svake pojave riječi „raspon“, za dijagnozu parsera.
  final List<String> rasponTekst;

  /// `action` forme, npr. `/Omm/Dostava`.
  final String akcija;

  /// Sva imenovana polja forme kako bi ih poslao preglednik.
  final Map<String, String> polja;

  /// „očekivani raspon od X do Y“ ispod polja, ako ga stranica ima.
  final (int, int)? rasponT1;
  final (int, int)? rasponT2;

  bool get dvijeTarife => polja.containsKey('DostavaVM.Tarifa2');
}

/// Ishod [FlutterMojaMreza.dostavi].
class HepDostava {
  const HepDostava({
    required this.poslano,
    this.status,
    this.opis,
    this.upozorenje = false,
    this.omm,
    this.forma,
  });

  /// Je li POST uopće poslan. `false` kad je vrijednost izvan očekivanog
  /// raspona, a nije traženo slanje svejedno.
  final bool poslano;

  /// `Status` iz odgovora; 1 znači prihvaćeno.
  final int? status;
  final String? opis;

  /// HEP traži potvrdu („Dostavi svejedno“); ponovi s `svejedno: true`.
  final bool upozorenje;
  final String? omm;
  final HepDostavaForma? forma;

  bool get prihvaceno => poslano && status == 1;

  Map<String, Object?> toJson() => {
    'poslano': poslano,
    'Status': status,
    'Opis': opis,
    'upozorenje': upozorenje,
    'omm': omm,
    'raspon_t1': forma?.rasponT1 == null
        ? null
        : [forma!.rasponT1!.$1, forma!.rasponT1!.$2],
    'raspon_tekst': forma?.rasponTekst,
    'raspon_t2': forma?.rasponT2 == null
        ? null
        : [forma!.rasponT2!.$1, forma!.rasponT2!.$2],
  };

  @override
  String toString() => 'HepDostava(poslano: $poslano, $status, $opis)';
}
