const PORTAL = 'https://mojamreza.hep.hr/';
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
async function uvezi(tabId) {
  $('uvezi').disabled = true;
  $('rezultat').hidden = true;
  status('Pokrećem…');
  try {
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
    status('');
  } catch (e) {
    status(`${PORUKE.mreza} (${e.message || e})`, true);
  } finally {
    $('uvezi').disabled = false;
    $('uvezi').textContent = 'Uvezi ponovno';
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

// Linkovi u popupu se ne otvaraju sami; otvara ih nova kartica.
$('kako').addEventListener('click', (e) => {
  e.preventDefault();
  chrome.tabs.create({ url: e.currentTarget.href });
});

$('otvori').addEventListener('click', async () => {
  await chrome.tabs.create({ url: PORTAL });
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
  } else {
    $('nije-portal').hidden = false;
  }
})();
