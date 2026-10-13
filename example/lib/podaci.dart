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

/// Spaja sve uvoze po OMM-u. Kad oba izvora imaju isto razdoblje ili
/// očitanje, vrijedi Moja mreža (mjerenje ODS-a), a Moj račun dodaje
/// predanu energiju, saldo i promet. Ako dva računa istog izvora vide isti
/// OMM, vrijedi noviji uvoz: uvozi se obrađuju od najstarijeg.
List<Mjesto> spojiMjesta({
  List<Map<String, Object?>> hep = const [],
  List<Map<String, Object?>> racun = const [],
}) {
  final mjesta = <String, Mjesto>{};

  for (final m in [for (final u in _poVremenu(hep)) ..._lista(u['mjesta'])]) {
    final x = mjesta.putIfAbsent('${m['omm']}', () => Mjesto('${m['omm']}'))
      ..izvori.add(Izvor.mojaMreza)
      ..adresa = m['adresa'] as String?
      ..tarifa = m['tarifni_model'] as String?
      ..brojBrojila = m['broj_brojila'] as String?
      ..ime = m['korisnik'] as String?;
    x.ocitanja = _ocitanja(m['ocitanja']);
    x.potrosnja = _razdoblja(m['potrosnja']);
  }

  for (final k in [for (final u in _poVremenu(racun)) ..._lista(u['kupci'])]) {
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

List<Map<String, Object?>> _poVremenu(List<Map<String, Object?>> uvozi) =>
    [...uvozi]
      ..sort((a, b) => '${a['dohvaceno']}'.compareTo('${b['dohvaceno']}'));

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

/// Jedan povezani HEP račun i zadnji uvoz s njega. Portali ne vraćaju
/// korisničko ime ni OIB, pa račun prepoznajemo po mjestima koja vidi:
/// OMM-ovima na Mojoj mreži, kupcima na Mojem računu.
class Racun {
  Racun(this.izvor, this.json);

  final Izvor izvor;
  final Map<String, Object?> json;

  List<Map<String, Object?>> get _stavke =>
      _lista(json[izvor == Izvor.mojaMreza ? 'mjesta' : 'kupci']);

  /// OMM-ovi (Moja mreža) ili ID-evi kupaca (Moj račun), sortirani.
  List<String> get oznake => [
    for (final m in _stavke)
      '${m[izvor == Izvor.mojaMreza ? 'omm' : 'kupac_id']}',
  ]..sort();

  String get kljuc => '${izvor.name}:${oznake.join(',')}';

  DateTime? get dohvaceno => _d(json['dohvaceno']);

  /// Po čemu ga korisnik prepozna: ime ili adresa, i broj mjesta.
  String get naziv {
    final s = _stavke;
    final ime =
        s
            .map((m) => (m['korisnik'] ?? m['ime']) as String?)
            .nonNulls
            .firstOrNull ??
        s.map((m) => m['adresa'] as String?).nonNulls.firstOrNull;
    final broj = s.length == 1
        ? null
        : '${s.length} ${izvor == Izvor.mojaMreza ? 'mjesta' : 'kupaca'}';
    final n = [?ime, ?broj].join(' · ');
    return n.isEmpty ? izvor.naziv : n;
  }

  /// OMM kad račun vidi točno jedno mjesto, za snimak na omm.domovina.ai.
  String? get jediniOmm =>
      _stavke.length == 1 ? _stavke.single['omm'] as String? : null;

  /// Isti račun s mjestom više ili manje.
  bool dijeliMjestaS(Racun d) =>
      d.izvor == izvor && oznake.any(d.oznake.contains);
}

/// Povezani računi, spremljeni na uređaju. Sadrže ime i adresu (ne OIB),
/// pa se brišu u postavkama i kod odjave.
class Spremiste {
  Spremiste._(this._p);

  final SharedPreferences _p;

  static Future<Spremiste> otvori() async {
    final sp = Spremiste._(await SharedPreferences.getInstance());
    await sp._preseli();
    return sp;
  }

  static String _kljuc(Izvor i) => 'racuni-${i.name}';
  static const _poslano = 'poslano';

  /// Do 2026-10-13 je po izvoru stajao jedan uvoz pod `uvoz-<izvor>`.
  Future<void> _preseli() async {
    for (final i in Izvor.values) {
      final stari = _p.getString('uvoz-${i.name}');
      if (stari == null) continue;
      if (_p.getString(_kljuc(i)) == null) {
        final r = Racun(i, jsonDecode(stari) as Map<String, Object?>);
        await _spremi(i, [r]);
        if (_p.getString('poslano-${i.name}') == r.json['dohvaceno']) {
          await oznaciPoslan(r);
        }
      }
      await _p.remove('uvoz-${i.name}');
      await _p.remove('poslano-${i.name}');
    }
  }

  List<Racun> racuni(Izvor i) => [
    for (final j in jsonDecode(_p.getString(_kljuc(i)) ?? '[]') as List)
      Racun(i, (j as Map).cast<String, Object?>()),
  ];

  List<Racun> get sviRacuni => [for (final i in Izvor.values) ...racuni(i)];

  Future<void> _spremi(Izvor i, List<Racun> r) =>
      _p.setString(_kljuc(i), jsonEncode([for (final x in r) x.json]));

  /// Spremi svjež uvoz. Zamjenjuje račun koji se osvježava (`umjesto`) i
  /// svaki koji vidi ista mjesta, jer je to isti račun.
  Future<Racun> spremi(
    Izvor i,
    Map<String, Object?> json, {
    Racun? umjesto,
  }) async {
    final novi = Racun(i, json);
    await _spremi(i, [
      for (final r in racuni(i))
        if (r.kljuc != umjesto?.kljuc && !r.dijeliMjestaS(novi)) r,
      novi,
    ]);
    return novi;
  }

  Future<void> ukloni(Racun r) => _spremi(r.izvor, [
    for (final x in racuni(r.izvor))
      if (x.kljuc != r.kljuc) x,
  ]);

  static String _uvoz(Racun r) => '${r.kljuc}@${r.json['dohvaceno']}';

  Set<String> get _poslani => {...?_p.getStringList(_poslano)};

  /// Je li baš ovaj uvoz (po vremenu dohvata) već na omm.domovina.ai.
  bool poslan(Racun r) => _poslani.contains(_uvoz(r));

  Future<void> oznaciPoslan(Racun r) async {
    final zivi = {for (final x in sviRacuni) _uvoz(x)};
    await _p.setStringList(_poslano, [
      ..._poslani.where(zivi.contains),
      _uvoz(r),
    ]);
  }

  Future<void> obrisi() async {
    for (final i in Izvor.values) {
      await _p.remove(_kljuc(i));
    }
    await _p.remove(_poslano);
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
