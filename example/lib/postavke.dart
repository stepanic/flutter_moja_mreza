import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'omm_servis.dart';
import 'podaci.dart';
import 'tema.dart';
import 'widgets.dart';

class Postavke extends StatefulWidget {
  const Postavke({super.key, required this.sp, required this.onObrisi});

  final Spremiste sp;

  /// Odjava s HEP portala i brisanje spremljenih uvoza.
  final Future<void> Function() onObrisi;

  @override
  State<Postavke> createState() => _PostavkeState();
}

class _PostavkeState extends State<Postavke> {
  late bool _auto = widget.sp.autoSlanje;

  Future<void> _obrisi() async {
    final da = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Obrisati podatke?'),
        content: const Text(
          'S uređaja se brišu uvezena mjesta, očitanja i računi. '
          'Snimci na omm.domovina.ai ostaju.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Boje.rust),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Obriši'),
          ),
        ],
      ),
    );
    if (da != true) return;
    await widget.onObrisi();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Postavke')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const Oznaka('omm.domovina.ai'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _auto,
                  onChanged: (v) {
                    setState(() => _auto = v);
                    widget.sp.postaviAutoSlanje(v);
                  },
                  title: const Text('Nakon uvoza pošalji snimak'),
                  subtitle: const Text(
                    'Mjesta, očitanja i potrošnja, uz lokaciju ako je dopustiš',
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('Moja očitanja na webu'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () async {
                    final s = await OmmServis.otvori();
                    await launchUrl(
                      s.webPopis,
                      mode: LaunchMode.externalApplication,
                    );
                  },
                ),
              ],
            ),
          ),
          const Oznaka('Podaci na uređaju'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: Boje.rust),
              title: const Text(
                'Obriši podatke i odjavi se',
                style: TextStyle(color: Boje.rust),
              ),
              onTap: _obrisi,
            ),
          ),
          const Oznaka('O aplikaciji'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: DomovinaLogo(velicina: 40),
                  title: Text('Domovina Energy'),
                  subtitle: Text('Moje brojilo · HEP Moja mreža i Moj račun'),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Licence'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Domovina Energy',
                    applicationIcon: const Padding(
                      padding: EdgeInsets.all(8),
                      child: DomovinaLogo(velicina: 56),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'HEP portali nemaju API za treće strane, pa aplikacija otvara '
            'njihovu stranicu, ti se prijaviš, a podaci se pročitaju na '
            'uređaju. Kolačići prijave brišu se nakon svakog uvoza.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}
