import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import 'modeli.dart';

/// Parsiranje HTML-a stranica Moje mreže (server-rendered ASP.NET MVC).
///
/// Stupci se traže po nazivu u `thead`, ne po indeksu, pa dodani ili
/// premješteni stupac ne pokvari uvoz. Ako stupac koji je obavezan nedostaje,
/// baca se [MojaMrezaGreska.neocekivanHtml].
class MojaMrezaParser {
  const MojaMrezaParser._();

  /// `/Postavke`: svi OMM-ovi prijavljene osobe.
  static List<HepOmm> postavke(String izvor) {
    final t = _Tablica.trazi(html.parse(izvor), const ['omm', 'broj brojila']);
    return [
      for (final r in t.retci)
        if (_znamenke(t.celija(r, 'omm')) case final omm? when omm.isNotEmpty)
          HepOmm(
            omm: omm,
            brojBrojila: t.celija(r, 'broj brojila'),
            korisnik: t.celija(r, 'korisnik'),
            adresa: t.celija(r, 'adresa'),
            tarifniModel: t.celija(r, 'tarifni model'),
          ),
    ];
  }

  /// `/Ocitanja`: stanja brojila, najnovije prvo.
  static List<HepOcitanje> ocitanja(String izvor) {
    final t = _Tablica.trazi(html.parse(izvor), const ['datum', 'tarifa 1']);
    return [
      for (final r in t.retci)
        if (_datum(t.celija(r, 'datum')) case final datum?)
          HepOcitanje(
            datum: datum,
            opis: t.celija(r, 'opis') ?? '',
            t1: _broj(t.celija(r, 'tarifa 1')),
            t2: _broj(t.celija(r, 'tarifa 2')),
          ),
    ];
  }

  /// `/DostavaOcitanja`: polja forme za `POST /Omm/Dostava`.
  ///
  /// Tokeni (`__RequestVerificationToken`, `encValue`) mijenjaju se pri
  /// svakom učitavanju, pa se forma parsira neposredno prije slanja.
  static HepDostavaForma dostavaForma(String izvor) {
    final d = html.parse(izvor);
    final forma =
        d.querySelector('#dostavaOcitanjaForm') ??
        d
            .querySelectorAll('form')
            .where((f) => (f.attributes['action'] ?? '').contains('Dostava'))
            .firstOrNull;
    if (forma == null) {
      throw const MojaMrezaIznimka(
        MojaMrezaGreska.neocekivanHtml,
        'Nema forme za dostavu očitanja',
      );
    }
    final polja = <String, String>{};
    for (final e in forma.querySelectorAll('input, select, textarea')) {
      final ime = e.attributes['name'];
      final tip = (e.attributes['type'] ?? '').toLowerCase();
      if (ime == null || ime.isEmpty || tip == 'submit' || tip == 'button') {
        continue;
      }
      if ((tip == 'checkbox' || tip == 'radio') &&
          !e.attributes.containsKey('checked')) {
        continue;
      }
      polja[ime] = e.localName == 'select'
          ? (e.querySelector('option[selected]') ?? e.querySelector('option'))
                    ?.attributes['value'] ??
                ''
          : e.localName == 'textarea'
          ? e.text
          : e.attributes['value'] ?? '';
    }
    if (!polja.containsKey('DostavaVM.Tarifa1')) {
      throw const MojaMrezaIznimka(
        MojaMrezaGreska.neocekivanHtml,
        'Forma nema polje DostavaVM.Tarifa1',
      );
    }
    final tekst = forma.text.replaceAll(RegExp(r'\s+'), ' ');
    final raspon = RegExp(
      r'raspon\D{0,20}?(\d[\d.]*)\s*do\s*(\d[\d.]*)',
      caseSensitive: false,
    ).allMatches(tekst).map((m) => (_broj(m[1])!, _broj(m[2])!)).toList();
    // 2026-10-12 je T1 izašao kao (15416, 815438): format teksta još ne znamo
    // točno, pa se besmislen raspon odbacuje, a tekst čuva za dijagnozu.
    (int, int)? razuman((int, int)? r) =>
        r != null && r.$2 >= r.$1 && r.$2 - r.$1 <= 5000 ? r : null;
    final oko = [
      for (final m in RegExp('raspon', caseSensitive: false).allMatches(tekst))
        tekst.substring(
          (m.start - 40).clamp(0, tekst.length),
          (m.end + 60).clamp(0, tekst.length),
        ),
    ];
    return HepDostavaForma(
      akcija: forma.attributes['action'] ?? '/Omm/Dostava',
      polja: polja,
      rasponT1: razuman(raspon.elementAtOrNull(0)),
      rasponT2: razuman(raspon.elementAtOrNull(1)),
      rasponTekst: oko,
    );
  }

