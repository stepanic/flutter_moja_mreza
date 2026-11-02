# Chrome Web Store: objava ekstenzije (2026-10-30)

**Stanje 2026-11-02: v0.7.1 odobrena i objavljena**,
<https://chromewebstore.google.com/detail/uvoz-s-hep-a-za-ommdomovi/eaepdcjoahegcgokhpbgppdeanpcfadi>.
Pregled je trajao oko tri dana. Svaka nova verzija s promjenom dozvola ili
`matches` ide na novi pregled.

Sve što Developer Dashboard traži, spremno za kopiranje. Prije toga v0.7.0 je
pravim uvozom provjerena na sva tri portala
([uvoz-bez-instalacije](2026-10-14-uvoz-bez-instalacije.md) § „Sljedeće:
ekstenzija kao glavni put“). Za objavu ide **v0.7.1**: popravljen raspored kvačice
„Nakon uvoza pošalji…“ (tekst je u flex kontejneru bio razbijen u tri stupca).

## Paket i slike

```bash
cd extension
npm test && npm run zip        # ../build/moja-mreza-extension.zip (12 datoteka)
tools/snimke/snimi.sh          # ../build/web-store/*.png
```

Snimke slaže `tools/snimke/okvir.html`: pravi `popup.html` u iframeu, s lažnim
`chrome.*` (`stub.js`) i izmišljenim podacima (OMM 0100012345, „Ulica primjera
12“), pa u njima nema ničijih podataka. Treba Google Chrome u `/Applications`.

| Datoteka | Za polje | Veličina |
|---|---|---|
| `mreza.png` | Screenshot 1 | 1280×800 |
| `hepi-gotovo.png` | Screenshot 2 | 1280×800 |
| `racun-gotovo.png` | Screenshot 3 | 1280×800 |
| `mreza-gotovo.png` | Screenshot 4 | 1280×800 |
| `drugo.png` | Screenshot 5 | 1280×800 |
| `plocica-440x280.png` | Small promo tile | 440×280 |
| `ikone/ikona-128.png` | Store icon (iz paketa) | 128×128 |

## Store listing

- **Jezik**: hrvatski
- **Kategorija**: Tools (Alati)
- **Homepage URL**: https://omm.domovina.ai/
- **Support URL**: https://omm.domovina.ai/ (kontakt ms@domovina.ai u podnožju)

**Opis** (detailed description):

```
Uvoz očitanja brojila, potrošnje i računa s HEP-ovih portala na omm.domovina.ai, gdje dobiješ pregled po mjesecima i godišnji izvještaj potrošnje (npr. za ponudu za sunčanu elektranu).

Kako radi:
1. Prijavi se kao i inače na Moju mrežu (HEP ODS), Moj račun (HEP Elektra) ili Moj Hepi račun (HEP Opskrba).
2. Klikni ikonu ekstenzije. Prije ičega piše što će pročitati, a što neće.
3. Klikni „Dopusti čitanje i uvezi“. Ekstenzija pročita tvoje podatke iz te kartice i pošalje ih na omm.domovina.ai.

Što čita: mjerna mjesta (OMM, brojilo, ime, adresa, tarifni model), stanja brojila, potrošnju po razdobljima, a s Mojeg računa i Hepija još račune, uplate i saldo. S Hepija se pročitaju i PDF-ovi novih računa; čuva se samo ono što se iz njih pročita.

Što ne radi:
- ne vidi tvoju lozinku ni prijavu na HEP-u i ne radi ništa dok ne klikneš
- ne uzima OIB
- ne šalje očitanja HEP-u i ništa ne mijenja na portalu
- ne čita druge stranice, ne prati što posjećuješ, nema oglasa ni analitike
- podatke šalje samo na omm.domovina.ai

Podatke na omm.domovina.ai možeš obrisati jednim klikom (Obriši sve moje podatke). Kod je otvoren: https://github.com/stepanic/flutter_moja_mreza

Ekstenzija nije službeni proizvod HEP-a i nije povezana s HEP grupom. Izradio ju je ITalk d.o.o. za omm.domovina.ai.
```

## Privacy practices

**Single purpose**:

```
Uvoz korisnikovih vlastitih podataka o struji (očitanja, potrošnja, računi) s HEP-ovih portala, na koje se korisnik sam prijavio, na omm.domovina.ai, na korisnikov klik.
```

