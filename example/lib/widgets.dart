import 'dart:math';

import 'package:flutter/material.dart';

import 'podaci.dart';
import 'tema.dart';

/// Logo Domovina Energy iz mediakit.domovina.tv.
class DomovinaLogo extends StatelessWidget {
  const DomovinaLogo({super.key, this.velicina = 32});

  final double velicina;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(velicina * 0.16),
    child: Image.asset(
      'assets/images/domovina_energy.png',
      width: velicina,
      height: velicina,
      semanticLabel: 'Domovina Energy',
    ),
  );
}

/// Logo + ime u AppBaru.
class DomovinaNaslov extends StatelessWidget {
  const DomovinaNaslov({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const DomovinaLogo(),
      const SizedBox(width: 10),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Domovina '),
            TextSpan(
              text: 'Energy',
              style: TextStyle(color: Boje.forest),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Mala oznaka iznad sekcije, verzalom.
class Oznaka extends StatelessWidget {
  const Oznaka(this.tekst, {super.key, this.desno});

  final String tekst;
  final Widget? desno;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            tekst.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        ?desno,
      ],
    ),
  );
}

/// Brojka s oznakom; na jantarnoj podlozi kad nosi kWh.
class BrojPlocica extends StatelessWidget {
  const BrojPlocica({
    super.key,
    required this.oznaka,
    required this.vrijednost,
    this.jedinica,
    this.ispod,
    this.energija = false,
  });

  final String oznaka;
  final String vrijednost;
  final String? jedinica;
  final String? ispod;
  final bool energija;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final boja = energija ? Boje.solarInk : Boje.inkMuted;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: energija ? Boje.solarSoft : Boje.sand,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(oznaka, style: t.bodySmall?.copyWith(color: boja)),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: vrijednost),
                if (jedinica != null)
                  TextSpan(
                    text: ' $jedinica',
                    style: t.bodyMedium?.copyWith(color: boja),
                  ),
              ],
            ),
            style: t.headlineSmall?.copyWith(
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: tabularno,
            ),
          ),
          if (ispod != null) ...[
            const SizedBox(height: 2),
            Text(ispod!, style: t.bodySmall?.copyWith(color: boja)),
          ],
        ],
      ),
    );
  }
}

/// Stanje računa: dug crveno, sve plaćeno zeleno, otvoreni račun s rokom.
class SaldoRed extends StatelessWidget {
  const SaldoRed(this.m, {super.key});

  final Mjesto m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final dug = (m.saldo ?? 0) > 0;
    final otvoren = m.otvoreniRacun;
    final (ikona, boja, tekst) = dug
        ? (Icons.error_outline, Boje.rust, 'Dospjeli dug ${Hr.eur(m.saldo)}')
        : (Icons.check_circle_outline, Boje.forest, 'Nema dospjelog duga');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(ikona, size: 18, color: boja),
            const SizedBox(width: 8),
            Text(
              tekst,
              style: t.bodyMedium?.copyWith(
                color: boja,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (otvoren != null)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text(
              'Račun ${Hr.eur(otvoren.iznos)}'
              '${otvoren.dospijeva == null ? '' : ', dospijeva ${Hr.datum(otvoren.dospijeva)}'}',
              style: t.bodySmall?.copyWith(color: Boje.inkMuted),
            ),
          ),
      ],
    );
  }
}

/// Traka za grešku ili obavijest, s gumbom za zatvaranje.
class Obavijest extends StatelessWidget {
  const Obavijest(this.tekst, {super.key, this.onZatvori});

  final String tekst;
  final VoidCallback? onZatvori;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Boje.rust, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tekst, style: const TextStyle(color: Boje.rust)),
        ),
        if (onZatvori != null)
          IconButton(
            onPressed: onZatvori,
            icon: const Icon(Icons.close, size: 18),
            color: Boje.rust,
            tooltip: 'Zatvori',
          ),
      ],
    ),
  );
}

/// Stupčasti graf potrošnje po razdobljima (T1 i T2 složeno), najstarije
/// lijevo. Dodir na stupac pokazuje njegove brojke.
class GrafPotrosnje extends StatefulWidget {
  const GrafPotrosnje(this.razdoblja, {super.key, this.najvise = 12});

  /// Najnovije prvo, kao u [Mjesto.potrosnja].
  final List<Razdoblje> razdoblja;
  final int najvise;

  @override
  State<GrafPotrosnje> createState() => _GrafPotrosnjeState();
}

class _GrafPotrosnjeState extends State<GrafPotrosnje> {
  int? _odabran;

