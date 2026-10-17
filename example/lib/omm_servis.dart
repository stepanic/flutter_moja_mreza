import 'dart:convert';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Klijent za https://omm.domovina.ai (repo `domovinatv/omm.domovina.ai`).
///
/// Prijave još nema: aplikacija generira nasumični ključ uređaja i šalje ga
/// kao `Authorization: Bearer`. Tko zna ključ, vidi snimke.
class OmmServis {
  OmmServis._(this.kljuc);

  static final baza = Uri.parse('https://omm.domovina.ai');

  final String kljuc;

  static Future<OmmServis> otvori() async {
    final p = await SharedPreferences.getInstance();
    var k = p.getString('omm-kljuc');
    if (k == null) {
      final r = Random.secure();
      k = base64Url
          .encode(List.generate(18, (_) => r.nextInt(256)))
          .replaceAll('=', '');
      await p.setString('omm-kljuc', k);
    }
    return OmmServis._(k);
  }

  Map<String, String> get _auth => {'Authorization': 'Bearer $kljuc'};

  /// Popis snimaka u pregledniku, s ključem ovog uređaja u fragmentu, koji ne
  /// ide serveru ni u logove (SEC-04 u omm.domovina.ai).
  Uri get webPopis => baza.replace(fragment: 'k=$kljuc');

  /// Slika zaslona → prijedlog 1.8.1 / 1.8.2.
  /// [omm] služi za usporedbu sa zadnjim stanjem tog mjernog mjesta.
  Future<OcrOdgovor> ocitaj(List<int> jpeg, {String? omm}) async {
    final z = http.MultipartRequest('POST', baza.resolve('/api/ocitaj'))
      ..headers.addAll(_auth)
      ..fields.addAll({'omm': ?omm})
      ..files.add(
        // Bez contentType Dart šalje application/octet-stream.
        http.MultipartFile.fromBytes(
          'slika',
          jpeg,
          filename: 'brojilo.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    final o = await http.Response.fromStream(await z.send());
    final j = jsonDecode(o.body) as Map<String, Object?>;
    if (o.statusCode != 200) {
      throw OmmGreska(j['greska'] as String? ?? 'HTTP ${o.statusCode}', j);
    }
    return OcrOdgovor(j);
  }

  /// Sprema snimak; vraća njegov id. Server prepoznaje isti sadržaj i tada
  /// vraća postojeći snimak (200, `duplikat: true`) umjesto novog.
  Future<String> spremi(Map<String, Object?> snimak) async {
    final o = await http.post(
      baza.resolve('/api/snimak'),
      headers: {..._auth, 'Content-Type': 'application/json'},
      body: jsonEncode(snimak),
    );
    final j = jsonDecode(o.body) as Map<String, Object?>;
    if (o.statusCode != 201 && o.statusCode != 200) {
      throw OmmGreska(j['greska'] as String? ?? 'HTTP ${o.statusCode}', j);
    }
    return j['id'] as String;
  }

  /// Bilježi odgovor HEP-a uz već spremljeni snimak.
  Future<void> zabiljeziDostavu(
    String id,
    Map<String, Object?> hep, {
    String? omm,
  }) async {
    final o = await http.patch(
      baza.resolve('/api/snimak/$id'),
      headers: {..._auth, 'Content-Type': 'application/json'},
      body: jsonEncode({'hep_dostava': hep, 'omm': ?omm}),
    );
    if (o.statusCode != 200) throw OmmGreska('HTTP ${o.statusCode}', o.body);
  }
}

class OcrOdgovor {
  OcrOdgovor(this.json);

  final Map<String, Object?> json;

  String? get slika => json['slika'] as String?;
  int? get t1 => (json['t1'] as num?)?.toInt();
  int? get t2 => (json['t2'] as num?)?.toInt();

  /// Vrijednost bez sigurne oznake tarife.
  int? get neodredeno => (json['neodredeno'] as num?)?.toInt();
  String? get napomena => json['napomena'] as String?;

  /// Npr. ispravljen decimalni zarez ili tarifa određena usporedbom.
  List<String> get upozorenja => [
    for (final u in json['upozorenja'] as List? ?? const []) '$u',
  ];

  /// Zadnje poznato stanje (uvoz s HEP-a ili prihvaćena dostava).
  ZadnjeStanje? get zadnje => switch (json['zadnje']) {
    final Map<String, Object?> z => ZadnjeStanje(
      t1: (z['t1'] as num?)?.toInt(),
      t2: (z['t2'] as num?)?.toInt(),
      datum: z['datum'] as String? ?? '',
    ),
    _ => null,
  };
}

class ZadnjeStanje {
  const ZadnjeStanje({this.t1, this.t2, required this.datum});

  final int? t1;
  final int? t2;
  final String datum;
}

class OmmGreska implements Exception {
  OmmGreska(this.poruka, [this.detalji]);

  final String poruka;
  final Object? detalji;

  @override
  String toString() => poruka;
}

/// Trenutna lokacija ili `null` ako je korisnik ne dopusti.
Future<Position?> lokacija() async {
  if (!await Geolocator.isLocationServiceEnabled()) return null;
  var d = await Geolocator.checkPermission();
  if (d == LocationPermission.denied) d = await Geolocator.requestPermission();
  if (d == LocationPermission.denied || d == LocationPermission.deniedForever) {
    return null;
  }
  return Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: 20),
    ),
  );
}

Map<String, Object?>? lokacijaJson(Position? p) => p == null
    ? null
    : {'lat': p.latitude, 'lon': p.longitude, 'tocnost_m': p.accuracy};
