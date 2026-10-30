// Service worker: vodi cijeli uvoz, da popup smije nestati usred posla (klik
// izvan popupa ga zatvori, a Hepi zna imati 20 PDF-ova računa).
//
// Tok: popup javi {pokreni: {tabId, izvor, posalji}} → ovdje se parser ubaci u
// karticu portala i vrati gotov JSON → snimak na omm.domovina.ai → za Hepi još
// PDF-ovi računa. Stanje posla je u chrome.storage.session pod `posao`, a popup
// ga samo crta. Slanje ide s origina ekstenzije, pa HEP-ov connect-src i COOP
// nemaju ulogu (API ima CORS *).

const OMM = 'https://omm.domovina.ai';

const IZVORI = {
  mreza: { datoteka: 'uvoz.js', funkcija: 'mojaMrezaUvoz', ommIzvor: 'hep', ime: 'moja-mreza' },
  racun: { datoteka: 'mojracun.js', funkcija: 'mojRacunUvoz', ommIzvor: 'hep-moj-racun', ime: 'moj-racun' },
  hepi: { datoteka: 'hepi.js', funkcija: 'hepiUvoz', ommIzvor: 'hep-hepi', ime: 'moj-hepi-racun', racuni: true },
};

const PORUKE = {
  sesijaIstekla: 'Nisi prijavljen. Prijavi se u ovoj kartici pa pokušaj ponovno.',
  neocekivanHtml: 'Stranica ne izgleda kako uvoz očekuje (HEP ju je možda promijenio).',
  neocekivanOdgovor: 'Odgovor portala ne izgleda kako uvoz očekuje (HEP ga je možda promijenio).',
  nemaKupca: 'Ne vidim kupca. Otvori Potrošnju ili Promet u Mojem računu pa pokušaj ponovno.',
  mreza: 'Mreža ili preglednik javili su grešku.',
};

let posao = null;

async function azuriraj(promjena) {
  posao = { ...posao, ...promjena };
  await chrome.storage.session.set({ posao });
}

// Ključ korisnika s omm.domovina.ai; zapisuje ga omm.js kad je korisnik na webu.
async function kljuc() {
  const { kljuc } = await chrome.storage.local.get('kljuc');
  return kljuc || null;
}

class GreskaKljuca extends Error {}

async function api(put, metoda, tip, tijelo) {
  const k = await kljuc();
  if (!k) throw new GreskaKljuca('nema ključa');
  const headers = { Authorization: `Bearer ${k}` };
  if (tip) headers['Content-Type'] = tip;
  const o = await fetch(`${OMM}${put}`, { method: metoda, headers, body: tijelo, credentials: 'omit' });
  const j = await o.json().catch(() => ({}));
  // 401: ključ je na webu zamijenjen novim (rotacija), a ovdje je ostao stari.
  if (o.status === 401) throw new GreskaKljuca(j.greska || 'ključ ne vrijedi');
  return { status: o.status, j };
}

// OMM snimka kad uvoz ima točno jedno mjesto (Moja mreža) ili kupca (Moj račun, Hepi).
function jediniOmm(u) {
  const lista = u.mjesta || u.kupci || [];
  return lista.length === 1 ? lista[0].omm || null : null;
}

async function uvezi({ tabId, izvor: ime, posalji }) {
  const izvor = IZVORI[ime];
  posao = { tabId, izvor: ime, faza: 'radi', status: 'Pokrećem…', pocetak: Date.now() };
  await chrome.storage.session.set({ posao });
  try {
    await chrome.scripting.executeScript({ target: { tabId }, files: [izvor.datoteka] });
    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId },
      args: [izvor.funkcija],
      func: async (funkcija) => {
        try {
          return { uvoz: await globalThis[funkcija]({ napredak: (p) => chrome.runtime.sendMessage({ napredak: p }) }) };
        } catch (e) {
          return { greska: e.greska || 'mreza', poruka: String(e.message || e) };
        }
      },
    });
    if (result.greska) {
      return azuriraj({ faza: 'greska', status: `${PORUKE[result.greska] || ''} (${result.poruka})` });
    }
    await azuriraj({ uvoz: result.uvoz, ime: izvor.ime, status: '' });
    if (posalji) return posaljiOmm();
    await azuriraj({ faza: 'gotovo' });
  } catch (e) {
    await azuriraj({ faza: 'greska', status: `${PORUKE.mreza} (${e.message || e})` });
  }
}

