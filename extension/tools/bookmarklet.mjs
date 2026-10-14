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

const dijelovi = ['uvoz.js', 'mojracun.js', 'bookmarklet.js'].map((d) => {
  const kod = readFileSync(join(ovdje, d), 'utf8');
  return `// ---- ${d} ----\n${kod}`;
});

// bookmarklet.js čita svoj src preko document.currentScript, što radi samo
// dok se izvršava sinkrono, a to vrijedi i za spojenu datoteku.
const zaglavlje =
  '// Generirano iz github.com/stepanic/flutter_moja_mreza (extension/tools/bookmarklet.mjs).\n' +
  '// Ne mijenjati ovdje: izvor su extension/uvoz.js, mojracun.js i bookmarklet.js.\n';
writeFileSync(izlaz, zaglavlje + dijelovi.join('\n'));
console.log(`${izlaz} (${Math.round((zaglavlje + dijelovi.join('\n')).length / 1024)} kB)`);
