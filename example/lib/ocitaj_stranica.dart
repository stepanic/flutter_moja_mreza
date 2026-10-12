import 'package:flutter/material.dart';
import 'package:flutter_moja_mreza/flutter_moja_mreza.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'omm_servis.dart';

/// Slika zaslona brojila → 1.8.1 / 1.8.2 → potvrda → omm.domovina.ai i,
/// po želji, dostava očitanja u Moju mrežu.
class OcitajStranica extends StatefulWidget {
  const OcitajStranica({super.key, this.omms = const []});

  /// OMM-ovi iz zadnjeg uvoza, za izbor kod dostave.
  final List<String> omms;

  @override
  State<OcitajStranica> createState() => _OcitajStranicaState();
}

class _OcitajStranicaState extends State<OcitajStranica> {
  final _t1 = TextEditingController();
  final _t2 = TextEditingController();
  final _omm = TextEditingController();
  final _slike = <String>[];
  final _ocr = <Map<String, Object?>>[];
  OmmServis? _servis;
  Position? _pozicija;
  String? _poruka;
  bool _upozorenje = false;
  bool _radi = false;
  String? _snimakId;
  ZadnjeStanje? _zadnje;

  @override
  void initState() {
    super.initState();
    if (widget.omms.length == 1) _omm.text = widget.omms.single;
    OmmServis.otvori().then((s) => setState(() => _servis = s));
    lokacija().then((p) {
      if (mounted) setState(() => _pozicija = p);
    }, onError: (_) {});
  }

  void _stanje(String poruka, {bool upozorenje = false}) => setState(() {
    _poruka = poruka;
    _upozorenje = upozorenje;
  });

  int? get _v1 => int.tryParse(_t1.text.trim());
  int? get _v2 => int.tryParse(_t2.text.trim());
  String? get _ommVrijednost {
    final o = _omm.text.trim();
    return RegExp(r'^\d{10}$').hasMatch(o) ? o : null;
  }

