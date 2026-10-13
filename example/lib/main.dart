import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ocitaj_stranica.dart';
import 'omm_servis.dart';

void main() {
  if (kDebugMode && !kIsWeb) {
    FlutterMojaMrezaPlatform.instance = _SnimanjeHtmla(
      FlutterMojaMrezaPlatform.instance,
    );
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
  Future<bool> prijava(
    BuildContext context, {
    HepPortal portal = HepPortal.mojaMreza,
  }) => _p.prijava(context, portal: portal);
  @override
  Future<HepStanje> stanje() => _p.stanje();
  @override
  Future<void> napredak(String poruka) => _p.napredak(poruka);
  @override
  Future<void> zatvori() => _p.zatvori();
  @override
  Future<void> odjava() => _p.odjava();

  @override
  Future<HepOdgovor> dohvati(
    String putanja, {
    Map<String, String>? forma,
  }) async {
    final o = await _p.dohvati(putanja, forma: forma);
    final dir = Directory('${Directory.systemTemp.path}/moja_mreza_html')
      ..createSync();
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

  /// Uvoz koji je već poslan na omm.domovina.ai, da gumb ne šalje opet.
  HepUvoz? _poslanUvoz;
  MojRacunUvoz? _racun;
  MojRacunUvoz? _poslanRacun;
  String? _greska;
  bool _radi = false;

  /// Nakon uvoza sam pošalji snimak na omm.domovina.ai. Isto kao kvačica u
  /// extensionu: uključeno dok je korisnik ne isključi, pamti se.
  bool _autoSlanje = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _autoSlanje = p.getBool('auto-omm') ?? true);
    });
  }

  Future<void> _postaviAutoSlanje(bool v) async {
    setState(() => _autoSlanje = v);
    await (await SharedPreferences.getInstance()).setBool('auto-omm', v);
  }

  Future<void> _uvezi() async {
    HepUvoz? novi;
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
        novi = uvoz;
      }
    } on MojaMrezaIznimka catch (e) {
      setState(() => _greska = e.toString());
    } finally {
      if (mounted) setState(() => _radi = false);
    }
    // Nakon duge prijave rijetko tko još klikne gumb, pa slanje kreće samo.
    if (novi != null && _autoSlanje && mounted) await _posaljiSnimak();
  }

  /// Uvoz s Mojeg računa HEP Elektre (korisničko ime i lozinka).
  Future<void> _uveziRacun() async {
    MojRacunUvoz? novi;
    setState(() {
      _radi = true;
      _greska = null;
    });
    try {
      final racun = await _mojaMreza.uveziMojRacun(context);
      if (racun != null) {
        debugPrint(const JsonEncoder.withIndent('  ').convert(racun.toJson()));
        setState(() => _racun = racun);
        novi = racun;
      }
    } on MojaMrezaIznimka catch (e) {
      setState(() => _greska = e.toString());
    } finally {
      if (mounted) setState(() => _radi = false);
    }
    if (novi != null && _autoSlanje && mounted) await _posaljiRacun();
  }

  /// Uvoz s Moje mreže kao snimak `hep`.
  Future<void> _posaljiSnimak() async {
    final uvoz = _uvoz;
    if (uvoz == null) return;
    if (await _spremi(
      'hep',
      uvoz.mjesta.length == 1 ? uvoz.mjesta.single.omm.omm : null,
      uvoz.toJson(),
    )) {
      setState(() => _poslanUvoz = uvoz);
    }
  }

  /// Uvoz s Mojeg računa kao snimak `hep-moj-racun`.
  Future<void> _posaljiRacun() async {
    final racun = _racun;
    if (racun == null) return;
    if (await _spremi(
      'hep-moj-racun',
      racun.kupci.length == 1 ? racun.kupci.single.zaglavlje.omm : null,
      racun.toJson(),
    )) {
      setState(() => _poslanRacun = racun);
    }
  }

  /// Snimak na omm.domovina.ai, uz lokaciju ako je dopuštena.
  Future<bool> _spremi(
    String izvor,
    String? omm,
    Map<String, Object?> uvoz,
  ) async {
    setState(() => _radi = true);
    try {
      final servis = await OmmServis.otvori();
      final p = await lokacija().catchError((_) => null);
      await servis.spremi({
        'izvor': izvor,
        'omm': omm,
        'uvoz': uvoz,
        'lokacija': lokacijaJson(p),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Snimak spremljen na omm.domovina.ai ✓'),
          ),
        );
      }
      return true;
    } catch (e) {
      setState(() => _greska = 'Slanje snimka nije uspjelo: $e');
      return false;
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  Future<void> _mojaOcitanja() async {
    final servis = await OmmServis.otvori();
    await launchUrl(servis.webPopis, mode: LaunchMode.externalApplication);
  }

  Future<void> _odjava() async {
    await _mojaMreza.odjava();
    setState(() {
      _uvoz = null;
      _racun = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uvoz = _uvoz;
    final racun = _racun;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Moja mreža'),
        actions: [
          IconButton(
            tooltip: 'Moja očitanja (web)',
            onPressed: _mojaOcitanja,
            icon: const Icon(Icons.history),
          ),
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
          Card(
            child: ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Očitaj brojilo'),
              subtitle: const Text('Uslikaj zaslon, provjeri 1.8.1 i 1.8.2'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OcitajStranica(
                    omms: [
                      for (final m in uvoz?.mjesta ?? const <HepMjernoMjesto>[])
                        m.omm.omm,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Uvezi s Mojeg računa'),
              subtitle: const Text(
                'HEP Elektra: računi, uplate, očitanja (korisničko ime i lozinka)',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _radi ? null : _uveziRacun,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoSlanje,
            onChanged: _radi ? null : _postaviAutoSlanje,
            title: const Text('Nakon uvoza pošalji na omm.domovina.ai'),
            subtitle: const Text(
              'Mjesta, očitanja i potrošnja, uz lokaciju ako je dopustiš',
            ),
          ),
          if (uvoz == null && _greska == null)
            const Text(
              'Prijava ide preko e-Građana (Certilia). Podaci se parsiraju na uređaju.',
            ),
          if (uvoz != null) ...[
            for (final m in uvoz.mjesta) _MjernoMjesto(m),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _radi || identical(_poslanUvoz, uvoz)
                  ? null
                  : _posaljiSnimak,
              icon: Icon(
                identical(_poslanUvoz, uvoz)
                    ? Icons.cloud_done
                    : Icons.cloud_upload,
              ),
              label: Text(
                identical(_poslanUvoz, uvoz)
                    ? 'Snimak je na omm.domovina.ai ✓'
                    : 'Pošalji snimak na omm.domovina.ai',
              ),
            ),
          ],
          if (racun != null) ...[
            for (final k in racun.kupci) _Kupac(k),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _radi || identical(_poslanRacun, racun)
                  ? null
                  : _posaljiRacun,
              icon: Icon(
                identical(_poslanRacun, racun)
                    ? Icons.cloud_done
                    : Icons.cloud_upload,
              ),
              label: Text(
                identical(_poslanRacun, racun)
                    ? 'Moj račun je na omm.domovina.ai ✓'
                    : 'Pošalji Moj račun na omm.domovina.ai',
              ),
            ),
          ],
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

class _Kupac extends StatelessWidget {
  const _Kupac(this.k);

  final MojRacunKupac k;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    String d(DateTime? x) => x == null ? '–' : '${x.day}.${x.month}.${x.year}.';
    String eur(num? v) => v == null ? '–' : '${v.toStringAsFixed(2)} €';
    final z = k.zaglavlje;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(z.ime ?? 'Kupac ${k.kupacId}', style: tema.titleMedium),
            Text(
              [
                if (z.omm != null) 'OMM ${z.omm}',
                z.adresa,
                if (z.ugovorniRacun != null)
                  'ugovorni račun ${z.ugovorniRacun}',
              ].whereType<String>().join(' · '),
            ),
            if (k.saldoOpis != null || k.saldo != null)
              Text('${k.saldoOpis ?? 'Saldo'} ${eur(k.saldo)}'),
            const SizedBox(height: 12),
            Text('Promet (${k.promet.length})', style: tema.titleSmall),
            for (final s in k.promet.take(5))
              Text(
                '${d(s.datum)}  ${s.opis}  ${eur(s.duguje > 0 ? s.duguje : s.potrazuje)}',
              ),
            const SizedBox(height: 12),
            Text('Očitanja (${k.ocitanja.length})', style: tema.titleSmall),
            for (final o in k.ocitanja.take(5))
              Text('${d(o.datum)}  T1 ${o.t1}  T2 ${o.t2 ?? '–'}  ${o.opis}'),
          ],
        ),
      ),
    );
  }
}
