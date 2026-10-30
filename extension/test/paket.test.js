// Paket za Web Store mora imati sve što manifest, popup i background traže.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ovdje = path.join(__dirname, '..');

test('paket ima parsere svih triju portala i sve datoteke postoje', async () => {
  const { datoteke } = await import('../tools/zip.mjs');
  const popis = datoteke();
  for (const d of ['uvoz.js', 'mojracun.js', 'hepi.js', 'background.js', 'omm.js', 'popup.js', 'ikone/ikona-128.png']) {
    assert.ok(popis.includes(d), `${d} nije u paketu`);
  }
  for (const d of popis) assert.ok(fs.existsSync(path.join(ovdje, d)), `${d} ne postoji`);
});

test('popup.js dohvaća samo elemente koji postoje u popup.html', () => {
  const html = fs.readFileSync(path.join(ovdje, 'popup.html'), 'utf8');
  const js = fs.readFileSync(path.join(ovdje, 'popup.js'), 'utf8');
  const id = new Set([...html.matchAll(/id="([^"]+)"/g)].map((m) => m[1]));
  const trazeni = [...js.matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]);
  // $(`uvezi-${izvor}`) i ODJELJCI: po jedan za svaki izvor.
  trazeni.push('uvezi-mreza', 'uvezi-racun', 'uvezi-hepi', 'spremno', 'spremno-racun', 'spremno-hepi');
  for (const t of trazeni) assert.ok(id.has(t), `#${t} nema u popup.html`);
});