  /// `/Potrosnja`: potrošnja po obračunskim razdobljima, najnovije prvo.
  static List<HepPotrosnja> potrosnja(String izvor) {
    final t = _Tablica.trazi(html.parse(izvor), const [
      'razdoblje',
      'tarifa 1',
    ]);
    final razdoblje = RegExp(
      r'(\d{1,2}\.\d{1,2}\.\d{4})\.?\s*-\s*(\d{1,2}\.\d{1,2}\.\d{4})',
    );
    return [
      for (final r in t.retci)
        if (razdoblje.firstMatch(t.celija(r, 'razdoblje') ?? '') case final m?)
          HepPotrosnja(
            od: _datum(m[1])!,
            doDatuma: _datum(m[2])!,
            t1: _broj(t.celija(r, 'tarifa 1')),
            t2: _broj(t.celija(r, 'tarifa 2')),
          ),
    ];
  }

  /// OMM odabran u `select#omm_select` (ili `null` ako ga nema). Služi za
  /// provjeru da je `?omm=` stvarno prebacio stranicu na traženi OMM.
  static String? odabraniOmm(String izvor) {
    final select = html.parse(izvor).querySelector('#omm_select');
    if (select == null) return null;
    final opcije = select.querySelectorAll('option');
    final odabrana =
        opcije.where((o) => o.attributes.containsKey('selected')).firstOrNull ??
        opcije.firstOrNull;
    return _znamenke(odabrana?.attributes['value']);
  }
}

String _tekst(Element e) => e.text.replaceAll(RegExp(r'\s+'), ' ').trim();

String? _znamenke(String? s) => s?.replaceAll(RegExp(r'\D'), '');

/// `1.234` i `1 234` su tisuće; HEP daje cijele kWh.
int? _broj(String? s) {
  final z = _znamenke(s);
  return z == null || z.isEmpty ? null : int.parse(z);
}

/// `dd.mm.yyyy.` (s točkom na kraju ili bez nje).
DateTime? _datum(String? s) {
  final m = RegExp(r'(\d{1,2})\.(\d{1,2})\.(\d{4})').firstMatch(s ?? '');
  if (m == null) return null;
  return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
}

class _Tablica {
  _Tablica(this.stupci, this.retci);

  /// Naziv stupca (mala slova, bez viška razmaka) → indeks.
  final Map<String, int> stupci;
  final List<List<String>> retci;

  /// Prva tablica čiji `thead` sadrži sve [obavezni] stupce.
  static _Tablica trazi(Document d, List<String> obavezni) {
    for (final tablica in d.querySelectorAll('table')) {
      final zaglavlje = tablica.querySelectorAll('thead th');
      final stupci = {
        for (final (i, th) in zaglavlje.indexed) _tekst(th).toLowerCase(): i,
      };
      if (!obavezni.every((o) => stupci.keys.any((k) => k.startsWith(o)))) {
        continue;
      }
      final retci = [
        for (final tr in tablica.querySelectorAll('tbody tr'))
          // Prvi stupac retka je često `<th scope="row">` (OMM na /Postavke,
          // ikona statusa na /Ocitanja), pa se broje i th i td.
          [
            for (final c in tr.children)
              if (c.localName == 'td' || c.localName == 'th') _tekst(c),
          ],
      ].where((r) => r.any((c) => c.isNotEmpty)).toList();
      return _Tablica(stupci, retci);
    }
    throw MojaMrezaIznimka(
      MojaMrezaGreska.neocekivanHtml,
      'nema tablice sa stupcima ${obavezni.join(', ')}',
    );
  }

  /// Ćelija stupca čiji naziv počinje s [naziv]; `null` ako je stupca nema
  /// ili je ćelija prazna.
  String? celija(List<String> redak, String naziv) {
    final i = stupci.entries
        .where((e) => e.key.startsWith(naziv))
        .firstOrNull
        ?.value;
    if (i == null || i >= redak.length) return null;
    final v = redak[i];
    return v.isEmpty ? null : v;
  }
}
