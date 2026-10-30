const PORTAL = 'https://mojamreza.hep.hr/';
const MOJ_RACUN = 'https://mojracun.hep.hr/elektra/';
const HEPI = 'https://mojracun.hep.hr/hepi/';
const OMM = 'https://omm.domovina.ai';
const $ = (id) => document.getElementById(id);

// Uvoz vodi background.js (popup smije nestati usred posla), a ovdje se samo
// pokreće i crta stanje iz chrome.storage.session.
const ODJELJCI = { mreza: 'spremno', racun: 'spremno-racun', hepi: 'spremno-hepi' };
let tab = null;
let izvor = null;
let posao = null;

// localStorage popupa pripada originu extensiona: ostaje između otvaranja,
// briše se s deinstalacijom. try/catch jer ga preglednik može blokirati.
function procitaj(k) {
  try { return localStorage.getItem(k); } catch { return null; }
}
function zapisi(k, v) {
  try { localStorage.setItem(k, v); } catch {}
}

function status(tekst, greska = false) {
  $('status').hidden = !tekst;
  $('status').textContent = tekst || '';
  $('status').className = greska ? 'greska' : '';
}

function crtaj() {
  const gumb = $(`uvezi-${izvor}`);
  // Posao druge kartice (ili starog uvoza) ovdje se ne prikazuje.
  const p = posao && tab && posao.tabId === tab.id && posao.izvor === izvor ? posao : null;
  gumb.disabled = !!p && p.faza === 'radi';
  if (p && p.faza !== 'radi') gumb.textContent = 'Uvezi ponovno';
  $('povezi').hidden = !(p && p.kljuc);
  status(p ? p.status : '', p && p.faza === 'greska');
  if (!p || !p.uvoz) {
    $('rezultat').hidden = true;
    return;
  }
  prikazi(p.uvoz);
  const poslano = $('posalji-omm');
  poslano.disabled = p.faza === 'radi' || !!p.poslano;
  poslano.textContent = p.poslano ? 'Snimak je na omm.domovina.ai ✓' : 'Pošalji na omm.domovina.ai';
  const kraj = [];
  if (p.poslano === 'duplikat') kraj.push('Isti uvoz je već na omm.domovina.ai, nema ništa novo ✓');
  if (p.poslano === 'novo') kraj.push('Snimak spremljen na omm.domovina.ai ✓');
  if (p.racuni && p.racuni.novi) kraj.push(`Pročitano ${p.racuni.procitano} od ${p.racuni.novi} novih računa.`);
  if (p.faza === 'gotovo' && kraj.length) status(kraj.join(' '));
  $('rezultat').hidden = false;
}

function prikazi(u) {
  const ul = $('sazetak');
  ul.replaceChildren();
  if (u.kupci) {
    for (const k of u.kupci) {
      const racuni = k.racuni ? `, ${k.racuni.length} računa` : '';
      const promet = k.promet ? `, ${k.promet.length} stavki prometa` : '';
      ul.append(li(`${k.omm || `kupac ${k.kupac_id}`}, ${k.adresa || 'bez adrese'}: ${k.ocitanja.length} očitanja, ${k.potrosnja.length} razdoblja potrošnje${promet}${racuni}`));
    }
  } else {
    if (u.mjesta.length === 0) ul.append(li('Nema mjernih mjesta na ovom računu.'));
    for (const m of u.mjesta) {
      ul.append(li(`${m.omm}, ${m.adresa || 'bez adrese'}: ${m.ocitanja.length} očitanja, ${m.potrosnja.length} razdoblja potrošnje`));
    }
  }
}

function li(tekst) {
  const e = document.createElement('li');
  e.textContent = tekst;
  return e;
}

const json = () => JSON.stringify(posao.uvoz, null, 2);

$('preuzmi').addEventListener('click', () => {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([json()], { type: 'application/json' }));
  a.download = `${posao.ime}-${posao.uvoz.dohvaceno.slice(0, 10)}.json`;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});

$('kopiraj').addEventListener('click', async () => {
  await navigator.clipboard.writeText(json());
  $('kopiraj').textContent = 'Kopirano';
});

$('posalji-omm').addEventListener('click', () => chrome.runtime.sendMessage({ posalji: true }));

$('auto-omm').checked = procitaj('auto-omm') !== 'ne';
$('auto-omm').addEventListener('change', (e) => zapisi('auto-omm', e.target.checked ? 'da' : 'ne'));

// Linkovi u popupu se ne otvaraju sami; otvara ih nova kartica.
for (const id of ['kako', 'kako-hepi', 'moji-snimci', 'povezi', 'povezi-tekst']) {
  $(id).addEventListener('click', async (e) => {
    e.preventDefault();
    await chrome.tabs.create({ url: e.currentTarget.getAttribute('href') });
    window.close();
  });
}

for (const [id, url] of [['otvori', PORTAL], ['otvori-racun', MOJ_RACUN], ['otvori-hepi', HEPI]]) {
  $(id).addEventListener('click', async () => {
    await chrome.tabs.create({ url });
    window.close();
  });
}

chrome.storage.onChanged.addListener((promjene, podrucje) => {
  if (podrucje === 'session' && promjene.posao) {
    posao = promjene.posao.newValue || null;
    crtaj();
  }
});

// activeTab: klik na ikonu daje pristup samo ovoj kartici, dok ne ode s
// trenutne stranice. Zato je tab.url ovdje vidljiv, a uvoz se pokreće samo na
// portalu; drugdje extension ništa ne ubacuje.
(async () => {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const url = (tab && tab.url) || '';
  izvor = url.startsWith(PORTAL) ? 'mreza' : url.startsWith(MOJ_RACUN) ? 'racun' : url.startsWith(HEPI) ? 'hepi' : null;
  const { kljuc } = await chrome.storage.local.get('kljuc');
  $('nepovezano').hidden = !!kljuc;
  if (!izvor) {
    $('nije-portal').hidden = false;
    return;
  }
  $(ODJELJCI[izvor]).hidden = false;
  $('auto-omm-red').hidden = false;
  $('napomena-rad').hidden = false;
  $(`uvezi-${izvor}`).addEventListener('click', () => {
    chrome.runtime.sendMessage({ pokreni: { tabId: tab.id, izvor, posalji: $('auto-omm').checked } });
  });
  posao = (await chrome.storage.session.get('posao')).posao || null;
  crtaj();
})();
