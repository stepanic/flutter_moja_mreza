// Content script na https://omm.domovina.ai: ekstenzija šalje uvoze s istim
// ključem koji korisnik ima na webu, inače ih tamo ne bi vidio.
//
// - Na <html> ostavlja data-omm-ekstenzija="<verzija>", po čemu naslovnica zna
//   da je ekstenzija instalirana (umjesto oznake nudi nju).
// - Ključ čita iz localStorage stranice ('omm-kljuc', vidi
//   src/lib/kljuc-klijent.ts u omm.domovina.ai) i sprema u chrome.storage.local.
//   Uzima samo ključ koji je web već prihvatio, nikad #k= iz adrese (SEC-01 u
//   sigurnosnom auditu omm.domovina.ai), pa tuđa poveznica ne preusmjeri uvoze.
//   Web javlja promjenu (rotacija, preuzet ključ) događajem 'omm-kljuc'.
// - Je li ikona pribodena uz adresnu traku: data-omm-pribodena="1"|"0" i događaj
//   'omm-pribodena', da naslovnica vodi korisnika dok nije (pita background.js).

document.documentElement.dataset.ommEkstenzija = chrome.runtime.getManifest().version;

const OBLIK = /^[A-Za-z0-9_-]{22,64}$/;

async function preuzmi() {
  let k = null;
  try { k = localStorage.getItem('omm-kljuc'); } catch {}
  if (!k || !OBLIK.test(k)) return;
  // Sinkrono, prije await: naslovnica ga čita na DOMContentLoaded, odmah iza ovoga.
  document.documentElement.dataset.ommEkstenzijaPovezana = '1';
  const { kljuc } = await chrome.storage.local.get('kljuc');
  if (kljuc !== k) await chrome.storage.local.set({ kljuc: k });
}

window.addEventListener('omm-kljuc', preuzmi);
if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', preuzmi);
else preuzmi();

function pribodena(p) {
  if (typeof p !== 'boolean') return;
  document.documentElement.dataset.ommPribodena = p ? '1' : '0';
  window.dispatchEvent(new Event('omm-pribodena'));
  if (p && anketa) { clearInterval(anketa); anketa = null; }
}

let anketa = null;
async function pitajPribodena() {
  let o;
  try { o = await chrome.runtime.sendMessage({ pitajPribodena: true }); } catch { return; }
  if (!o) return;
  pribodena(o.pribodena);
  // Stariji Chromium bez onUserSettingsChanged: pitaj dok ikona nije u traci.
  if (!o.prati && o.pribodena === false && !anketa) {
    anketa = setInterval(() => { if (document.visibilityState === 'visible') pitajPribodena(); }, 1500);
  }
}

chrome.storage.onChanged.addListener((c, podrucje) => {
  if (podrucje === 'local' && c.pribodena) pribodena(c.pribodena.newValue);
});
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') pitajPribodena(); });
pitajPribodena();
