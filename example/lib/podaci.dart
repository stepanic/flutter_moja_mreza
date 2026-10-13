import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Model za prikaz: jedno mjerno mjesto sa spojenim podacima Moje mreže i
/// Mojeg računa. Gradi se iz JSON-a uvoza (`HepUvoz.toJson()`,
/// `MojRacunUvoz.toJson()`), pa svježi i spremljeni uvoz idu istim putem.
class Mjesto {
  Mjesto(this.omm);

  /// 10 znamenki; kod kupca bez OMM-a `kupac-<id>`.
  final String omm;
  String? adresa;
  String? tarifa;
  String? brojBrojila;
  String? ime;
  String? ugovorniRacun;

  /// Dospjeli dug s Mojeg računa.
  num? saldo;
  String? saldoOpis;

  final izvori = <Izvor>{};

  /// Najnovije prvo.
  List<Ocitanje> ocitanja = [];
  List<Razdoblje> potrosnja = [];
  List<Stavka> promet = [];

  bool get imaOmm => RegExp(r'^\d{10}$').hasMatch(omm);

  String get naslov => adresa ?? ime ?? 'OMM $omm';

  Ocitanje? get zadnjeOcitanje => ocitanja.firstOrNull;
  Razdoblje? get zadnjeRazdoblje => potrosnja.firstOrNull;

  /// Najnoviji neplaćeni račun (portal ga boji crveno).
  Stavka? get otvoreniRacun =>
      promet.where((s) => s.racun && s.status == 'RED').firstOrNull;

  bool get imaProizvodnju => potrosnja.any((p) => p.predano > 0);
}

enum Izvor {
  mojaMreza('Moja mreža'),
  mojRacun('Moj račun');

  const Izvor(this.naziv);
  final String naziv;
}

class Ocitanje {
  const Ocitanje({required this.datum, required this.opis, this.t1, this.t2});

  final DateTime datum;
  final String opis;
  final int? t1;
  final int? t2;
}

class Razdoblje {
  const Razdoblje({
    required this.od,
    required this.doDatuma,
    this.t1,
    this.t2,
    this.predano = 0,
  });

  final DateTime od;
  final DateTime doDatuma;
  final int? t1;
  final int? t2;

  /// Energija predana u mrežu (samo Moj račun).
  final int predano;

  int get ukupno => (t1 ?? 0) + (t2 ?? 0);
  int get dana => doDatuma.difference(od).inDays + 1;
}

class Stavka {
  const Stavka({
    required this.datum,
    required this.opis,
    required this.duguje,
    required this.potrazuje,
    this.dospijeva,
    this.status,
  });

  final DateTime datum;
  final String opis;
  final num duguje;
  final num potrazuje;
  final DateTime? dospijeva;
  final String? status;

  bool get racun => duguje > 0;
  num get iznos => racun ? duguje : potrazuje;
}

DateTime? _d(Object? s) => s is String ? DateTime.tryParse(s) : null;
int? _i(Object? v) => (v as num?)?.toInt();
List<Map<String, Object?>> _lista(Object? v) => [
  for (final x in v as List? ?? const []) (x as Map).cast<String, Object?>(),
];

/// Spaja oba uvoza po OMM-u. Kad oba izvora imaju isto razdoblje ili
/// očitanje, vrijedi Moja mreža (mjerenje ODS-a), a Moj račun dodaje
/// predanu energiju, saldo i promet.
List<Mjesto> spojiMjesta({
  Map<String, Object?>? hep,
  Map<String, Object?>? racun,
}) {
  final mjesta = <String, Mjesto>{};

  for (final m in _lista(hep?['mjesta'])) {
    final x = mjesta.putIfAbsent('${m['omm']}', () => Mjesto('${m['omm']}'))
      ..izvori.add(Izvor.mojaMreza)
      ..adresa = m['adresa'] as String?
      ..tarifa = m['tarifni_model'] as String?
      ..brojBrojila = m['broj_brojila'] as String?
      ..ime = m['korisnik'] as String?;
    x.ocitanja = _ocitanja(m['ocitanja']);
    x.potrosnja = _razdoblja(m['potrosnja']);
  }

  for (final k in _lista(racun?['kupci'])) {
    final kljuc = k['omm'] as String? ?? 'kupac-${k['kupac_id']}';
    final x = mjesta.putIfAbsent(kljuc, () => Mjesto(kljuc))
      ..izvori.add(Izvor.mojRacun)
      ..ugovorniRacun = k['ugovorni_racun'] as String?;
    x.adresa ??= k['adresa'] as String?;
    x.ime ??= k['ime'] as String?;
    if (k['saldo'] case final Map<String, Object?> s) {
      x
        ..saldo = s['iznos_eur'] as num?
        ..saldoOpis = s['opis'] as String?;
    }

    final datumi = {for (final o in x.ocitanja) o.datum};
    x.ocitanja = [
      ...x.ocitanja,
      for (final o in _ocitanja(k['ocitanja']))
        if (!datumi.contains(o.datum)) o,
    ]..sort((a, b) => b.datum.compareTo(a.datum));

    final predano = <DateTime, int>{};
    final izRacuna = _razdoblja(k['potrosnja']);
    for (final p in izRacuna) {
      predano[p.od] = p.predano;
    }
    final pocetci = {for (final p in x.potrosnja) p.od};
    x.potrosnja = [
      for (final p in x.potrosnja)
        Razdoblje(
          od: p.od,
          doDatuma: p.doDatuma,
          t1: p.t1,
          t2: p.t2,
          predano: predano[p.od] ?? p.predano,
        ),
      for (final p in izRacuna)
        if (!pocetci.contains(p.od)) p,
    ]..sort((a, b) => b.od.compareTo(a.od));

    x.promet = [
      for (final s in _lista(k['promet']))
        if (_d(s['datum']) case final datum?)
          Stavka(
            datum: datum,
            opis: s['opis'] as String? ?? '',
            duguje: s['duguje_eur'] as num? ?? 0,
            potrazuje: s['potrazuje_eur'] as num? ?? 0,
            dospijeva: _d(s['dospijeva']),
            status: s['status'] as String?,
          ),
    ]..sort((a, b) => b.datum.compareTo(a.datum));
  }

  return mjesta.values.toList();
}

