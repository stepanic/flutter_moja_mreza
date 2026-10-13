# Moj račun HEP Elektre: rute i uvoz

Snimljeno 2026-10-13 na https://mojracun.hep.hr/elektra (verzija „Mojračun v3.0.3“,
bundle `main-YWNEM3F6.js`), u prijavljenom pregledniku.

## Kako radi portal

- Angular SPA, API je JSON na `/elektra/v1/api/…`; sesija je cookie
  (`withCredentials`), refresh `POST api/korisnik/refresh-token` svakih 13 min.
- Prijava je **korisničko ime i lozinka** (`POST api/korisnik/prijava`), ne
  e-Građani kao na Mojoj mreži. Lozinku upisuje samo korisnik.
- Popis kupaca (`korisnik.kupci[]`, s `kupacId` i `master`) stiže **samo u
  odgovoru prijave** i živi u memoriji aplikacije. `GET api/korisnik` i
  `GET api/kupac` vraćaju 405. Nakon osvježavanja stranice aplikacija ide na
  `/elektra/login` iako je cookie možda još valjan.
- Ekrani: Kupci, Promet, Potrošnja (kartice Potrošnja / Proizvodnja), Opomene,
  Informativni obračun, Kalkulator, Korisnik. Informativni obračun i Kalkulator
  računaju se u pregledniku iz `obracun/{id}` i `obracun/cjenik`.

## Rute koje uvoz čita (GET)

| Ruta | Odgovor |
|---|---|
| `api/ocitanja/{kupacId}` | `[{kupacId, datum (ISO, npr. 2026-10-01T01:59:00Z), tarifa1, tarifa2, tarifa3, nacinOcitanja, obracunato}]`, najnovije prvo, od 2019. |
| `api/potrosnja/{kupacId}` | `[{razdoblje: "01.09.2026 - 30.09.2026", tarifa1, tarifa2, tarifa3, proizv1, proizv2}]` |
| `api/promet/{kupacId}` | `{promet: [{datum, opis: Račun\|Uplaćeno, duguje, potrazuje, saldo, dospijeva, pnb, iznosIspis, racun, status: RED\|GREEN\|""}], saldo: {iznos, opis, iznosVal}}`. Kod uplata je `dospijeva` trenutno vrijeme, ne rok. |

Ne čitaju se, iako su GET: `api/opomene/{kupacId}` (kod nas prazna lista,
oblik nepoznat), `api/obracun/{kupacId}` (zadnje očitanje i saldo, već u
gornjima), `api/obracun/cjenik` (javni cjenik).

Ne poziva se nikad: PDF računa i opomene (`POST api/promet/kupac/{id}/racun/{n}`,
`POST api/opomene/kupac/{id}/broj/{n}`), promjene kupca i korisnika
(`api/kupac…`, `api/korisnik…`), barkod uplatnice.

## Odakle kupacId

Iz URL-ova zahtjeva koje je stranica već poslala
(`performance.getEntriesByType('resource')`, npr. `…/api/potrosnja/30390034`).
Nakon prijave aplikacija sama učita ekran odabranog kupca, pa je id tu.
Ime, ugovorni račun, OMM i adresa čitaju se iz zaglavlja „Kupac“
(`app-kupac-list`) i pripisuju zadnje korištenom kupcu. Ostali kupci (ako ih
korisnik otvarao) dobiju samo podatke iz API-ja.

## JSON uvoza

`MojRacunUvoz.toJson()` (`lib/src/moj_racun.dart`) = `mojRacunUvoz()`
(`extension/mojracun.js`):

```json
{
  "izvor": "https://mojracun.hep.hr",
  "dohvaceno": "2026-10-13T13:00:00.000Z",
  "kupci": [{
    "kupac_id": "10000001", "ime": "PERO PERIĆ", "ugovorni_racun": "2200000001",
    "omm": "0100031779", "adresa": "ULICA 1, 10000 MJESTO, HR",
    "saldo": { "iznos_eur": 0, "opis": "Dospjeli dug na dan 13.10.2026:" },
    "ocitanja": [{ "datum": "2026-10-01", "opis": "Procijenjeno od strane ODS-a", "t1_kwh": 42947, "t2_kwh": 15797 }],
    "potrosnja": [{ "od": "2026-09-01", "do": "2026-09-30", "t1_kwh": 171, "t2_kwh": 70, "ukupno_kwh": 241, "predano_t1_kwh": 0, "predano_t2_kwh": 0 }],
    "promet": [{ "datum": "2026-10-24", "opis": "Račun", "duguje_eur": 44.47, "potrazuje_eur": 0, "dospijeva": "2026-10-24", "poziv_na_broj": "2200000001-260920-7", "racun": "100000000002", "status": "RED" }]
  }]
}
```

Retci `ocitanja` i `potrosnja` imaju iste ključeve kao kod Moje mreže
(`potrosnja` dodaje `predano_*`). Fixturei: `test/fixtures/mojracun/`.

## Otvoreno

- Mobilna aplikacija nema transport za Moj račun (WebView s prijavom na
  `mojracun.hep.hr`); parser je spreman.

## omm.domovina.ai

Extension (od 0.6.0) šalje uvoz kao snimak `izvor: hep-moj-racun`, uz istu
kvačicu kao za Moju mrežu. Server za usporedbu sa zadnjim stanjem gleda zadnji
uvoz iz oba izvora (`kupci[]` odnosno `mjesta[]`) i preskače očitanja
„Procijenjeno od strane ODS-a“, jer procjena nije stanje brojila.
