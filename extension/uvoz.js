// Uvoz s Moje mreže (https://mojamreza.hep.hr) u pregledniku.
//
// Isti tok i isti JSON kao FlutterMojaMreza.uvezi() / HepUvoz.toJson() u
// pluginu, a parsiranje je prijepis lib/src/parser.dart. Radi samo u kontekstu
// stranice mojamreza.hep.hr (fetch je same-origin, ide s cookiejima sesije).
//
// Extension ovu datoteku ubacuje u karticu (chrome.scripting) i zove
// mojaMrezaUvoz(). Može se i zalijepiti u konzolu prijavljene stranice:
//   await mojaMrezaUvoz()

// Sve je u IIFE-u jer extension datoteku može ubaciti u istu karticu više puta.
(() => {
  class MojaMrezaIznimka extends Error {
    /** @param {'sesijaIstekla'|'neocekivanHtml'|'mreza'} greska */
    constructor(greska, poruka) {
      super(poruka ? `${greska}: ${poruka}` : greska);
      this.greska = greska;
    }
  }

  const MojaMrezaParser = (() => {
    const tekst = (e) => (e.textContent || '').replace(/\s+/g, ' ').trim();
    const znamenke = (s) => (s == null ? null : s.replace(/\D/g, ''));

    // `1.234` i `1 234` su tisuće; HEP daje cijele kWh.
    const broj = (s) => {
      const z = znamenke(s);
      return z == null || z === '' ? null : parseInt(z, 10);
    };

    // `dd.mm.yyyy.` → `yyyy-mm-dd`.
    const datum = (s) => {
      const m = /(\d{1,2})\.(\d{1,2})\.(\d{4})/.exec(s || '');
      if (!m) return null;
      return `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}`;
    };

    const dokument = (izvor) =>
      typeof izvor === 'string' ? new DOMParser().parseFromString(izvor, 'text/html') : izvor;

    // Prva tablica čiji thead sadrži sve obavezne stupce. Stupci se traže po
    // nazivu (početak, mala slova), ne po indeksu.
    function tablica(d, obavezni) {
      for (const t of d.querySelectorAll('table')) {
        const stupci = new Map();
        t.querySelectorAll('thead th').forEach((th, i) => stupci.set(tekst(th).toLowerCase(), i));
        const kljucevi = [...stupci.keys()];
        if (!obavezni.every((o) => kljucevi.some((k) => k.startsWith(o)))) continue;

        const retci = [...t.querySelectorAll('tbody tr')]
          // Prvi stupac retka je često <th scope="row"> (OMM na /Postavke,
          // ikona statusa na /Ocitanja), pa se broje i th i td.
          .map((tr) => [...tr.children].filter((c) => /^t[hd]$/i.test(c.tagName)).map(tekst))
          .filter((r) => r.some(Boolean));

        const celija = (redak, naziv) => {
          const k = kljucevi.find((k) => k.startsWith(naziv));
          const v = k == null ? undefined : redak[stupci.get(k)];
          return v ? v : null;
        };
        return { retci, celija };
      }
      throw new MojaMrezaIznimka('neocekivanHtml', `nema tablice sa stupcima ${obavezni.join(', ')}`);
    }

    return {
      /** `/Postavke`: svi OMM-ovi prijavljene osobe. OIB se namjerno ne uzima. */
      postavke(izvor) {
        const t = tablica(dokument(izvor), ['omm', 'broj brojila']);
        return t.retci
          .map((r) => ({
            omm: znamenke(t.celija(r, 'omm')),
            broj_brojila: t.celija(r, 'broj brojila'),
            korisnik: t.celija(r, 'korisnik'),
            adresa: t.celija(r, 'adresa'),
            tarifni_model: t.celija(r, 'tarifni model'),
          }))
          .filter((o) => o.omm);
      },

      /** `/Ocitanja`: stanja brojila, najnovije prvo. */
      ocitanja(izvor) {
        const t = tablica(dokument(izvor), ['datum', 'tarifa 1']);
        return t.retci
          .map((r) => ({
            datum: datum(t.celija(r, 'datum')),
            opis: t.celija(r, 'opis') || '',
            t1_kwh: broj(t.celija(r, 'tarifa 1')),
            t2_kwh: broj(t.celija(r, 'tarifa 2')),
          }))
          .filter((o) => o.datum);
      },

      /** `/Potrosnja`: potrošnja po obračunskim razdobljima, najnovije prvo. */
      potrosnja(izvor) {
        const t = tablica(dokument(izvor), ['razdoblje', 'tarifa 1']);
        const re = /(\d{1,2}\.\d{1,2}\.\d{4})\.?\s*-\s*(\d{1,2}\.\d{1,2}\.\d{4})/;
        return t.retci.flatMap((r) => {
          const m = re.exec(t.celija(r, 'razdoblje') || '');
          if (!m) return [];
          const t1 = broj(t.celija(r, 'tarifa 1'));
          const t2 = broj(t.celija(r, 'tarifa 2'));
          return [{ od: datum(m[1]), do: datum(m[2]), t1_kwh: t1, t2_kwh: t2, ukupno_kwh: (t1 || 0) + (t2 || 0) }];
        });
      },

      /** OMM odabran u select#omm_select, ili null ako ga nema. */
      odabraniOmm(izvor) {
        const select = dokument(izvor).querySelector('#omm_select');
        if (!select) return null;
        const o = select.querySelector('option[selected]') || select.querySelector('option');
        return znamenke(o ? o.getAttribute('value') : null);
      },
    };
  })();

  /**
   * Uvoz svih OMM-ova prijavljene osobe s očitanjima i potrošnjom.
   * @param {{ocitanja?: boolean, potrosnja?: boolean, napredak?: (poruka: string) => void}} [opcije]
   */
  async function mojaMrezaUvoz({ ocitanja = true, potrosnja = true, napredak = () => {} } = {}) {
    if (location.origin !== 'https://mojamreza.hep.hr') {
      throw new MojaMrezaIznimka('mreza', 'pokreni na https://mojamreza.hep.hr');
    }

    // HTML stranice, uz provjeru da je sesija živa i da je odabran omm.
    async function stranica(putanja, omm) {
      let odgovor;
      try {
        odgovor = await fetch(omm ? `${putanja}?omm=${encodeURIComponent(omm)}` : putanja, {
          credentials: 'same-origin',
          cache: 'no-store',
        });
      } catch (e) {
        throw new MojaMrezaIznimka('mreza', String(e));
      }
      // Neprijavljen zahtjev server preusmjerava na naslovnicu.
      if (new URL(odgovor.url).pathname === '/') throw new MojaMrezaIznimka('sesijaIstekla');
      if (odgovor.status !== 200) {
        throw new MojaMrezaIznimka('mreza', `HTTP ${odgovor.status} za ${putanja}`);
      }
      const html = await odgovor.text();
      if (omm) {
        const odabran = MojaMrezaParser.odabraniOmm(html);
        if (odabran && odabran !== omm) {
          throw new MojaMrezaIznimka('neocekivanHtml', `${putanja}?omm=${omm} vratio je OMM ${odabran}`);
        }
      }
      return html;
    }

    napredak('Dohvaćam mjerna mjesta…');
    const omms = MojaMrezaParser.postavke(await stranica('/Postavke'));
    const mjesta = [];
    for (const [i, omm] of omms.entries()) {
      napredak(`OMM ${omm.omm}${omms.length > 1 ? ` (${i + 1}/${omms.length})` : ''}…`);
      mjesta.push({
        ...omm,
        ocitanja: ocitanja ? MojaMrezaParser.ocitanja(await stranica('/Ocitanja', omm.omm)) : [],
        potrosnja: potrosnja ? MojaMrezaParser.potrosnja(await stranica('/Potrosnja', omm.omm)) : [],
      });
    }
    return { izvor: 'https://mojamreza.hep.hr', dohvaceno: new Date().toISOString(), mjesta };
  }

  const izvoz = { MojaMrezaParser, MojaMrezaIznimka, mojaMrezaUvoz };
  if (typeof module !== 'undefined') module.exports = izvoz;
  else Object.assign(globalThis, izvoz);
})();
