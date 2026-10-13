const PORTAL = 'https://mojamreza.hep.hr/';
const MOJ_RACUN = 'https://mojracun.hep.hr/elektra/';
const OMM = 'https://omm.domovina.ai';
const $ = (id) => document.getElementById(id);

const PORUKE = {
  sesijaIstekla: 'Nisi prijavljen. Prijavi se u ovoj kartici pa pokušaj ponovno.',
  neocekivanHtml: 'Stranica ne izgleda kako uvoz očekuje (HEP ju je možda promijenio).',
  neocekivanOdgovor: 'Odgovor Mojeg računa ne izgleda kako uvoz očekuje (HEP ga je možda promijenio).',
  nemaKupca: 'Ne vidim kupca. Otvori Potrošnju ili Promet u Mojem računu pa pokušaj ponovno.',
  mreza: 'Mreža ili preglednik javili su grešku.',
};

let uvoz = null;

// localStorage popupa pripada originu extensiona: ostaje između otvaranja,
// briše se s deinstalacijom. try/catch jer ga preglednik može blokirati.
function procitaj(k) {
  try { return localStorage.getItem(k); } catch { return null; }
}
function zapisi(k, v) {
  try { localStorage.setItem(k, v); } catch {}
}

// Isto kao OmmServis u example aplikaciji: prijave još nema, nasumični ključ
// uređaja ide kao Bearer. Tko zna ključ, vidi snimke.
function kljucUredaja() {
  let k = procitaj('omm-kljuc');
  if (!k) {
    const b = crypto.getRandomValues(new Uint8Array(18));
    k = btoa(String.fromCharCode(...b)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    zapisi('omm-kljuc', k);
  }
  return k;
}

/** Uvoz kao snimak `izvor: hep`; server isti sadržaj vraća kao duplikat (200). */
async function posaljiOmm() {
  $('posalji-omm').disabled = true;
  status('Šaljem na omm.domovina.ai…');
  try {
    const o = await fetch(`${OMM}/api/snimak`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${kljucUredaja()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        izvor: 'hep',
        omm: uvoz.mjesta.length === 1 ? uvoz.mjesta[0].omm : null,
        uvoz,
        lokacija: null,
      }),
    });
    const j = await o.json().catch(() => ({}));
    if (o.status !== 200 && o.status !== 201) throw new Error(j.greska || `HTTP ${o.status}`);
    status(j.duplikat ? 'Isti uvoz je već na omm.domovina.ai ✓' : 'Snimak spremljen na omm.domovina.ai ✓');
    $('posalji-omm').textContent = 'Snimak je na omm.domovina.ai ✓';
  } catch (e) {
    status(`Slanje na omm.domovina.ai nije uspjelo (${e.message || e})`, true);
    $('posalji-omm').disabled = false;
  }
}

function status(tekst, greska = false) {
  $('status').hidden = !tekst;
  $('status').textContent = tekst || '';
  $('status').className = greska ? 'greska' : '';
}

// Uvoz se izvodi u kartici portala (same-origin fetch s cookiejima sesije),
// a ovdje stiže samo gotov JSON.
// Moja mreža i Moj račun razlikuju se samo u datoteci i funkciji koja se
// ubacuje; ostatak toka je isti.
const IZVORI = {
  mreza: { gumb: 'uvezi', datoteka: 'uvoz.js', funkcija: 'mojaMrezaUvoz', omm: true },
  racun: { gumb: 'uvezi-racun', datoteka: 'mojracun.js', funkcija: 'mojRacunUvoz', omm: false },
};
let izvor = IZVORI.mreza;

async function uvezi(tabId) {
  $(izvor.gumb).disabled = true;
  $('rezultat').hidden = true;
  status('Pokrećem…');
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
      status(`${PORUKE[result.greska] || ''} (${result.poruka})`, true);
      return;
    }
    uvoz = result.uvoz;
    prikazi(uvoz);
    status('');
    if (izvor.omm && $('auto-omm').checked) await posaljiOmm();
  } catch (e) {
    status(`${PORUKE.mreza} (${e.message || e})`, true);
  } finally {
    $(izvor.gumb).disabled = false;
    $(izvor.gumb).textContent = 'Uvezi ponovno';
  }
}

function prikazi(u) {
  const ul = $('sazetak');
  ul.replaceChildren();
  if (u.kupci) {
    for (const k of u.kupci) {
      ul.append(li(`${k.omm || `kupac ${k.kupac_id}`}, ${k.adresa || 'bez adrese'}: ${k.ocitanja.length} očitanja, ${k.potrosnja.length} razdoblja potrošnje, ${k.promet.length} stavki prometa`));
    }
  } else {
    if (u.mjesta.length === 0) ul.append(li('Nema mjernih mjesta na ovom računu.'));
    for (const m of u.mjesta) {
      ul.append(li(`${m.omm}, ${m.adresa || 'bez adrese'}: ${m.ocitanja.length} očitanja, ${m.potrosnja.length} razdoblja potrošnje`));
    }
  }
  // Server zasad prima samo uvoz s Moje mreže (usporedba čita uvoz.mjesta).
  $('posalji-omm').hidden = !izvor.omm;
  $('posalji-omm').disabled = false;
  $('posalji-omm').textContent = 'Pošalji na omm.domovina.ai';
  $('rezultat').hidden = false;
}

function li(tekst) {
  const e = document.createElement('li');
  e.textContent = tekst;
  return e;
}

const json = () => JSON.stringify(uvoz, null, 2);

$('preuzmi').addEventListener('click', () => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([json()], { type: 'application/json' }));
  a.download = `${izvor.omm ? 'moja-mreza' : 'moj-racun'}-${uvoz.dohvaceno.slice(0, 10)}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});

$('kopiraj').addEventListener('click', async () => {
  await navigator.clipboard.writeText(json());
  $('kopiraj').textContent = 'Kopirano';
});

$('posalji-omm').addEventListener('click', posaljiOmm);

$('auto-omm').checked = procitaj('auto-omm') !== 'ne';
$('auto-omm').addEventListener('change', (e) => zapisi('auto-omm', e.target.checked ? 'da' : 'ne'));

// Linkovi u popupu se ne otvaraju sami; otvara ih nova kartica.
$('kako').addEventListener('click', (e) => {
  e.preventDefault();
  chrome.tabs.create({ url: e.currentTarget.href });
});

$('moji-snimci').addEventListener('click', (e) => {
  e.preventDefault();
  chrome.tabs.create({ url: `${OMM}/?k=${encodeURIComponent(kljucUredaja())}` });
});

$('otvori').addEventListener('click', async () => {
  await chrome.tabs.create({ url: PORTAL });
  window.close();
});

$('otvori-racun').addEventListener('click', async () => {
  await chrome.tabs.create({ url: MOJ_RACUN });
  window.close();
});

chrome.runtime.onMessage.addListener((m) => {
  if (m && m.napredak) status(m.napredak);
});

// activeTab: klik na ikonu daje pristup samo ovoj kartici, dok ne ode s
// trenutne stranice. Zato je tab.url ovdje vidljiv, a uvoz se pokreće samo na
// portalu; drugdje extension ništa ne ubacuje.
(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab && tab.url && tab.url.startsWith(PORTAL)) {
    $('spremno').hidden = false;
    $('uvezi').addEventListener('click', () => uvezi(tab.id));
  } else if (tab && tab.url && tab.url.startsWith(MOJ_RACUN)) {
    izvor = IZVORI.racun;
    $('spremno-racun').hidden = false;
    $('uvezi-racun').addEventListener('click', () => uvezi(tab.id));
  } else {
    $('nije-portal').hidden = false;
  }
})();
