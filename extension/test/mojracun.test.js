// Isti fixturei i iste provjere kao test/moj_racun_test.dart.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { DOMParser } = require('linkedom');

globalThis.DOMParser = DOMParser;
const { MojRacunParser } = require('../mojracun.js');

const dir = path.join(__dirname, '../../test/fixtures/mojracun');
const json = (ime) => JSON.parse(fs.readFileSync(path.join(dir, `${ime}.json`), 'utf8'));

test('ocitanja: datum iz ISO, način očitanja je opis', () => {
  const o = MojRacunParser.ocitanja(json('ocitanja'));
  assert.equal(o.length, 3);
  assert.deepEqual(o[0], { datum: '2026-10-01', opis: 'Procijenjeno od strane ODS-a', t1_kwh: 42947, t2_kwh: 15797 });
  assert.equal(o[2].datum, '2019-10-01');
});

test('potrosnja: razdoblje "dd.mm.yyyy - dd.mm.yyyy", proizv je predano', () => {
  const p = MojRacunParser.potrosnja(json('potrosnja'));
  assert.equal(p.length, 2);
  assert.deepEqual(p[0], {
    od: '2026-09-01', do: '2026-09-30', t1_kwh: 171, t2_kwh: 70, ukupno_kwh: 241, predano_t1_kwh: 0, predano_t2_kwh: 0,
  });
  assert.deepEqual([p[1].od, p[1].do, p[1].predano_t1_kwh, p[1].predano_t2_kwh], ['2019-10-01', '2019-11-04', 12, 3]);
});

test('promet: rok samo za račune, prazni stringovi su null', () => {
  const { stavke, saldo } = MojRacunParser.promet(json('promet'));
  assert.equal(stavke.length, 3);
  assert.deepEqual(stavke[0], {
    datum: '2026-10-24', opis: 'Račun', duguje_eur: 44.47, potrazuje_eur: 0, dospijeva: '2026-10-24',
    poziv_na_broj: '2200000001-260920-7', racun: '100000000002', status: 'RED',
  });
  assert.deepEqual(stavke[1], {
    datum: '2026-09-28', opis: 'Uplaćeno', duguje_eur: 0, potrazuje_eur: 45.78, dospijeva: null,
    poziv_na_broj: null, racun: null, status: null,
  });
  assert.deepEqual(saldo, { iznos_eur: 0, opis: 'Dospjeli dug na dan 13.10.2026:' });
});

test('zaglavlje Kupac: ime, ugovorni račun, OMM, adresa', () => {
  const html = fs.readFileSync(path.join(dir, 'kupac.html'), 'utf8');
  assert.deepEqual(MojRacunParser.zaglavlje(`<html><body>${html}</body></html>`), {
    ime: 'PERO PERIĆ', ugovorni_racun: '2200000001', omm: '0100031779', adresa: 'ULICA 1, 10000 MJESTO, HR',
  });
});

test('kupacIds: iz URL-ova API-ja, zadnje korišteni zadnji', () => {
  const b = 'https://mojracun.hep.hr/elektra/v1/api/';
  assert.deepEqual(
    MojRacunParser.kupacIds([`${b}obracun/cjenik`, `${b}korisnik/prijava`, `${b}potrosnja/1`, `${b}promet/2`, `${b}ocitanja/1`]),
    ['2', '1'],
  );
});

test('neočekivan oblik je neocekivanOdgovor', () => {
  assert.throws(() => MojRacunParser.ocitanja({}), (e) => e.greska === 'neocekivanOdgovor');
  assert.throws(() => MojRacunParser.promet([]), (e) => e.greska === 'neocekivanOdgovor');
});