List<Ocitanje> _ocitanja(Object? v) => [
  for (final o in _lista(v))
    if (_d(o['datum']) case final datum?)
      Ocitanje(
        datum: datum,
        opis: o['opis'] as String? ?? '',
        t1: _i(o['t1_kwh']),
        t2: _i(o['t2_kwh']),
      ),
];

List<Razdoblje> _razdoblja(Object? v) => [
  for (final p in _lista(v))
    if ((_d(p['od']), _d(p['do'])) case (final od?, final doDatuma?))
      Razdoblje(
        od: od,
        doDatuma: doDatuma,
        t1: _i(p['t1_kwh']),
        t2: _i(p['t2_kwh']),
        predano:
            (_i(p['predano_t1_kwh']) ?? 0) + (_i(p['predano_t2_kwh']) ?? 0),
      ),
];

/// Zadnji uvoz s pojedinog izvora, spremljen na uređaju. Sadrži ime i
/// adresu (ne OIB), pa se briše u postavkama i kod odjave.
class Spremiste {
  Spremiste._(this._p);

  final SharedPreferences _p;

  static Future<Spremiste> otvori() async =>
      Spremiste._(await SharedPreferences.getInstance());

  static String _kljuc(Izvor i) => 'uvoz-${i.name}';
  static String _poslano(Izvor i) => 'poslano-${i.name}';

  Map<String, Object?>? uvoz(Izvor i) => switch (_p.getString(_kljuc(i))) {
    final s? => jsonDecode(s) as Map<String, Object?>,
    null => null,
  };

  Future<void> spremi(Izvor i, Map<String, Object?> json) =>
      _p.setString(_kljuc(i), jsonEncode(json));

  /// Je li baš ovaj uvoz (po vremenu dohvata) već na omm.domovina.ai.
  bool poslan(Izvor i) {
    final d = uvoz(i)?['dohvaceno'];
    return d != null && _p.getString(_poslano(i)) == d;
  }

  Future<void> oznaciPoslan(Izvor i) async {
    final d = uvoz(i)?['dohvaceno'];
    if (d is String) await _p.setString(_poslano(i), d);
  }

  Future<void> obrisi() async {
    for (final i in Izvor.values) {
      await _p.remove(_kljuc(i));
      await _p.remove(_poslano(i));
    }
  }

  bool get autoSlanje => _p.getBool('auto-omm') ?? true;
  Future<void> postaviAutoSlanje(bool v) => _p.setBool('auto-omm', v);
}

/// Hrvatski zapis brojeva i datuma, bez paketa `intl`.
abstract final class Hr {
  static const _mjeseci = [
    'sij',
    'velj',
    'ožu',
    'tra',
    'svi',
    'lip',
    'srp',
    'kol',
    'ruj',
    'lis',
    'stu',
    'pro',
  ];

  static String broj(num? v) {
    if (v == null) return '–';
    final s = v.round().abs().toString();
    final b = StringBuffer(v < 0 ? '−' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String eur(num? v) {
    if (v == null) return '–';
    final c = (v.abs() * 100).round();
    return '${v < 0 ? '−' : ''}${broj(c ~/ 100)},${(c % 100).toString().padLeft(2, '0')} €';
  }

  static String datum(DateTime? d) =>
      d == null ? '–' : '${d.day}. ${d.month}. ${d.year}.';

  static String kratko(DateTime d) => '${d.day}. ${d.month}.';

  static String mjesec(DateTime d) => _mjeseci[d.month - 1];

  /// „rujan 2026.“ ili „1. 9. – 30. 9. 2026.“ kad razdoblje nije mjesec.
  static String razdoblje(Razdoblje r) {
    final cijeliMjesec =
        r.od.day == 1 &&
        r.od.month == r.doDatuma.month &&
        r.doDatuma.add(const Duration(days: 1)).month != r.doDatuma.month;
    return cijeliMjesec
        ? '${_puni[r.od.month - 1]} ${r.od.year}.'
        : '${kratko(r.od)} – ${datum(r.doDatuma)}';
  }

  static const _puni = [
    'siječanj',
    'veljača',
    'ožujak',
    'travanj',
    'svibanj',
    'lipanj',
    'srpanj',
    'kolovoz',
    'rujan',
    'listopad',
    'studeni',
    'prosinac',
  ];

  static String prije(DateTime d) {
    final r = DateTime.now().difference(d);
    if (r.inMinutes < 1) return 'upravo';
    if (r.inHours < 1) return 'prije ${r.inMinutes} min';
    if (r.inDays < 1) return 'prije ${r.inHours} h';
    if (r.inDays == 1) return 'jučer';
    return datum(d.toLocal());
  }
}
