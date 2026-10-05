const PORTAL = 'https://mojamreza.hep.hr/';
// Dozvola za portal traži se na klik „Uvezi“ i vraća odmah nakon uvoza, pa
// extension između dva uvoza nema nikakav pristup Mojoj mreži.
const DOZVOLA = { origins: [`${PORTAL}*`] };
const $ = (id) => document.getElementById(id);

const PORUKE = {
  sesijaIstekla: 'Nisi prijavljen. Prijavi se na Moju mrežu (e-Građani) u ovoj kartici pa pokušaj ponovno.',
  neocekivanHtml: 'Stranica ne izgleda kako uvoz očekuje (HEP ju je možda promijenio).',
  mreza: 'Mreža ili preglednik javili su grešku.',
};

let uvoz = null;

function status(tekst, greska = false) {
  $('status').hidden = !tekst;
  $('status').textContent = tekst || '';
  $('status').className = greska ? 'greska' : '';
}

// Uvoz se izvodi u kartici portala (same-origin fetch s cookiejima sesije),
// a ovdje stiže samo gotov JSON.
async function uvezi() {
  // request() mora biti prvi await, dok klik još vrijedi kao korisnička gesta.
  if (!(await chrome.permissions.request(DOZVOLA))) {
    status('Bez dozvole za mojamreza.hep.hr uvoz ne može čitati podatke.', true);
    return;
  }
  $('uvezi').disabled = true;
  $('rezultat').hidden = true;
  status('Pokrećem…');
  try {
    // tab.url je vidljiv tek s dozvolom za portal.
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.url || !tab.url.startsWith(PORTAL)) {
      status('');
      $('spremno').hidden = true;
      $('nije-portal').hidden = false;
      return;
    }
    const tabId = tab.id;
    await chrome.scripting.executeScript({ target: { tabId }, files: ['uvoz.js'] });
    const [{ result }] = await chrome.scripting.executeScript({
      target: { tabId },
      func: async () => {
        try {
          return { uvoz: await mojaMrezaUvoz({ napredak: (p) => chrome.runtime.sendMessage({ napredak: p }) }) };
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
    status('Gotovo. Dozvola za mojamreza.hep.hr je vraćena.');
  } catch (e) {
    status(`${PORUKE.mreza} (${e.message || e})`, true);
  } finally {
    await chrome.permissions.remove(DOZVOLA);
    $('uvezi').disabled = false;
  }
}

function prikazi(u) {
  const ul = $('sazetak');
  ul.replaceChildren();
  if (u.mjesta.length === 0) ul.append(li('Nema mjernih mjesta na ovom računu.'));
  for (const m of u.mjesta) {
    ul.append(li(`${m.omm}, ${m.adresa || 'bez adrese'}: ${m.ocitanja.length} očitanja, ${m.potrosnja.length} razdoblja potrošnje`));
  }
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
  a.download = `moja-mreza-${uvoz.dohvaceno.slice(0, 10)}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});

$('kopiraj').addEventListener('click', async () => {
  await navigator.clipboard.writeText(json());
  $('kopiraj').textContent = 'Kopirano';
});

$('otvori').addEventListener('click', async () => {
  await chrome.tabs.create({ url: PORTAL });
  window.close();
});

chrome.runtime.onMessage.addListener((m) => {
  if (m && m.napredak) status(m.napredak);
});

$('uvezi').addEventListener('click', uvezi);

// Ako se popup prošli put zatvorio usred uvoza, dozvola je možda ostala.
chrome.permissions.remove(DOZVOLA);
$('spremno').hidden = false;
