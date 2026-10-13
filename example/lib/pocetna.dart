import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';

import 'mjesto_stranica.dart';
import 'ocitaj_stranica.dart';
import 'omm_servis.dart';
import 'podaci.dart';
import 'postavke.dart';
import 'tema.dart';
import 'widgets.dart';

class Pocetna extends StatefulWidget {
  const Pocetna({super.key});

  @override
  State<Pocetna> createState() => _PocetnaState();
}

class _PocetnaState extends State<Pocetna> {
  final _mojaMreza = FlutterMojaMreza();
  Spremiste? _sp;
  var _racuni = <Racun>[];
  String? _greska;

  /// Što se upravo radi; `null` kad ništa.
  String? _radi;

  @override
  void initState() {
    super.initState();
    Spremiste.otvori().then((sp) {
      if (!mounted) return;
      setState(() {
        _sp = sp;
        _racuni = sp.sviRacuni;
      });
    });
  }

  List<Mjesto> get _mjesta => spojiMjesta(
    hep: [
      for (final r in _racuni)
        if (r.izvor == Izvor.mojaMreza) r.json,
    ],
    racun: [
      for (final r in _racuni)
        if (r.izvor == Izvor.mojRacun) r.json,
    ],
  );

  Future<void> _uvezi(Izvor izvor, {Racun? umjesto}) async {
    if (_radi != null) return;
    await _uvoz(izvor, umjesto: umjesto);
  }

  /// Jedan po jedan račun; svaki traži svoju prijavu. Odustajanje od
  /// prijave prekida niz.
  Future<void> _osvjeziSve() async {
    if (_radi != null) return;
    final svi = [..._racuni];
    for (final (n, r) in svi.indexed) {
      final ok = await _uvoz(
        r.izvor,
        umjesto: r,
        poruka: 'Prijavi se kao ${r.naziv} (${n + 1}/${svi.length})…',
      );
      if (!ok || !mounted) return;
    }
  }

  /// `false` kad prijava nije dovršena ili uvoz nije uspio.
  Future<bool> _uvoz(Izvor izvor, {Racun? umjesto, String? poruka}) async {
    final sp = _sp;
    if (sp == null) return false;
    Racun? novi;
    setState(() {
      _radi =
          poruka ??
          'Uvoz s ${izvor == Izvor.mojaMreza ? 'Moje mreže' : 'Mojeg računa'}…';
      _greska = null;
    });
    try {
      final json = await (izvor == Izvor.mojaMreza
          ? _mojaMreza.uvezi(context).then((u) => u?.toJson())
          : _mojaMreza.uveziMojRacun(context).then((u) => u?.toJson()));
      if (json != null) {
        // Za usporedbu s parserom: cijeli rezultat u konzolu.
        debugPrint(const JsonEncoder.withIndent('  ').convert(json));
        novi = await sp.spremi(izvor, json, umjesto: umjesto);
        setState(() => _racuni = sp.sviRacuni);
      }
    } on MojaMrezaIznimka catch (e) {
      setState(() => _greska = e.toString());
    } finally {
      if (mounted) setState(() => _radi = null);
    }
    // Nakon duge prijave rijetko tko još klikne gumb, pa slanje kreće samo.
    if (novi != null && sp.autoSlanje && mounted) await _posalji(novi);
    return novi != null;
  }

  Future<void> _ukloni(Racun r) async {
    final sp = _sp;
    if (sp == null) return;
    await sp.ukloni(r);
    setState(() => _racuni = sp.sviRacuni);
  }

