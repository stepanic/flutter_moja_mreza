// Uvoz s Mojeg Hepi računa (https://mojracun.hep.hr/hepi), portala HEP Opskrbe
// za kupce na tržištu. Zaseban od Mojeg računa HEP Elektre (/elektra), sa
// zasebnom prijavom.
//
// Hepi je AngularJS aplikacija s JSON API-jem na /hepi/api/…. Prijava sprema
// token u localStorage['hepi.token'] i stranica ga šalje kao Bearer; ovaj kod
// radi isto, ali token nikad ne napušta stranicu. Za razliku od Elektre
// postoji GET /api/kupci, pa ne treba Resource Timing, a /api/report/racun
// vraća PDF računa. OIB i mail se ne uzimaju.
//
// Bookmarklet ubacuje datoteku u karticu i zove hepiUvoz(); može se i
// zalijepiti u konzolu prijavljene stranice.

(() => {
  class HepiIznimka extends Error {
    /** @param {'sesijaIstekla'|'neocekivanOdgovor'|'mreza'} greska */
    constructor(greska, poruka) {
      super(poruka ? `${greska}: ${poruka}` : greska);
      this.greska = greska;
    }
  }

  const HepiParser = (() => {
    const prazno = (v) => (v == null || v === '' ? null : v);
    // API daje `2026-09-30T02:00:00+02:00` (ponoć po našem vremenu); datum je prvih 10 znakova.
    const datum = (s) => (/^\d{4}-\d{2}-\d{2}/.test(s || '') && !String(s).startsWith('0001') ? s.slice(0, 10) : null);
    // `01.09.2026-30.09.2026` → { od, do }.
    const razdoblje = (s) => {
      const m = /(\d{2})\.(\d{2})\.(\d{4})\s*-\s*(\d{2})\.(\d{2})\.(\d{4})/.exec(s || '');
      return m ? { od: `${m[3]}-${m[2]}-${m[1]}`, do: `${m[6]}-${m[5]}-${m[4]}` } : { od: null, do: null };
    };
    const lista = (j, sto) => {
      if (!Array.isArray(j)) throw new HepiIznimka('neocekivanOdgovor', `${sto} nije lista`);
      return j;
    };

    /** GET /api/kupci: objekt { kupacId: kupac }. */
    function kupci(j) {
      if (!j || typeof j !== 'object') throw new HepiIznimka('neocekivanOdgovor', 'kupci nisu objekt');
      return Object.values(j).map((k) => ({
        kupac_id: String(k.KupacId),
        sifra_kupca: prazno(k.Sifra),
        ime: prazno(k.Naziv),
        omm: prazno(k.Omm),
        adresa: prazno(k.AdresaOmm) || prazno(k.Adresa),
        tarifni_model: prazno(k.TarifniModel),
        ugovor_od: datum(k.UgovorOd),
      }));
    }

    /** GET /api/potrosnja/:kupacId: { Total, Potrosnja[], Ocitanja[] }, najnovije prvo. */
    function potrosnja(j) {
      return {
        potrosnja: lista(j && j.Potrosnja, 'Potrosnja').map((p) => ({
          ...razdoblje(p.Razdoblje),
          t1_kwh: p.Tarifa1,
          t2_kwh: p.Tarifa2,
          ukupno_kwh: p.Ukupno,
        })),
        ocitanja: lista(j && j.Ocitanja, 'Ocitanja').map((o) => ({
          datum: datum(o.Datum),
          opis: prazno(o.NacinOcitanja),
          t1_kwh: o.Tarifa1,
          t2_kwh: o.Tarifa2,
        })),
      };
    }

    /** GET /api/promet/:kupacId: { Total (saldo), Racuni[], Uplate[] }. */
    function promet(j) {
      const t = (j && j.Total) || {};
      return {
        saldo: { iznos_eur: typeof t.Iznos === 'number' ? t.Iznos : null, opis: prazno(t.Labela) },
        racuni: lista(j && j.Racuni, 'Racuni').map((r) => ({
          datum: datum(r.Datum),
          poziv_na_broj: prazno(r.Pnb),
          iznos_eur: r.Iznos,
          dospijeva: datum(r.Dospijeva),
          placen: r.Status === 1,
          status: prazno(r.StatusText),
          link: prazno(r.Link),
        })),
        uplate: lista(j && j.Uplate, 'Uplate').map((u) => ({ datum: datum(u.Datum), iznos_eur: u.Iznos })),
      };
    }

    return { kupci, potrosnja, promet };
  })();

  function token() {
    let t = null;
    try { t = localStorage.getItem('hepi.token'); } catch {}
    if (!t || t === 'undefined') throw new HepiIznimka('sesijaIstekla');
    return t;
  }

  async function zahtjev(putanja, opcije = {}) {
    let o;
    try {
      o = await fetch(`/hepi/api/${putanja}`, {
        cache: 'no-store',
        ...opcije,
        headers: { Authorization: `Bearer ${token()}`, ...(opcije.headers || {}) },
      });
    } catch (e) {
      throw new HepiIznimka('mreza', String(e));
    }
    if (o.status === 401 || o.status === 403) throw new HepiIznimka('sesijaIstekla');
    if (o.status !== 200) throw new HepiIznimka('mreza', `HTTP ${o.status} za ${putanja}`);
    return o;
  }

  async function api(putanja) {
    const o = await zahtjev(putanja);
    try {
      return await o.json();
    } catch {
      throw new HepiIznimka('neocekivanOdgovor', `${putanja} nije JSON`);
    }
  }

  /** PDF računa (`link` iz promet.racuni[]), kao gumb za ispis računa na portalu. */
  async function hepiRacunPdf(link) {
    const o = await zahtjev('report/racun', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ link }),
    });
    const b = new Uint8Array(await o.arrayBuffer());
    // Server šalje Content-Type text/html, pa se provjerava zaglavlje datoteke.
    if (String.fromCharCode(...b.slice(0, 5)) !== '%PDF-') throw new HepiIznimka('neocekivanOdgovor', 'račun nije PDF');
    return b;
  }

  /** @param {{napredak?: (poruka: string) => void}} [opcije] */
  async function hepiUvoz({ napredak = () => {} } = {}) {
    if (location.origin !== 'https://mojracun.hep.hr' || !location.pathname.startsWith('/hepi')) {
      throw new HepiIznimka('mreza', 'pokreni na https://mojracun.hep.hr/hepi');
    }
    napredak('Dohvaćam kupce…');
    const popis = HepiParser.kupci(await api('kupci'));
    const kupci = [];
    for (const [i, k] of popis.entries()) {
      napredak(`Kupac ${k.sifra_kupca || k.kupac_id}${popis.length > 1 ? ` (${i + 1}/${popis.length})` : ''}…`);
      const { saldo, racuni, uplate } = HepiParser.promet(await api(`promet/${k.kupac_id}`));
      const { potrosnja, ocitanja } = HepiParser.potrosnja(await api(`potrosnja/${k.kupac_id}`));
      kupci.push({ ...k, saldo, ocitanja, potrosnja, racuni, uplate });
    }
    return { izvor: 'https://mojracun.hep.hr/hepi', dohvaceno: new Date().toISOString(), kupci };
  }

  const izvoz = { HepiParser, HepiIznimka, hepiUvoz, hepiRacunPdf };
  if (typeof module !== 'undefined') module.exports = izvoz;
  else Object.assign(globalThis, izvoz);
})();