**Permission justification**:

| Dozvola | Obrazloženje |
|---|---|
| `activeTab` | Pristup samo kartici HEP-ova portala u kojoj je korisnik kliknuo ikonu, i to tek kad klikne. Nema trajnog pristupa nijednoj stranici. |
| `scripting` | Na klik „Dopusti čitanje i uvezi“ u tu karticu ubaci parser iz paketa koji pročita korisnikove podatke s portala (isti API koji portal sam koristi u korisnikovoj prijavi). |
| `storage` | `chrome.storage.local`: ključ korisnika s omm.domovina.ai, da uvozi budu vidljivi na webu. `chrome.storage.session`: stanje tekućeg uvoza, da se posao ne izgubi kad se popup zatvori. |
| Host permission (content script `https://omm.domovina.ai/*`) | Preuzme korisnikov ključ s omm.domovina.ai i stranici javi da je ekstenzija instalirana. Radi samo na toj domeni, koja je odredište uvoza. |

**Remote code**: No, I am not using remote code. (Svi parseri su u paketu; `fetch` ide
samo na API HEP-ova portala iz kartice i na `omm.domovina.ai/api`.)

**Data usage**, označiti:

- [x] Personally identifiable information (ime i adresa kupca, broj mjernog mjesta)
- [x] Financial and payment information (računi, uplate, saldo)
- [ ] sve ostalo (health, authentication, personal communications, location, web history, user activity, website content) ostaje prazno

Tri potvrde (ne prodaje se trećima, ne koristi se za ništa nevezano uz svrhu, ne
koristi se za kreditnu sposobnost): sve tri da.

**Privacy policy URL**: https://omm.domovina.ai/privatnost (od 2026-10-30 ima odjeljak
„Ekstenzija za preglednik“).

## Distribution

- Free, Public
- Regije: sve (korisno samo u Hrvatskoj, ali ograničenje ne treba)

## Rizici pregleda

- **Ime s „HEP“**: pravila zabranjuju zavaravajuće predstavljanje. Opis zato kaže da nije
  službeni proizvod HEP-a; ime je opisno („Uvoz s HEP-a za omm.domovina.ai“), a ikona
  nema HEP-ov znak. Ako odbiju, rezervno ime: „Uvoz struje za omm.domovina.ai“.
- **Prijava treba za test**: recenzent nema HEP račun. U „Test instructions“ (ako ih
  traže) napisati da je za uvoz potreban korisnički račun na HEP-ovom portalu i da bez
  prijave popup pokazuje samo upute (snimka 5).

## Predano 2026-10-30

- **ID**: `eaepdcjoahegcgokhpbgppdeanpcfadi`, verzija 0.7.1, status „pending review“.
- Izdavač: Google račun stepanic.matija@gmail.com; kontakt mail izdavača postavljen i
  potvrđen u Settings (bez potvrđenog kontakt maila „Submit for review“ je siv).
- Uz snimke je predana i marquee pločica 1400×560 (`tools/snimke/marquee.html`).
- **Zamka**: Developer Console (i Web Store) ne mogu skriptirati ekstenzije, pa ni
  Claude in Chrome („The extensions gallery cannot be scripted“). Chrome DevTools MCP
  otvara zaseban Chrome bez prijave. Formu je korisnik ispunio ručno, copy-paste iz
  ovog dokumenta; slike su složene u `build/web-store/za-upload/` po redu.
- Svaka nova verzija: podigni `version` u manifestu, `npm test && npm run zip`, pa u
  Dashboardu Package → Upload new package i ponovno Submit.

## Nakon objave

1. Adresu ekstenzije na Storeu (`https://chromewebstore.google.com/detail/…`) u `WEB_STORE` (`omm.domovina.ai/src/lib/ekstenzija.ts`),
   pa `npm run deploy`: na naslovnici se pojavi gumb za Web Store.
2. Unpacked v0.7.x u Braveu ukloniti i instalirati iz Storea (drugi ID, pa ključ s
   omm.domovina.ai preuzme ponovno, kad se otvori naslovnica).
3. Sekcija „Kako to radi“ na naslovnici još opisuje samo oznaku.