  Future<void> _uslikaj(ImageSource izvor) async {
    final servis = _servis;
    if (servis == null) return;
    final slika = await ImagePicker().pickImage(
      source: izvor,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (slika == null) return;
    setState(() => _radi = true);
    _stanje('Čitam brojeve…');
    try {
      final r = await servis.ocitaj(
        await slika.readAsBytes(),
        omm: _ommVrijednost,
      );
      _ocr.add(r.json);
      _zadnje = r.zadnje ?? _zadnje;
      final dodatno = r.upozorenja.isEmpty
          ? ''
          : '\n${r.upozorenja.join('\n')}';
      if (r.slika != null) _slike.add(r.slika!);
      _snimakId = null;
      if (r.t1 == null && r.t2 == null && r.neodredeno != null) {
        final polje = _t1.text.isEmpty ? _t1 : _t2;
        polje.text = '${r.neodredeno}';
        _stanje(
          'Pročitano ${r.neodredeno}, ali oznaka tarife nije sigurna: upisano u '
          '${identical(polje, _t1) ? '1.8.1' : '1.8.2'}. Provjeri.',
          upozorenje: true,
        );
      } else if (r.t1 == null && r.t2 == null) {
        _stanje(
          'Nisam našao 1.8.1 ni 1.8.2${r.napomena == null ? '' : ' (${r.napomena})'}. '
          'Probaj opet ili upiši ručno.',
          upozorenje: true,
        );
      } else {
        if (r.t1 != null) _t1.text = '${r.t1}';
        if (r.t2 != null) _t2.text = '${r.t2}';
        _stanje(
          'Pročitano: ${[if (r.t1 != null) '1.8.1', if (r.t2 != null) '1.8.2'].join(' i ')}. '
          'Provjeri brojeve.$dodatno',
          upozorenje: dodatno.isNotEmpty,
        );
      }
    } catch (e) {
      _stanje('Čitanje nije uspjelo: $e', upozorenje: true);
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  /// Sprema snimak (jednom); vraća id.
  Future<String?> _spremi() async {
    final servis = _servis;
    final t1 = _v1;
    if (servis == null) return null;
    if (t1 == null) {
      _stanje('Upiši stanje 1.8.1', upozorenje: true);
      return null;
    }
    if (_snimakId != null) return _snimakId;
    setState(() => _radi = true);
    try {
      _snimakId = await servis.spremi({
        'izvor': _slike.isEmpty ? 'rucno' : 'foto',
        't1': t1,
        't2': _v2,
        'omm': _ommVrijednost,
        'slike': _slike,
        'ocr': _ocr,
        'lokacija': lokacijaJson(_pozicija),
      });
      _stanje('Spremljeno na omm.domovina.ai ✓');
      return _snimakId;
    } catch (e) {
      _stanje('Spremanje nije uspjelo: $e', upozorenje: true);
      return null;
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  /// Upozorenja za brojeve manje od zadnjeg stanja (stanje brojila ne pada).
  List<String> get _manjeOdZadnjeg {
    final z = _zadnje;
    if (z == null) return const [];
    return [
      if (_v1 != null && z.t1 != null && _v1! < z.t1!)
        '1.8.1 ($_v1) je manje od zadnjeg stanja ${z.t1}',
      if (_v2 != null && z.t2 != null && _v2! < z.t2!)
        '1.8.2 ($_v2) je manje od zadnjeg stanja ${z.t2}',
    ];
  }

  Future<void> _dostavi({bool svejedno = false}) async {
    final t1 = _v1;
    if (t1 == null) return _stanje('Upiši stanje 1.8.1', upozorenje: true);
    if (_manjeOdZadnjeg.isNotEmpty) {
      return _stanje(
        '${_manjeOdZadnjeg.join('\n')}. Provjeri brojeve.',
        upozorenje: true,
      );
    }
    final omm = _ommVrijednost;
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          svejedno ? 'Dostaviti svejedno?' : 'Poslati očitanje HEP-u?',
        ),
        content: Text(
          'OMM ${omm ?? '(onaj koji portal odabere)'}\n'
          '1.8.1: $t1 kWh\n'
          '1.8.2: ${_v2 ?? '–'} kWh\n\n'
          'Očitanje se šalje u Moju mrežu i ne može se povući. '
          'Prijava ide preko e-Građana (Certilia).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Pošalji'),
          ),
        ],
      ),
    );
    if (potvrda != true || !mounted) return;

    final id = await _spremi();
    if (!mounted) return;
    setState(() => _radi = true);
    try {
      final r = await FlutterMojaMreza().dostavi(
        context,
        t1: t1,
        t2: _v2,
        omm: omm,
        svejedno: svejedno,
      );
      if (r == null) {
        return _stanje('Prijava je prekinuta, ništa nije poslano.');
      }
      if (id != null) {
        await _servis
            ?.zabiljeziDostavu(id, r.toJson(), omm: r.omm)
            .catchError((_) {});
      }
      if (r.prihvaceno) {
        _stanje('HEP je primio očitanje ✓ (OMM ${r.omm})');
      } else if (!r.poslano || r.upozorenje) {
        final raspon = [
          if (r.forma?.rasponT1 case final x?) '1.8.1: ${x.$1}–${x.$2}',
          if (r.forma?.rasponT2 case final x?) '1.8.2: ${x.$1}–${x.$2}',
        ].join(', ');
        _stanje(
          '${r.poslano ? 'HEP upozorava' : 'Nije poslano'}: ${r.opis ?? ''}'
          '${raspon.isEmpty ? '' : ' Očekivani raspon $raspon.'}',
          upozorenje: true,
        );
        if (mounted) {
          final opet = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Vrijednost izgleda neobično'),
              content: Text(
                '${r.opis ?? ''}\n${raspon.isEmpty ? '' : 'Očekivani raspon $raspon.\n'}\n'
                'Provjeri brojeve. Ako su točni, možeš ih dostaviti svejedno '
                '(nova prijava).',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: const Text('Ispravit ću'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Dostavi svejedno'),
                ),
              ],
            ),
          );
          if (opet == true && mounted) {
            setState(() => _radi = false);
            await _dostavi(svejedno: true);
            return;
          }
        }
      } else {
        _stanje(
          'HEP: ${r.opis ?? 'greška'} (Status ${r.status})',
          upozorenje: true,
        );
      }
    } on MojaMrezaIznimka catch (e) {
      _stanje('Dostava nije uspjela: $e', upozorenje: true);
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final boje = Theme.of(context).colorScheme;
    final broj = Theme.of(context).textTheme.headlineSmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final p = _pozicija;
    return Scaffold(
      appBar: AppBar(title: const Text('Očitaj brojilo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Uslikaj zaslon dok pokazuje 1.8.1, pa dok pokazuje 1.8.2. '
            'Brojeve pročitamo automatski, a ti ih provjeriš.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _radi || _servis == null
                      ? null
                      : () => _uslikaj(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Uslikaj'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _radi || _servis == null
                    ? null
                    : () => _uslikaj(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Galerija'),
              ),
            ],
          ),
          if (_slike.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Slika: ${_slike.length}'),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _t1,
                  style: broj,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '1.8.1 (viša), kWh',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _snimakId = null),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _t2,
                  style: broj,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '1.8.2 (niža), kWh',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() => _snimakId = null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.omms.length > 1)
            DropdownButtonFormField<String>(
              initialValue: null,
              decoration: const InputDecoration(
                labelText: 'OMM',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final o in widget.omms)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (o) => _omm.text = o ?? '',
            )
          else
            TextField(
              controller: _omm,
              keyboardType: TextInputType.number,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'OMM (nije obavezno)',
                border: OutlineInputBorder(),
              ),
            ),
          if (_zadnje case final z?)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Zadnje stanje (${z.datum}): 1.8.1 ${z.t1 ?? '–'} · 1.8.2 ${z.t2 ?? '–'}',
                style: TextStyle(color: boje.onSurfaceVariant),
              ),
            ),
          for (final u in _manjeOdZadnjeg)
            Text('⚠️ $u', style: TextStyle(color: boje.error)),
          Text(
            p == null
                ? '📍 Lokacija nije dostupna'
                : '📍 ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)} '
                      '(±${p.accuracy.round()} m)',
            style: TextStyle(color: boje.onSurfaceVariant),
          ),
          if (_poruka != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _poruka!,
                style: TextStyle(
                  color: _upozorenje ? boje.error : boje.onSurface,
                ),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _radi || _snimakId != null ? null : _spremi,
            child: _radi
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_snimakId != null ? 'Spremljeno ✓' : 'Spremi očitanje'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _radi ? null : _dostavi,
            icon: const Icon(Icons.send),
            label: const Text('Pošalji u Moju mrežu (HEP)'),
          ),
        ],
      ),
    );
  }
}
