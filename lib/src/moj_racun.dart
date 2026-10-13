/// Uvoz s Mojeg računa HEP Elektre (https://mojracun.hep.hr/elektra).
///
/// Moj račun je Angular aplikacija s JSON API-jem na `/elektra/v1/api/…`
/// (cookie sesije, prijava korisničkim imenom i lozinkom), pa parser mapira
/// JSON, ne HTML. Isti JSON daje `extension/mojracun.js`; promjena se radi na
/// oba mjesta. OIB se ne uvozi.
library;

import 'package:html/parser.dart' as html;

import 'modeli.dart';

String _datum(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Potrošnja za obračunsko razdoblje, `api/potrosnja/{kupacId}`.
class MojRacunPotrosnja {
  const MojRacunPotrosnja({
    required this.od,
    required this.doDatuma,
    this.t1,
    this.t2,
    this.predanoT1 = 0,
    this.predanoT2 = 0,
  });

  final DateTime od;
  final DateTime doDatuma;
  final int? t1;
  final int? t2;

  /// Energija predana u mrežu (`proizv1`, `proizv2`), kartica „Proizvodnja“.
  final int predanoT1;
  final int predanoT2;

  int get ukupno => (t1 ?? 0) + (t2 ?? 0);

  Map<String, Object?> toJson() => {
    'od': _datum(od),
    'do': _datum(doDatuma),
    't1_kwh': t1,
    't2_kwh': t2,
    'ukupno_kwh': ukupno,
    'predano_t1_kwh': predanoT1,
    'predano_t2_kwh': predanoT2,
  };
}

/// Račun ili uplata, `api/promet/{kupacId}`.
class MojRacunStavka {
  const MojRacunStavka({
    required this.datum,
    required this.opis,
    this.duguje = 0,
    this.potrazuje = 0,
    this.dospijeva,
    this.pozivNaBroj,
    this.racun,
    this.status,
  });

  final DateTime datum;

  /// `Račun` ili `Uplaćeno`.
  final String opis;
  final num duguje;
  final num potrazuje;

  /// Rok plaćanja; samo kod računa.
  final DateTime? dospijeva;
  final String? pozivNaBroj;
  final String? racun;

  /// Boja na portalu: `RED` (otvoren), `GREEN` (plaćen).
  final String? status;

  Map<String, Object?> toJson() => {
    'datum': _datum(datum),
    'opis': opis,
    'duguje_eur': duguje,
    'potrazuje_eur': potrazuje,
    'dospijeva': dospijeva == null ? null : _datum(dospijeva!),
    'poziv_na_broj': pozivNaBroj,
    'racun': racun,
    'status': status,
  };
}

/// Odabrani kupac iz zaglavlja „Kupac“.
class MojRacunZaglavlje {
  const MojRacunZaglavlje({
    this.ime,
    this.ugovorniRacun,
    this.omm,
    this.adresa,
  });

  final String? ime;
  final String? ugovorniRacun;
  final String? omm;
  final String? adresa;

  Map<String, Object?> toJson() => {
    'ime': ime,
    'ugovorni_racun': ugovorniRacun,
    'omm': omm,
    'adresa': adresa,
  };
}

/// Jedan kupac (ugovorni račun) s očitanjima, potrošnjom i prometom.
class MojRacunKupac {
  const MojRacunKupac({
    required this.kupacId,
    this.zaglavlje = const MojRacunZaglavlje(),
    this.saldo,
    this.saldoOpis,
    this.ocitanja = const [],
    this.potrosnja = const [],
    this.promet = const [],
  });

  /// Interni id HEP Elektre iz URL-ova API-ja, npr. `10000001`.
  final String kupacId;
  final MojRacunZaglavlje zaglavlje;

  /// Dospjeli dug u eurima.
  final num? saldo;
  final String? saldoOpis;

  /// Najnovije prvo; `opis` je način očitanja.
  final List<HepOcitanje> ocitanja;
  final List<MojRacunPotrosnja> potrosnja;
  final List<MojRacunStavka> promet;

  Map<String, Object?> toJson() => {
    'kupac_id': kupacId,
    ...zaglavlje.toJson(),
    'saldo': saldoOpis == null && saldo == null
        ? null
        : {'iznos_eur': saldo, 'opis': saldoOpis},
    'ocitanja': [for (final o in ocitanja) o.toJson()],
    'potrosnja': [for (final p in potrosnja) p.toJson()],
    'promet': [for (final s in promet) s.toJson()],
  };
}

class MojRacunUvoz {
  const MojRacunUvoz({required this.dohvaceno, required this.kupci});

  final DateTime dohvaceno;
  final List<MojRacunKupac> kupci;

  Map<String, Object?> toJson() => {
    'izvor': 'https://mojracun.hep.hr',
    'dohvaceno': dohvaceno.toUtc().toIso8601String(),
    'kupci': [for (final k in kupci) k.toJson()],
  };
}

/// Mapiranje odgovora `/elektra/v1/api/…` u modele.
class MojRacunParser {
  const MojRacunParser._();

  /// `api/ocitanja/{kupacId}`.
  static List<HepOcitanje> ocitanja(Object? json) => [
    for (final o in _lista(json, 'ocitanja'))
      if (_isoDatum(o['datum']) case final datum?)
        HepOcitanje(
          datum: datum,
          opis: o['nacinOcitanja'] as String? ?? '',
          t1: (o['tarifa1'] as num?)?.toInt(),
          t2: (o['tarifa2'] as num?)?.toInt(),
        ),
  ];

  /// `api/potrosnja/{kupacId}`: razdoblje `dd.mm.yyyy - dd.mm.yyyy`.
  static List<MojRacunPotrosnja> potrosnja(Object? json) => [
    for (final p in _lista(json, 'potrosnja'))
      if ((p['razdoblje'] as String? ?? '').split('-').map(_hrDatum).toList()
          case [final od?, final doDatuma?])
        MojRacunPotrosnja(
          od: od,
          doDatuma: doDatuma,
          t1: (p['tarifa1'] as num?)?.toInt(),
          t2: (p['tarifa2'] as num?)?.toInt(),
          predanoT1: (p['proizv1'] as num?)?.toInt() ?? 0,
          predanoT2: (p['proizv2'] as num?)?.toInt() ?? 0,
        ),
  ];

  /// `api/promet/{kupacId}`: stavke i dospjeli dug.
  static ({List<MojRacunStavka> stavke, num? saldo, String? saldoOpis}) promet(
    Object? json,
  ) {
    if (json is! Map || json['promet'] is! List) {
      throw const MojaMrezaIznimka(
        MojaMrezaGreska.neocekivanHtml,
        'promet bez liste',
      );
    }
    final saldo = json['saldo'] as Map?;
    return (
      stavke: [
        for (final s in _lista(json['promet'], 'promet'))
          if (_isoDatum(s['datum']) case final datum?)
            MojRacunStavka(
              datum: datum,
              opis: s['opis'] as String? ?? '',
              duguje: s['duguje'] as num? ?? 0,
              potrazuje: s['potrazuje'] as num? ?? 0,
              // Kod uplata server ovdje vraća trenutno vrijeme, ne rok.
              dospijeva: s['opis'] == 'Račun'
                  ? _isoDatum(s['dospijeva'])
                  : null,
              pozivNaBroj: _prazno(s['pnb']),
              racun: _prazno(s['racun']),
              status: _prazno(s['status']),
            ),
      ],
      saldo: saldo?['iznos'] as num?,
      saldoOpis: saldo == null ? null : _tekst(saldo['opis'] as String?),
    );
  }

  /// Zaglavlje „Kupac“ (`app-kupac-list`) u HTML-u stranice.
  static MojRacunZaglavlje? zaglavlje(String izvor) {
    final k = html.parse(izvor).querySelector('app-kupac-list');
    if (k == null) return null;
    final t = _tekst(k.text);
    String? grupa(String re) => RegExp(re).firstMatch(t)?.group(1);
    final ime = _tekst(k.querySelector('.ng-value-label')?.text);
    final adresa = _tekst(grupa(r'Adresa:\s*(.+)$'));
    return MojRacunZaglavlje(
      ime: ime.isEmpty ? null : ime,
      ugovorniRacun: grupa(r'Ugovorni račun:\s*(\d+)'),
      omm: grupa(r'Broj OMM:\s*(\d+)'),
      adresa: adresa.isEmpty ? null : adresa,
    );
  }

  /// kupacId iz URL-ova API zahtjeva, zadnje korišteni zadnji.
  static List<String> kupacIds(Iterable<String> urlovi) {
    final re = RegExp(
      r'/api/(?:promet|potrosnja|ocitanja|opomene|obracun)/(\d+)(?:$|[?#])',
    );
    final ids = <String>[];
    for (final u in urlovi) {
      final id = re.firstMatch(u)?.group(1);
      if (id == null) continue;
      ids
        ..remove(id)
        ..add(id);
    }
    return ids;
  }

  static List<Map<Object?, Object?>> _lista(Object? json, String sto) {
    if (json is! List) {
      throw MojaMrezaIznimka(MojaMrezaGreska.neocekivanHtml, '$sto nije lista');
    }
    return json.whereType<Map<Object?, Object?>>().toList();
  }

  static String _tekst(String? s) =>
      (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String? _prazno(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// `2026-10-01T01:59:00Z` (rano jutro po našem vremenu) ili `…+02:00`:
  /// datum je prvih 10 znakova.
  static DateTime? _isoDatum(Object? s) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})',
    ).firstMatch(s is String ? s : '');
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  /// `dd.mm.yyyy`.
  static DateTime? _hrDatum(String s) {
    final m = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  }
}
