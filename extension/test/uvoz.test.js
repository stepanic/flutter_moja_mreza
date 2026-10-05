// Isti fixturei i iste provjere kao test/parser_test.dart.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { DOMParser } = require('linkedom');

globalThis.DOMParser = DOMParser;
const { MojaMrezaParser } = require('../uvoz.js');

const fixture = (ime) =>
  fs.readFileSync(path.join(__dirname, '../../test/fixtures', `${ime}.html`), 'utf8');

test('/Postavke: OMM je u <th scope="row">, OIB se ne uvozi', () => {
  const [omm, ...ostali] = MojaMrezaParser.postavke(fixture('postavke'));
  assert.equal(ostali.length, 0);
  assert.deepEqual(omm, {
    omm: '0100031779',
    broj_brojila: '87071794',
    korisnik: 'PERO PERIĆ',
    adresa: 'ULICA 1, MJESTO',
    tarifni_model: 'Kućanstvo NN Bijeli Mjesečno',
  });
});

test('/Ocitanja: stupac Status je <th> s ikonom', () => {
  const o = MojaMrezaParser.ocitanja(fixture('ocitanja'));
  assert.equal(o.length, 3);
  assert.deepEqual(o[0], { datum: '2026-10-05', opis: 'Očitanje kupca', t1_kwh: 15343, t2_kwh: 9019 });
  assert.equal(o[2].opis, 'Očitanje od strane ODS-a');
  assert.equal(o[2].t1_kwh, 0);
});

test('/Potrosnja: razdoblje "dd.mm.yyyy. - dd.mm.yyyy."', () => {
  const p = MojaMrezaParser.potrosnja(fixture('potrosnja'));
  assert.equal(p.length, 2);
  assert.deepEqual(p[0], { od: '2026-09-01', do: '2026-09-30', t1_kwh: 299, t2_kwh: 128, ukupno_kwh: 427 });
  assert.equal(p[1].od, '2023-09-21');
});

test('odabrani OMM', () => {
  assert.equal(MojaMrezaParser.odabraniOmm(fixture('ocitanja')), '0100031779');
});

test('tablica bez očekivanih stupaca je neocekivanHtml', () => {
  assert.throws(
    () => MojaMrezaParser.ocitanja('<table><thead><tr><th>Nešto</th></tr></thead></table>'),
    (e) => e.greska === 'neocekivanHtml',
  );
});
