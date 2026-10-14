// Uvoz s Mojeg računa HEP Elektre (https://mojracun.hep.hr/elektra) u pregledniku.
//
// Moj račun je Angular aplikacija s JSON API-jem na /elektra/v1/api/…, pa se
// ovdje ne parsira HTML tablica nego JSON. Parser je prijepis
// lib/src/moj_racun.dart i daje isti JSON kao MojRacunUvoz.toJson().
//
// Popis kupaca stiže samo u odgovoru prijave i ostaje u memoriji aplikacije
// (nema GET rute za njega). Zato se kupacId čita iz zahtjeva koje je stranica
// već poslala (Resource Timing), a ime, OMM i adresa iz zaglavlja „Kupac“.
// OIB se ne uzima.
//
// Extension ubacuje datoteku u karticu i zove mojRacunUvoz(); može se i
// zalijepiti u konzolu prijavljene stranice.

(() => {
  class MojRacunIznimka extends Error {
    /** @param {'sesijaIstekla'|'nemaKupca'|'neocekivanOdgovor'|'mreza'} greska */
    constructor(greska, poruka) {
      super(poruka ? `${greska}: ${poruka}` : greska);
      this.greska = greska;
    }
  }

  const MojRacunParser = (() => {
    const prazno = (v) => (v == null || v === '' ? null : v);
    const tekst = (s) => (s || '').replace(/\s+/g, ' ').trim();

    // API daje `2026-10-01T01:59:00Z` (rano jutro po našem vremenu) ili
    // `…+02:00`; datum je prvih 10 znakova.
    const datum = (s) => (/^\d{4}-\d{2}-\d{2}/.test(s || '') ? s.slice(0, 10) : null);

    // `dd.mm.yyyy` → `yyyy-mm-dd`.
    const hrDatum = (s) => {
      const m = /(\d{1,2})\.(\d{1,2})\.(\d{4})/.exec(s || '');
      return m ? `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}` : null;
    };

    const lista = (j, sto) => {
      if (!Array.isArray(j)) throw new MojRacunIznimka('neocekivanOdgovor', `${sto} nije lista`);
      return j;
    };

    return {
      /** `api/ocitanja/{kupacId}`: stanja brojila, najnovije prvo. */
      ocitanja: (j) =>
        lista(j, 'ocitanja')
          .map((o) => ({
            datum: datum(o.datum),
            opis: o.nacinOcitanja || '',
            t1_kwh: o.tarifa1 ?? null,
            t2_kwh: o.tarifa2 ?? null,
          }))
          .filter((o) => o.datum),

      /** `api/potrosnja/{kupacId}`: razdoblja, najnovije prvo; proizv = predano u mrežu. */
      potrosnja: (j) =>
        lista(j, 'potrosnja').flatMap((p) => {
          const [od, doDatuma] = (p.razdoblje || '').split('-').map(hrDatum);
          if (!od || !doDatuma) return [];
          const t1 = p.tarifa1 ?? null;
          const t2 = p.tarifa2 ?? null;
          return [{
            od,
            do: doDatuma,
            t1_kwh: t1,
            t2_kwh: t2,
            ukupno_kwh: (t1 || 0) + (t2 || 0),
            predano_t1_kwh: p.proizv1 ?? 0,
            predano_t2_kwh: p.proizv2 ?? 0,
          }];
        }),

      /** `api/promet/{kupacId}`: računi i uplate, najnovije prvo, i dospjeli dug. */
      promet(j) {
        if (!j || !Array.isArray(j.promet)) throw new MojRacunIznimka('neocekivanOdgovor', 'promet bez liste');
        return {
          stavke: j.promet
            .map((s) => {
              const racun = s.opis === 'Račun';
              return {
                datum: datum(s.datum),
                opis: s.opis || '',
                duguje_eur: s.duguje ?? 0,
                potrazuje_eur: s.potrazuje ?? 0,
                // Kod uplata server ovdje vraća trenutno vrijeme, ne rok.
                dospijeva: racun ? datum(s.dospijeva) : null,
                poziv_na_broj: prazno(s.pnb),
                racun: prazno(s.racun),
                status: prazno(s.status),
              };
            })
            .filter((s) => s.datum),
          saldo: j.saldo ? { iznos_eur: j.saldo.iznos ?? null, opis: tekst(j.saldo.opis) } : null,
        };
      },

      /** Zaglavlje „Kupac“ (app-kupac-list): odabrani kupac. */
      zaglavlje(izvor) {
        const d = typeof izvor === 'string' ? new DOMParser().parseFromString(izvor, 'text/html') : izvor;
        const k = d.querySelector('app-kupac-list');
        if (!k) return null;
        const t = tekst(k.textContent);
        const naziv = k.querySelector('.ng-value-label');
        return {
          ime: naziv ? tekst(naziv.textContent) || null : null,
          ugovorni_racun: (/Ugovorni račun:\s*(\d+)/.exec(t) || [])[1] || null,
          omm: (/Broj OMM:\s*(\d+)/.exec(t) || [])[1] || null,
          adresa: tekst((/Adresa:\s*(.+)$/.exec(t) || [])[1]) || null,
        };
      },

      /** kupacId iz URL-ova API zahtjeva, zadnje korišteni zadnji. */
      kupacIds(urlovi) {
        const ids = [];
        for (const u of urlovi) {
          const m = /\/api\/(?:promet|potrosnja|ocitanja|opomene|obracun)\/(\d+)(?:$|[?#])/.exec(u);
          if (!m) continue;
          const i = ids.indexOf(m[1]);
          if (i >= 0) ids.splice(i, 1);
          ids.push(m[1]);
        }
        return ids;
      },
    };
  })();

  /** @param {{napredak?: (poruka: string) => void}} [opcije] */
  async function mojRacunUvoz({ napredak = () => {} } = {}) {
    if (location.origin !== 'https://mojracun.hep.hr' || !location.pathname.startsWith('/elektra')) {
      throw new MojRacunIznimka('mreza', 'pokreni na https://mojracun.hep.hr/elektra');
    }
    if (location.pathname.startsWith('/elektra/login')) throw new MojRacunIznimka('sesijaIstekla');

    async function api(putanja) {
      let o;
      try {
        o = await fetch(`/elektra/v1/api/${putanja}`, { credentials: 'same-origin', cache: 'no-store' });
      } catch (e) {
        throw new MojRacunIznimka('mreza', String(e));
      }
      if (o.status === 401 || o.status === 403) throw new MojRacunIznimka('sesijaIstekla');
      if (o.status !== 200) throw new MojRacunIznimka('mreza', `HTTP ${o.status} za ${putanja}`);
      try {
        return await o.json();
      } catch {
        throw new MojRacunIznimka('neocekivanOdgovor', `${putanja} nije JSON`);
      }
    }

    const kupacIdsSada = () => MojRacunParser.kupacIds(performance.getEntriesByType('resource').map((e) => e.name));
    let ids = kupacIdsSada();
    if (ids.length === 0) {
      // Naslovnica nakon prijave još nije tražila ništa s kupacId. Potrošnja
      // hoće, pa se na nju prelazi Angularovim routerom, bez učitavanja
      // stranice (učitavanje bi prekinulo ovaj kod): klik na poveznicu, a bez
      // nje pushState + popstate, koji router također sluša.
      napredak('Otvaram Potrošnju…');
      const poveznica = [...document.querySelectorAll('a[href]')].find((a) => /\/potrosnja\/?$/.test(a.pathname));
      if (poveznica) poveznica.click();
      else {
        history.pushState(null, '', '/elektra/potrosnja');
        dispatchEvent(new PopStateEvent('popstate', { state: null }));
      }
      for (let i = 0; i < 40 && ids.length === 0; i++) {
        await new Promise((ok) => setTimeout(ok, 250));
        ids = kupacIdsSada();
      }
      // Zaglavlje „Kupac“ se iscrta tek nakon odgovora.
      await new Promise((ok) => setTimeout(ok, 600));
    }
    if (ids.length === 0) throw new MojRacunIznimka('nemaKupca');
    // Zaglavlje pokazuje kupca čiji su podaci zadnji učitani.
    const odabran = ids[ids.length - 1];
    const zaglavlje = MojRacunParser.zaglavlje(document);

    const kupci = [];
    for (const [i, id] of ids.entries()) {
      napredak(`Kupac ${id}${ids.length > 1 ? ` (${i + 1}/${ids.length})` : ''}…`);
      const promet = MojRacunParser.promet(await api(`promet/${id}`));
      kupci.push({
        kupac_id: id,
        ...(id === odabran && zaglavlje ? zaglavlje : { ime: null, ugovorni_racun: null, omm: null, adresa: null }),
        saldo: promet.saldo,
        ocitanja: MojRacunParser.ocitanja(await api(`ocitanja/${id}`)),
        potrosnja: MojRacunParser.potrosnja(await api(`potrosnja/${id}`)),
        promet: promet.stavke,
      });
    }
    return { izvor: 'https://mojracun.hep.hr', dohvaceno: new Date().toISOString(), kupci };
  }

  const izvoz = { MojRacunParser, MojRacunIznimka, mojRacunUvoz };
  if (typeof module !== 'undefined') module.exports = izvoz;
  else Object.assign(globalThis, izvoz);
})();
