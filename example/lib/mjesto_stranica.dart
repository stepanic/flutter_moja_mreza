import 'package:flutter/material.dart';

import 'podaci.dart';
import 'tema.dart';
import 'widgets.dart';

/// Jedno mjerno mjesto: potrošnja s grafom, sva očitanja i promet.
class MjestoStranica extends StatelessWidget {
  const MjestoStranica(this.m, {super.key, required this.onOcitaj});

  final Mjesto m;
  final VoidCallback onOcitaj;

  @override
  Widget build(BuildContext context) {
    final kartice = [
      if (m.potrosnja.isNotEmpty) ('Potrošnja', _Potrosnja(m)),
      if (m.ocitanja.isNotEmpty) ('Očitanja', _Ocitanja(m)),
      if (m.promet.isNotEmpty) ('Računi', _Promet(m)),
    ];
    final t = Theme.of(context).textTheme;
    final tabovi = kartice.length < 2
        ? null
        : TabBar(tabs: [for (final (n, _) in kartice) Tab(text: n)]);
    return DefaultTabController(
      length: kartice.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(m.naslov, overflow: TextOverflow.ellipsis),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(
              44 + (tabovi?.preferredSize.height ?? 0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 44,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    [
                      if (m.imaOmm) 'OMM ${m.omm}',
                      ?m.tarifa,
                      if (m.brojBrojila != null) 'brojilo ${m.brojBrojila}',
                      if (m.ugovorniRacun != null)
                        'ug. račun ${m.ugovorniRacun}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall,
                  ),
                ),
                ?tabovi,
              ],
            ),
          ),
        ),
        bottomNavigationBar: m.imaOmm
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton.icon(
                    onPressed: onOcitaj,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Očitaj brojilo'),
                  ),
                ),
              )
            : null,
        body: kartice.isEmpty
            ? const Center(child: Text('Nema podataka za prikaz.'))
            : TabBarView(children: [for (final (_, w) in kartice) w]),
      ),
    );
  }
}

class _Potrosnja extends StatelessWidget {
  const _Potrosnja(this.m);

  final Mjesto m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GrafPotrosnje(m.potrosnja),
          ),
        ),
        const Oznaka('Sva razdoblja'),
        Card(
          child: Column(
            children: [
              for (final (i, p) in m.potrosnja.indexed) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                ListTile(
                  title: Text(Hr.razdoblje(p)),
                  subtitle: Text(
                    [
                      if (p.t2 != null)
                        'T1 ${Hr.broj(p.t1)} · T2 ${Hr.broj(p.t2)}',
                      if (p.predano > 0) 'predano ${Hr.broj(p.predano)} kWh',
                    ].join(' · '),
                    style: t.bodySmall?.copyWith(fontFeatures: tabularno),
                  ),
                  trailing: Text(
                    '${Hr.broj(p.ukupno)} kWh',
                    style: t.titleMedium?.copyWith(fontFeatures: tabularno),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Ocitanja extends StatelessWidget {
  const _Ocitanja(this.m);

  final Mjesto m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final broj = t.bodyLarge?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: tabularno,
    );
    final dvotarifno = m.ocitanja.any((o) => o.t2 != null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Expanded(child: Text('Datum')),
                    const SizedBox(
                      width: 84,
                      child: Text('T1', textAlign: TextAlign.end),
                    ),
                    if (dvotarifno)
                      const SizedBox(
                        width: 84,
                        child: Text('T2', textAlign: TextAlign.end),
                      ),
                  ],
                ),
              ),
              const Divider(),
              for (final (i, o) in m.ocitanja.indexed) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(Hr.datum(o.datum), style: t.bodyLarge),
                            Text(o.opis, style: t.bodySmall),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          Hr.broj(o.t1),
                          textAlign: TextAlign.end,
                          style: broj,
                        ),
                      ),
                      if (dvotarifno)
                        SizedBox(
                          width: 84,
                          child: Text(
                            Hr.broj(o.t2),
                            textAlign: TextAlign.end,
                            style: broj,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Promet extends StatelessWidget {
  const _Promet(this.m);

  final Mjesto m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (m.saldo != null || m.saldoOpis != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SaldoRed(m),
            ),
          ),
        const Oznaka('Računi i uplate'),
        Card(
          child: Column(
            children: [
              for (final (i, s) in m.promet.indexed) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: s.racun ? Boje.sand : Boje.forestSoft,
                    child: Icon(
                      s.racun ? Icons.receipt_long_outlined : Icons.south_west,
                      size: 18,
                      color: s.racun ? Boje.inkSoft : Boje.forest,
                    ),
                  ),
                  title: Text(s.opis),
                  subtitle: Text(
                    [
                      Hr.datum(s.datum),
                      if (s.racun && s.dospijeva != null)
                        'rok ${Hr.kratko(s.dospijeva!)}',
                    ].join(' · '),
                    style: t.bodySmall,
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${s.racun ? '' : '+'}${Hr.eur(s.iznos)}',
                        style: t.titleMedium?.copyWith(
                          fontFeatures: tabularno,
                          color: s.racun ? Boje.ink : Boje.forest,
                        ),
                      ),
                      if (s.racun && s.status == 'RED')
                        Text(
                          'otvoren',
                          style: t.bodySmall?.copyWith(color: Boje.rust),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