  /// Snimak na omm.domovina.ai, uz lokaciju ako je dopuštena.
  Future<void> _posalji(Racun r) async {
    final sp = _sp;
    if (sp == null) return;
    setState(() => _radi = 'Šaljem na omm.domovina.ai…');
    try {
      final servis = await OmmServis.otvori();
      final p = await lokacija().catchError((_) => null);
      await servis.spremi({
        'izvor': r.izvor == Izvor.mojaMreza ? 'hep' : 'hep-moj-racun',
        'omm': r.jediniOmm,
        'uvoz': r.json,
        'lokacija': lokacijaJson(p),
      });
      await sp.oznaciPoslan(r);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snimak spremljen na omm.domovina.ai')),
        );
      }
    } catch (e) {
      setState(() => _greska = 'Slanje snimka nije uspjelo: $e');
    } finally {
      if (mounted) setState(() => _radi = null);
    }
  }

  void _ocitaj([String? omm]) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => OcitajStranica(
        mjesta: [
          for (final m in _mjesta)
            if (m.imaOmm) m,
        ],
        omm: omm,
      ),
    ),
  );

  void _otvori(Mjesto m) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MjestoStranica(m, onOcitaj: () => _ocitaj(m.omm)),
    ),
  );

  Future<void> _postavke() async {
    final sp = _sp;
    if (sp == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Postavke(
          sp: sp,
          onObrisi: () async {
            await _mojaMreza.odjava();
            await sp.obrisi();
            setState(() => _racuni = []);
          },
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sp = _sp;
    final mjesta = _mjesta;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const DomovinaNaslov(),
        actions: [
          IconButton(
            tooltip: 'Postavke',
            onPressed: _postavke,
            icon: const Icon(Icons.tune),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: _radi == null
              ? const SizedBox(height: 2)
              : const LinearProgressIndicator(minHeight: 2),
        ),
      ),
      body: sp == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                if (_radi != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_radi!, style: t.bodySmall),
                  ),
                if (_greska != null)
                  Obavijest(
                    _greska!,
                    onZatvori: () => setState(() => _greska = null),
                  ),
                if (_racuni.isEmpty)
                  _Dobrodoslica(
                    zauzeto: _radi != null,
                    onUvezi: _uvezi,
                    onOcitaj: _ocitaj,
                  )
                else ...[
                  Oznaka(
                    mjesta.length == 1
                        ? 'Moje mjesto'
                        : 'Moja mjesta (${mjesta.length})',
                  ),
                  for (final m in mjesta) ...[
                    _MjestoKartica(
                      m,
                      onOtvori: () => _otvori(m),
                      onOcitaj: () => _ocitaj(m.omm),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Oznaka(
                    _racuni.length == 1
                        ? 'Povezani račun'
                        : 'Povezani računi (${_racuni.length})',
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final (n, r) in _racuni.indexed) ...[
                          if (n > 0) const Divider(indent: 16, endIndent: 16),
                          _RacunRed(
                            r,
                            poslan: sp.poslan(r),
                            zauzeto: _radi != null,
                            onOsvjezi: () => _uvezi(r.izvor, umjesto: r),
                            onPosalji: () => _posalji(r),
                            onUkloni: () => _ukloni(r),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final i in Izvor.values)
                        TextButton.icon(
                          onPressed: _radi != null ? null : () => _uvezi(i),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(i.naziv),
                        ),
                      if (_racuni.length > 1)
                        TextButton.icon(
                          onPressed: _radi != null ? null : _osvjeziSve,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Osvježi sve'),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'HEP podaci se čitaju i obrađuju na ovom uređaju. '
                  'Prijava se briše nakon svakog uvoza.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall,
                ),
              ],
            ),
    );
  }
}

class _Dobrodoslica extends StatelessWidget {
  const _Dobrodoslica({
    required this.zauzeto,
    required this.onUvezi,
    required this.onOcitaj,
  });

  final bool zauzeto;
  final ValueChanged<Izvor> onUvezi;
  final VoidCallback onOcitaj;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Text('Tvoja struja,\nna jednom mjestu.', style: t.displaySmall),
        const SizedBox(height: 12),
        Text(
          'Uvezi mjerna mjesta, očitanja, potrošnju i račune s HEP-ovih '
          'portala, pa očitaj brojilo jednom slikom.',
          style: t.bodyLarge?.copyWith(color: Boje.inkSoft),
        ),
        const Oznaka('Poveži izvor'),
        _IzvorKartica(
          ikona: Icons.bolt,
          naslov: 'Moja mreža',
          opis:
              'HEP ODS: mjerna mjesta, očitanja i potrošnja. '
              'Prijava preko e-Građana (Certilia).',
          gumb: FilledButton(
            onPressed: zauzeto ? null : () => onUvezi(Izvor.mojaMreza),
            child: const Text('Uvezi s Moje mreže'),
          ),
        ),
        const SizedBox(height: 12),
        _IzvorKartica(
          ikona: Icons.receipt_long_outlined,
          naslov: 'Moj račun',
          opis:
              'HEP Elektra: računi, uplate i očitanja. '
              'Korisničko ime i lozinka.',
          gumb: OutlinedButton(
            onPressed: zauzeto ? null : () => onUvezi(Izvor.mojRacun),
            child: const Text('Uvezi s Mojeg računa'),
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: onOcitaj,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Samo očitaj brojilo'),
        ),
      ],
    );
  }
}