  @override
  Widget build(BuildContext context) {
    final r = widget.razdoblja.take(widget.najvise).toList().reversed.toList();
    if (r.isEmpty) return const SizedBox.shrink();
    final i = (_odabran ?? r.length - 1).clamp(0, r.length - 1);
    final o = r[i];
    final t = Theme.of(context).textTheme;
    final dvotarifno = r.any((x) => (x.t2 ?? 0) > 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(Hr.razdoblje(o), style: t.bodySmall),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: Hr.broj(o.ukupno)),
              TextSpan(
                text: ' kWh',
                style: t.bodyMedium?.copyWith(color: Boje.inkMuted),
              ),
            ],
          ),
          style: t.headlineMedium?.copyWith(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
            fontFeatures: tabularno,
          ),
        ),
        Text(
          [
            if (dvotarifno) 'viša ${Hr.broj(o.t1)} · niža ${Hr.broj(o.t2)}',
            '${Hr.broj(o.ukupno / max(o.dana, 1))} kWh/dan',
            if (o.predano > 0) 'predano ${Hr.broj(o.predano)}',
          ].join(' · '),
          style: t.bodySmall?.copyWith(fontFeatures: tabularno),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: LayoutBuilder(
            builder: (context, c) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => setState(
                () => _odabran = (d.localPosition.dx / c.maxWidth * r.length)
                    .floor()
                    .clamp(0, r.length - 1),
              ),
              onHorizontalDragUpdate: (d) => setState(
                () => _odabran = (d.localPosition.dx / c.maxWidth * r.length)
                    .floor()
                    .clamp(0, r.length - 1),
              ),
              child: CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _Stupci(r, i, t.labelSmall!),
              ),
            ),
          ),
        ),
        if (dvotarifno) ...[
          const SizedBox(height: 10),
          const Row(
            children: [
              _Legenda(Boje.solar, 'viša tarifa (T1)'),
              SizedBox(width: 16),
              _Legenda(Boje.teal300, 'niža tarifa (T2)'),
            ],
          ),
        ],
      ],
    );
  }
}

class _Legenda extends StatelessWidget {
  const _Legenda(this.boja, this.tekst);

  final Color boja;
  final String tekst;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: boja,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(tekst, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _Stupci extends CustomPainter {
  _Stupci(this.r, this.odabran, this.stil);

  final List<Razdoblje> r;
  final int odabran;
  final TextStyle stil;

  @override
  void paint(Canvas canvas, Size size) {
    const dolje = 20.0;
    final visina = size.height - dolje;
    final vrh = r.map((x) => x.ukupno).fold(1, max);
    final sirina = size.width / r.length;
    final stupac = min(sirina * 0.62, 28.0);

    for (var i = 0; i < r.length; i++) {
      final x = r[i];
      final aktivan = i == odabran;
      final lijevo = sirina * i + (sirina - stupac) / 2;
      final h1 = visina * (x.t1 ?? 0) / vrh;
      final h2 = visina * (x.t2 ?? 0) / vrh;
      final alfa = aktivan ? 1.0 : 0.45;

      // T2 na dnu, T1 iznad; zaobljen samo vrh cijelog stupca.
      final dno = Rect.fromLTWH(lijevo, visina - h2, stupac, h2);
      final gore = Rect.fromLTWH(lijevo, visina - h2 - h1, stupac, h1);
      final r4 = const Radius.circular(4);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          dno,
          topLeft: h1 == 0 ? r4 : Radius.zero,
          topRight: h1 == 0 ? r4 : Radius.zero,
        ),
        Paint()..color = Boje.teal300.withValues(alpha: alfa),
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(gore, topLeft: r4, topRight: r4),
        Paint()..color = Boje.solar.withValues(alpha: alfa),
      );

      // Oznaka mjeseca, ali ne preguste.
      final korak = (r.length / 6).ceil();
      if (aktivan || (r.length - 1 - i) % korak == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: Hr.mjesec(x.od),
            style: stil.copyWith(
              letterSpacing: 0,
              color: aktivan ? Boje.ink : Boje.inkMuted,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(lijevo + stupac / 2 - tp.width / 2, size.height - tp.height),
        );
      }
    }
    canvas.drawLine(
      Offset(0, visina + 0.5),
      Offset(size.width, visina + 0.5),
      Paint()..color = Boje.border,
    );
  }

  @override
  bool shouldRepaint(_Stupci o) => o.r != r || o.odabran != odabran;
}
