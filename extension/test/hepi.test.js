// Fixturei su anonimizirani odgovori /hepi/api/… (test/fixtures/hepi).
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { HepiParser } = require('../hepi.js');

const dir = path.join(__dirname, '../../test/fixtures/hepi');
const json = (ime) => JSON.parse(fs.readFileSync(path.join(dir, `${ime}.json`), 'utf8'));

test('kupci: objekt po kupacId, bez OIB-a i maila', () => {
  const k = HepiParser.kupci(json('kupci'));
  assert.deepEqual(k, [{
    kupac_id: '10000000001', sifra_kupca: '10000001', ime: 'IME PREZIME', omm: '0100000001',
    adresa: 'MJESTO, ULICA 1', tarifni_model: 'hepi bijeli', ugovor_od: '2025-02-01',
  }]);
  assert.ok(!JSON.stringify(k).includes('00000000000'));
  assert.ok(!JSON.stringify(k).includes('@'));
});

test('potrosnja: razdoblje iz "dd.mm.yyyy-dd.mm.yyyy", očitanja s načinom', () => {
  const { potrosnja, ocitanja } = HepiParser.potrosnja(json('potrosnja'));
  assert.deepEqual(potrosnja[0], { od: '2026-09-01', do: '2026-09-30', t1_kwh: 299, t2_kwh: 128, ukupno_kwh: 427 });
  assert.equal(potrosnja.length, 2);
  assert.deepEqual(ocitanja[0], { datum: '2026-09-30', opis: 'Elektra', t1_kwh: 15284, t2_kwh: 8990 });
});

test('promet: saldo, računi s poveznicom na PDF, uplate', () => {
  const { saldo, racuni, uplate } = HepiParser.promet(json('promet'));
  assert.deepEqual(saldo, { iznos_eur: 92.58, opis: 'Dug' });
  assert.deepEqual(racuni[0], {
    datum: '2026-09-01', poziv_na_broj: '0010000001-260920-2', iznos_eur: 92.58, dospijeva: '2026-10-23',
    placen: false, status: 'Nije podmiren', link: 'AAAA0000000000000000000000001',
  });
  assert.equal(racuni[1].placen, true);
  assert.deepEqual(uplate, [{ datum: '2026-10-05', iznos_eur: 46.56 }]);
});

test('neočekivan odgovor baca neocekivanOdgovor', () => {
  assert.throws(() => HepiParser.promet({ Total: {} }), (e) => e.greska === 'neocekivanOdgovor');
  assert.throws(() => HepiParser.kupci(null), (e) => e.greska === 'neocekivanOdgovor');
});
