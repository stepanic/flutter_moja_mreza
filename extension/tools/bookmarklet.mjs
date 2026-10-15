// Spaja parsere i bookmarklet u jednu datoteku koju servira omm.domovina.ai.
//
//   node tools/bookmarklet.mjs [izlaz]
//
// Zadani izlaz je public/hep-uvoz.js u susjednom repou omm.domovina.ai
// (~/git/domovinatv/omm.domovina.ai), pa se nakon promjene parsera pokrene
// ovo i deploya taj repo.

import { readFileSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ovdje = join(dirname(fileURLToPath(import.meta.url)), '..');
const izlaz = process.argv[2] ?? join(homedir(), 'git/domovinatv/omm.domovina.ai/public/hep-uvoz.js');

const dijelovi = ['uvoz.js', 'mojracun.js', 'hepi.js', 'bookmarklet.js'].map((d) => {
  const kod = readFileSync(join(ovdje, d), 'utf8');
  return `// ---- ${d} ----\n${kod}`;
});

// bookmarklet.js čita svoj src preko document.currentScript, što radi samo
// dok se izvršava sinkrono, a to vrijedi i za spojenu datoteku.
const zaglavlje =
  '// Generirano iz github.com/stepanic/flutter_moja_mreza (extension/tools/bookmarklet.mjs).\n' +
  '// Ne mijenjati ovdje: izvor su extension/uvoz.js, mojracun.js, hepi.js i bookmarklet.js.\n';
// Samo ASCII: server šalje text/javascript bez charseta, a Moj račun i Hepi ne
// šalju charset ni za stranicu, pa bi preglednik skriptu mogao čitati kao
// Windows-1250 i „č“ bi postao „ÄŤ“. \uXXXX vrijedi u nizovima, predlošcima,
// regexima i komentarima, a regex bez zastavice u ide po UTF-16 jedinicama,
// pa i emoji postanu ispravan par.
const kod = (zaglavlje + dijelovi.join('\n')).replace(/[^\x00-\x7f]/g, (z) => `\\u${z.charCodeAt(0).toString(16).padStart(4, '0')}`);
writeFileSync(izlaz, kod);
console.log(`${izlaz} (${Math.round(kod.length / 1024)} kB)`);
