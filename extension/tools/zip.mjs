// Paket za Chrome Web Store: build/moja-mreza-extension.zip.
//
//   node tools/zip.mjs
//
// Popis datoteka se čita iz manifesta, popup.html i background.js (datoteke
// parsera koje se ubacuju u karticu), da novi parser ne ostane izvan paketa
// kao hepi.js u v0.6.0. test/paket.test.js provjerava isti popis.

import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ovdje = join(dirname(fileURLToPath(import.meta.url)), '..');
const citaj = (d) => readFileSync(join(ovdje, d), 'utf8');

export function datoteke() {
  const m = JSON.parse(citaj('manifest.json'));
  const popis = new Set(['manifest.json']);
  for (const v of Object.values(m.icons || {})) popis.add(v);
  for (const v of Object.values((m.action && m.action.default_icon) || {})) popis.add(v);
  if (m.background) popis.add(m.background.service_worker);
  for (const c of m.content_scripts || []) for (const j of c.js || []) popis.add(j);
  if (m.action && m.action.default_popup) {
    popis.add(m.action.default_popup);
    for (const [, src] of citaj(m.action.default_popup).matchAll(/<script src="([^"]+)"/g)) popis.add(src);
  }
  if (m.background) {
    for (const [, d] of citaj(m.background.service_worker).matchAll(/datoteka: '([^']+)'/g)) popis.add(d);
  }
  return [...popis].sort();
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const popis = datoteke();
  const nema = popis.filter((d) => !existsSync(join(ovdje, d)));
  if (nema.length) throw new Error(`nema datoteka: ${nema.join(', ')}`);
  const izlaz = join(ovdje, '../build/moja-mreza-extension.zip');
  mkdirSync(dirname(izlaz), { recursive: true });
  rmSync(izlaz, { force: true });
  execFileSync('zip', ['-X', izlaz, ...popis], { cwd: ovdje, stdio: 'inherit' });
  console.log(`${izlaz} (${popis.length} datoteka)`);
}