/** Snimak `hep`, `hep-moj-racun` ili `hep-hepi`; server isti sadržaj vraća kao duplikat (200). */
async function posaljiOmm() {
  const izvor = IZVORI[posao.izvor];
  await azuriraj({ faza: 'radi', status: 'Šaljem na omm.domovina.ai…' });
  try {
    const { status, j } = await api('/api/snimak', 'POST', 'application/json', JSON.stringify({
      izvor: izvor.ommIzvor,
      omm: jediniOmm(posao.uvoz),
      uvoz: posao.uvoz,
      lokacija: null,
    }));
    if (status !== 200 && status !== 201) throw new Error(j.greska || `HTTP ${status}`);
    await azuriraj({ poslano: j.duplikat ? 'duplikat' : 'novo', stvoren: j.stvoren || null });
    if (izvor.racuni) await posaljiRacune();
    await azuriraj({ faza: 'gotovo', status: '' });
  } catch (e) {
    await azuriraj({
      faza: 'greska',
      kljuc: e instanceof GreskaKljuca,
      status: e instanceof GreskaKljuca
        ? 'Ekstenzija još nije povezana s tvojim ključem na omm.domovina.ai. Otvori omm.domovina.ai (gumb ispod) pa pokušaj ponovno.'
        : `Slanje na omm.domovina.ai nije uspjelo (${e.message || e})`,
    });
  }
}

// Kao posaljiRacune u bookmarklet.js: server kaže koje pozive na broj već ima,
// a ostali PDF-ovi se dohvate u kartici Hepija i pošalju na /api/racun, gdje ih
// čita isti parser kao za mail. PDF se ne čuva.
async function posaljiRacune() {
  let imamo = [];
  const { status, j } = await api('/api/racun', 'GET');
  if (status === 200 && Array.isArray(j)) imamo = j;
  const novi = posao.uvoz.kupci.flatMap((k) => k.racuni).filter((r) => r.link && r.poziv_na_broj && !imamo.includes(r.poziv_na_broj));
  let procitano = 0;
  for (const [i, r] of novi.entries()) {
    await azuriraj({ status: `Račun ${i + 1}/${novi.length}…` });
    try {
      // executeScript vraća samo JSON, pa PDF putuje kao base64.
      const [{ result }] = await chrome.scripting.executeScript({
        target: { tabId: posao.tabId },
        args: [r.link],
        func: async (link) => {
          try {
            const b = await globalThis.hepiRacunPdf(link);
            let s = '';
            for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode(...b.subarray(i, i + 0x8000));
            return { pdf: btoa(s) };
          } catch (e) {
            return { greska: String(e.message || e) };
          }
        },
      });
      if (!result.pdf) continue;
      const pdf = Uint8Array.from(atob(result.pdf), (z) => z.charCodeAt(0));
      const o = await api('/api/racun', 'POST', 'application/pdf', pdf);
      if (o.status >= 200 && o.status < 300) procitano++;
    } catch (e) {
      if (e instanceof GreskaKljuca) throw e;
    }
  }
  await azuriraj({ racuni: { novi: novi.length, procitano } });
}

chrome.runtime.onMessage.addListener((m, posiljatelj) => {
  if (!m) return;
  (async () => {
    // Preglednik gasi service worker kad miruje; posao je ostao u storage.session.
    if (!posao) posao = (await chrome.storage.session.get('posao')).posao || null;
    if (m.pokreni) uvezi(m.pokreni);
    else if (m.posalji && posao && posao.uvoz) posaljiOmm();
    // Napredak parsera iz kartice u kojoj radi posao.
    else if (m.napredak && posao && posiljatelj.tab && posiljatelj.tab.id === posao.tabId) azuriraj({ status: m.napredak });
  })();
});

// Nakon instalacije omm.domovina.ai, da omm.js odmah preuzme ključ korisnika.
chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === 'install') chrome.tabs.create({ url: `${OMM}/?ekstenzija=1` });
});