class _IzvorKartica extends StatelessWidget {
  const _IzvorKartica({
    required this.ikona,
    required this.naslov,
    required this.opis,
    required this.gumb,
  });

  final IconData ikona;
  final String naslov;
  final String opis;
  final Widget gumb;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Boje.sand,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(ikona, color: Boje.navy, size: 20),
                ),
                const SizedBox(width: 12),
                Text(naslov, style: t.titleLarge),
              ],
            ),
            const SizedBox(height: 10),
            Text(opis),
            const SizedBox(height: 14),
            gumb,
          ],
        ),
      ),
    );
  }
}

class _MjestoKartica extends StatelessWidget {
  const _MjestoKartica(
    this.m, {
    required this.onOtvori,
    required this.onOcitaj,
  });

  final Mjesto m;
  final VoidCallback onOtvori;
  final VoidCallback onOcitaj;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = m.zadnjeOcitanje;
    final p = m.zadnjeRazdoblje;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOtvori,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.naslov, style: t.titleLarge),
                        const SizedBox(height: 2),
                        Text(
                          [if (m.imaOmm) 'OMM ${m.omm}', ?m.tarifa].join(' · '),
                          style: t.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Boje.inkMuted),
                ],
              ),
              if (o != null || p != null) ...[
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (o != null)
                        Expanded(
                          child: BrojPlocica(
                            oznaka: 'Stanje brojila',
                            vrijednost: Hr.broj(o.t1),
                            jedinica: o.t2 == null ? 'kWh' : 'T1',
                            ispod: [
                              if (o.t2 != null) 'T2 ${Hr.broj(o.t2)}',
                              Hr.kratko(o.datum),
                            ].join(' · '),
                          ),
                        ),
                      if (o != null && p != null) const SizedBox(width: 10),
                      if (p != null)
                        Expanded(
                          child: BrojPlocica(
                            energija: true,
                            oznaka: Hr.razdoblje(p),
                            vrijednost: Hr.broj(p.ukupno),
                            jedinica: 'kWh',
                            ispod: '${Hr.broj(p.ukupno / p.dana)} kWh/dan',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (m.saldo != null || m.saldoOpis != null) ...[
                const SizedBox(height: 14),
                SaldoRed(m),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (m.imaOmm)
                    FilledButton.icon(
                      onPressed: onOcitaj,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Očitaj brojilo'),
                    ),
                  const Spacer(),
                  Text(
                    m.izvori.map((i) => i.naziv).join(' + '),
                    style: t.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RacunRed extends StatelessWidget {
  const _RacunRed(
    this.r, {
    required this.poslan,
    required this.zauzeto,
    required this.onOsvjezi,
    required this.onPosalji,
    required this.onUkloni,
  });

  final Racun r;
  final bool poslan;
  final bool zauzeto;
  final VoidCallback onOsvjezi;
  final VoidCallback onPosalji;
  final VoidCallback onUkloni;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kada = r.dohvaceno;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
      child: Row(
        children: [
          Icon(
            r.izvor == Izvor.mojaMreza
                ? Icons.bolt
                : Icons.receipt_long_outlined,
            color: Boje.navy,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.naziv, style: t.titleMedium),
                Text(
                  [
                    r.izvor.naziv,
                    if (kada != null) 'uvezeno ${Hr.prije(kada.toLocal())}',
                  ].join(' · '),
                  style: t.bodySmall,
                ),
                poslan
                    ? Text(
                        'Na omm.domovina.ai',
                        style: t.bodySmall?.copyWith(color: Boje.forest),
                      )
                    : GestureDetector(
                        onTap: zauzeto ? null : onPosalji,
                        child: Text(
                          'Pošalji na omm.domovina.ai',
                          style: t.bodySmall?.copyWith(
                            color: Boje.teal,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
              ],
            ),
          ),
          TextButton(
            onPressed: zauzeto ? null : onOsvjezi,
            child: const Text('Osvježi'),
          ),
          PopupMenuButton<VoidCallback>(
            enabled: !zauzeto,
            tooltip: 'Više',
            onSelected: (f) => f(),
            itemBuilder: (_) => [
              PopupMenuItem(value: onUkloni, child: const Text('Ukloni račun')),
            ],
          ),
        ],
      ),
    );
  }
}
