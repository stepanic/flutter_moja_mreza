import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_platform_interface.dart';

void main() {
  if (kDebugMode && !kIsWeb) {
    FlutterMojaMrezaPlatform.instance = _SnimanjeHtmla(FlutterMojaMrezaPlatform.instance);
  }
  runApp(const MaterialApp(home: HomePage()));
}

/// Samo debug: sprema sirovi HTML svake stranice u privremeni direktorij
/// (na simulatoru je to direktorij na Macu), za usporedbu s parserom.
/// Sadrži OIB, pa ne ide u repo bez anonimizacije.
class _SnimanjeHtmla extends FlutterMojaMrezaPlatform {
  _SnimanjeHtmla(this._p);

  final FlutterMojaMrezaPlatform _p;

  @override
  Future<String?> getPlatformVersion() => _p.getPlatformVersion();
  @override
  Future<bool> prijava(BuildContext context) => _p.prijava(context);
  @override
  Future<void> napredak(String poruka) => _p.napredak(poruka);
  @override
  Future<void> zatvori() => _p.zatvori();
  @override
  Future<void> odjava() => _p.odjava();

  @override
  Future<HepOdgovor> dohvati(String putanja) async {
    final o = await _p.dohvati(putanja);
    final dir = Directory('${Directory.systemTemp.path}/moja_mreza_html')..createSync();
    final ime = putanja.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    File('${dir.path}/$ime.html').writeAsStringSync(o.html);
    debugPrint('MOJA_MREZA_HTML ${dir.path}/$ime.html (${o.status}, ${o.url})');
    return o;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _mojaMreza = FlutterMojaMreza();
  HepUvoz? _uvoz;
  String? _greska;
  bool _radi = false;

  Future<void> _uvezi() async {
    setState(() {
      _radi = true;
      _greska = null;
    });
    try {
      final uvoz = await _mojaMreza.uvezi(context);
      if (uvoz != null) {
        // Za usporedbu s parserom: cijeli rezultat u konzolu.
        debugPrint(const JsonEncoder.withIndent('  ').convert(uvoz.toJson()));
        setState(() => _uvoz = uvoz);
      }
    } on MojaMrezaIznimka catch (e) {
      setState(() => _greska = e.toString());
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  Future<void> _odjava() async {
    await _mojaMreza.odjava();
    setState(() => _uvoz = null);
  }

  @override
  Widget build(BuildContext context) {
    final uvoz = _uvoz;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moja mreža'),
        actions: [
          IconButton(
            tooltip: 'Odjava',
            onPressed: _radi ? null : _odjava,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _radi ? null : _uvezi,
        icon: _radi
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(),
              )
            : const Icon(Icons.download),
        label: const Text('Uvezi s Moje mreže'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (_greska != null)
            Text(
              _greska!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (uvoz == null && _greska == null)
            const Text(
              'Prijava ide preko e-Građana (Certilia). Podaci se parsiraju na uređaju.',
            ),
          if (uvoz != null)
            for (final m in uvoz.mjesta) _MjernoMjesto(m),
        ],
      ),
    );
  }
}

class _MjernoMjesto extends StatelessWidget {
  const _MjernoMjesto(this.m);

  final HepMjernoMjesto m;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    String d(DateTime x) => '${x.day}.${x.month}.${x.year}.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('OMM ${m.omm.omm}', style: tema.titleMedium),
            Text(
              [
                m.omm.adresa,
                m.omm.tarifniModel,
                'brojilo ${m.omm.brojBrojila}',
              ].whereType<String>().join(' · '),
            ),
            const SizedBox(height: 12),
            Text('Očitanja (${m.ocitanja.length})', style: tema.titleSmall),
            for (final o in m.ocitanja.take(5))
              Text('${d(o.datum)}  T1 ${o.t1}  T2 ${o.t2 ?? '–'}  ${o.opis}'),
            const SizedBox(height: 12),
            Text(
              'Potrošnja (${m.potrosnja.length} razdoblja)',
              style: tema.titleSmall,
            ),
            for (final p in m.potrosnja.take(5))
              Text(
                '${d(p.od)}–${d(p.doDatuma)}  ${p.ukupno} kWh (T1 ${p.t1}, T2 ${p.t2 ?? '–'})',
              ),
          ],
        ),
      ),
    );
  }
}
