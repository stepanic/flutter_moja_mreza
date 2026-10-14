# Desktop: Chrome extension za uvoz

Isti uvoz kao `FlutterMojaMreza.uvezi()`, ali u pregledniku na računalu.
Kod je u `extension/`. Isproban 2026-10-05 u Braveu (MV3, „Load unpacked“), verzije
0.1 (stalna dozvola za portal), 0.2 (dozvola na zahtjev) i 0.3 (`activeTab` s
ekranom pristanka, trenutna):
1 OMM, 46 očitanja, 23 razdoblja potrošnje, isto kao na Androidu.

## Zašto extension

| Opcija | Ocjena |
|---|---|
| **Chrome extension (MV3)** | izabrano: jedan klik na prijavljenoj kartici, `activeTab` bez stalnog pristupa ijednoj stranici, ništa ne napušta preglednik bez korisnika |
| Bookmarklet / isječak u konzoli | od 2026-10-14 napravljen kao „bez instalacije“ put na omm.domovina.ai: [2026-10-14-uvoz-bez-instalacije.md](2026-10-14-uvoz-bez-instalacije.md) |
| Userscript (Tampermonkey) | ionako treba instalirati dodatak, i to tuđi |
| Web app s extensionom kao mostom | sljedeći korak kad „naš sustav“ postoji: `externally_connectable` za našu domenu, extension vraća JSON stranici |
| File System Access | ne donosi ništa preko običnog preuzimanja |

Što točno čita, za korisnike: [kako-citamo-podatke.md](kako-citamo-podatke.md).

## Kako radi

```mermaid
sequenceDiagram
    participant K as Korisnik
    participant P as Popup extensiona
    participant T as Kartica mojamreza.hep.hr
    participant O as omm.domovina.ai
    K->>T: Prijava (e-Građani, Certilia)
    K->>P: klik na ikonu → Uvezi
    P->>T: chrome.scripting: uvoz.js (izolirani svijet)
    T->>T: fetch /Postavke, /Ocitanja?omm=, /Potrosnja?omm= (same-origin, cookieji sesije)
    T-->>P: JSON (oblik HepUvoz.toJson(), bez OIB-a)
    opt kvačica „pošalji na omm.domovina.ai“ (zadano uključena)
        P->>O: POST /api/snimak {izvor: hep, uvoz}, Bearer ključ extensiona
    end
    P->>K: Preuzmi JSON / Kopiraj JSON
```

- `uvoz.js` je prijepis `lib/src/parser.dart` (stupci po nazivu iz `thead`, prvi
  stupac retka `<th scope="row">`, provjera `?omm=` preko `option[selected]`).
  Promjena parsera mijenja se na oba mjesta.
- Datoteka je u IIFE-u jer se pri svakom kliku ponovno ubacuje u istu karticu
  (top-level `const`/`class` bi drugi put bacio grešku).
- Dozvole: `activeTab` i `scripting`, bez ijedne domene, pa instalacija nema
  upozorenje. Klik na ikonu daje pristup kliknutoj kartici dok se s nje ne ode.
  Zašto ne `optional_host_permissions`: vidi usporedbu u
  [2026-10-05-uvoz-arhitektura-i-povjerenje.md](2026-10-05-uvoz-arhitektura-i-povjerenje.md).
- Popup prvo pokaže ekran pristanka (što se čita, što ne). Na kartici koja nije
  `https://mojamreza.hep.hr/` nudi samo „Otvori mojamreza.hep.hr“ i ništa ne
  ubacuje.
- Od 0.4.0 popup nakon uvoza šalje snimak na omm.domovina.ai, kao gumb
  „Pošalji snimak“ u example aplikaciji. Ključ uređaja i izbor kvačice su u
  `localStorage` popupa (origin extensiona). Server ima `Access-Control-Allow-Origin: *`,
  pa `host_permissions` nije potreban. Lokacija se ne šalje (traži dozvolu
  `geolocation`).
- Popup mora ostati otvoren dok uvoz traje (par sekundi); ako se zatvori,
  rezultat se gubi i treba ponovno kliknuti.

## Razvoj

```bash
cd extension
npm install && npm test   # isti fixturei i provjere kao test/parser_test.dart (linkedom)
npm run zip               # build/moja-mreza-extension.zip za Chrome Web Store
```

Učitavanje: `brave://extensions` (ili `chrome://extensions`) → Developer mode →
Load unpacked → `extension/`. To ne može napraviti browser alat; radi korisnik.

## Otvoreno

- Nije objavljen u Chrome Web Storeu; nema ikona.
- Predaja „našem sustavu“ (`externally_connectable` ili POST) čeka backend.
- Rad s više OMM-ova neprovjeren, kao i na mobitelu.
