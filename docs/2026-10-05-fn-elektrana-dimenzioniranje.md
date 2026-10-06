# FN elektrana za OMM 0100031779: dimenzioniranje, otkup viška i izbor opreme

Stanje 2026-10-05. Analiza za vlastitu kuću (Donja Lomnica, priključak 11,04 kW
trofazno, HEPI bijeli VT/NT, grijanje dizalicom topline). Ništa još nije kupljeno.

Vezani dokumenti: [hep-moja-mreza-recept.md](hep-moja-mreza-recept.md),
[2026-10-02-uvoz-omm-preporuke.md](2026-10-02-uvoz-omm-preporuke.md). Stvarni HEP
računi i projekcija zime su u repou `rezije` (`data/racuni/HEP-ANALIZA.md`, izvan gita).

## Alati

| Skripta | Što radi |
|---|---|
| `tools/fn_procjena/fn_procjena.py` | PVGIS satna proizvodnja (cache u `data/pvgis_cache/`) × stvarna potrošnja iz očitanja; sweep nagiba/snaga, `--varijante "6:0:16\|7.4n"` (polja nagib:azimut:kWp, baterija kWh, `n` = NT punjenje X–III), `--izvoz-max 11.04`, `--ac-max` |
| `tools/fn_procjena/izvjestaj_potrosnje.py` | PDF za izvođače: mjesečna VT/NT potrošnja, grafovi, sva očitanja s datumima (interpolirani mjeseci šrafirani) |

Model opterećenja je ravnomjeran unutar VT (06–20 UTC) i NT; nema satnog brojila.
Cijene: +35 % stopa cijelu godinu (VT 0,2375, NT 0,1201 €/kWh s mrežom i PDV-om), pa je
ljetna ušteda ~5–10 % precijenjena (ljeti bi s elektranom bio ispod praga 3.000 kWh/6 mj).

## Potrošnja

~9.100–9.500 kWh/god, VT ~63 %. Zime ~5.700–5.900 kWh (X–III), vrh prosinac 2025.
1.422 kWh (46 kWh/dan). 17 od 24 mjeseca (X/2024–IX/2026) interpolirano jer je HEP slao
procjene; najdulji razmak bez očitanja 31.01.–26.07.2026. (176 dana). Od 07/2026 daljinsko
očitanje.

## Otkup viška (ključno za veličinu)

Elektrane priključene od 1.1.2026. su u **neto-obračunu** (ZOIEVUK čl. 51, mjesečno):
`Ci = k·PKC` ako predano ≤ preuzeto, inače `k·PKC·preuzeto/predano` → ukupni otkup u
mjesecu je najviše `k·PKC·preuzeto`. k = 0,9 (KKVP) ili kSO (HERA predložila 1 za kućanstva
do kraja 2026.; okvir donesen 16.07.2026., konačni kSO nije provjeren). PKC = cijena energije
bez mrežarine (~0,08–0,11 €/kWh).

| Za ~12 MWh viška godišnje | Vrijednost |
|---|---|
| Neto-obračun (2026+) | ~210–240 € (≈1,8–2 c/kWh) |
| Netiranje (stari KPSO, zahtjev do 31.12.2025.) | ~1.300 € (≈10–12 c/kWh) |

Posljedica: dimenzionirati za vlastitu potrošnju + baterija; višak skoro ništa ne vrijedi.

## Rezultati simulacije (krov 6°, jug)

| Sustav | €/god | Napomena |
|---|---|---|
| 6 kWp, bez baterije | 915 | |
| 8 kWp + 7,4 kWh, NT punjenje | 1.223 | |
| 16 kWp + 7,4 kWh, NT punjenje | 1.418 | višak ~12 MWh → 213 € |
| 41 kWp + 30 kWh | 1.694 | „zima na nuli" — povrat dodatka 25–30 g, odbačeno |

- Nagib 6° gubi ~10 % godišnje prema optimalnih 40°; 60° nadstrešnica / 90° ograda daju
  ~2× više po kWp zimi, ali ograda E–W (monofacijalno) samo 593 kWh/kWp.
- Zimi elektrana pokriva 30–40 % (prosinac ~0,98 kWh/kWp/dan na 6°); P20 dani ~0,4.
- Baterija bez panela (NT→VT, 0,104 €/kWh razlike): optimum ~16 kWh nazivno (+418–502 €/god);
  iznad toga +24–38 €/modul jer je dnevni VT IV–IX samo ~15 kWh.
- Inverter 10 kW uz 16 kWp na 6°: rezanje samo ~95 kWh/god.

## CROPEX (dan unaprijed, X/2025–IX/2026)

Ponderirano tvojom potrošnjom burza = 119 €/MWh, HEP energija = 88 €/MWh (+285 €/god razlike
na štetu HEP-a). 217 negativnih sati, gotovo svi u podne III–VII, min −327 €/MWh (svibanj).
Od ožujka do rujna noć je na burzi skuplja od dana (VT/NT tarifa je obrnuta od tržišta).
Mjesečni agregati: `data/cropex_dan_unaprijed_mjesecno.csv`. API `api.cropex.hr/web/v1/dayahead`
traži Bearer token koji stranica dobije iz `/web/v1/cfg`; radi samo iz preglednika.

## Izbor opreme

**Odabrano (košarica solar-kit, 3.396 € neto):** Deye SUN-20K-SG05LP3-EU-SM2 (1.871 €) +
Deye SE-F16 Max 16,38 kWh (1.525 €).

| Odbačeno / alternativa | Zašto |
|---|---|
| Deye SE-F16-C (1.465 €) | jamstvo 25 MWh → istekne za ~5 god uz ~5 MWh/god; Max ima 50 MWh, grijanje, IP65 za +60 € |
| GB-S10K…20K (HV, outlet) | 5 g jamstva, vjerojatno stara generacija; HV baterija ~165 €/kWh + BMS → sustav ~4.300 € |
| SUN-20K-SG01HP3 (HV) | jeftiniji inverter, ali s HV baterijom ukupno ~4.100 € |
| Dyness Powerbrick Plus (1.417 €) | kompatibilan s SG05LP3, −108 €, ali dva proizvođača i bez navedenih MWh |
| Keno B2B (FoxESS/GoodWe paketi) | 535–810 € skuplje za ~16 kWh, baterije ≥135 €/kWh |
| nJoy Astris 20K | mrežni inverter bez baterije |
| nJoy Ascet LV 20K + Bastion F15K | tehnički ravnopravno (3 MPPT, 1000 V, 380 A, AFCI), inverter bez cijene (Bastion 1.400 €, vidi ponudu niže); OEM nepoznat (najbliži SRNE HESP48200SH3, ali 380 A / 160–980 V / 20 A po MPPT se ne poklapaju) — nije stari Deye |

### nJoy ponuda 2026-10-06 (neto, bez PDV-a i prijevoza)

| Stavka | PN | Cijena |
|---|---|---|
| Ascet 25K-2x75/3P3T6 (hibrid 25 kW, AFCI, 3 MPPT) | SIH33025H256ACCU0B | 1.900 € |
| Bastion WF15K 14,3 kWh, 51,2 V 280 Ah | ESWMF15K5120BDA01B | 1.400 € |

- **Par ne radi zajedno:** Ascet 25K je HV (baterija 120–800 V, „H“ u PN-u; LV modeli
  imaju „L“, npr. SIH33020**L**203 za LV 20K), a Bastion je LV 51,2 V. Treba tražiti
  cijenu za Ascet LV 20K.
- Ascet LV 20K (2026-10-06): na njoy.global je u „Available products“ s datasheetom, priručnicima
  i CE (trofazna LV serija 6K–20K, baterija 40–60 V, 380 A), ali ga nijedan shop ne nudi —
  generatorautomat.ro, spy-shop.ro i compari.ro (19 nJoy invertora) imaju samo HV trofazne i LV monofazne
  Ascete. Vjerojatno nov, još nije u distribuciji → pitati rok isporuke.
- Bastion WF15K = Bastion F15K (isti PN). Pod / zid / kotači, 129,5 kg neto.
- Ascet 25K u mrežu daje do 27,5 kW, a priključak je 11,04 kW, pa je predimenzioniran.
- Baterija 97,7 €/kWh vs Deye SE-F16 Max 93,1 €/kWh. Da nJoy bude jednak Deyeu po €/kWh,
  Ascet LV 20K mora koštati ≤ ~1.770 € neto (Deye par: 3.396 € za 16,38 kWh).
- Spy-shop.ro prodaje HV 25K za 14.245,48 lei s PDV-om (≈ 2.206 € neto po tečaju ECB-a 5,3363),
  pa je nJoyevih 1.900 € ~14 % ispod najjeftinijeg shopa; Bastion 1.400 € je ~15 % ispod (spy-shop 1.641 €).
- **Zaključak 2026-10-06:** nJoy trofazni LV se trenutno ne može kupiti nigdje; jedini dostupan
  trofazni LV 20 kW je Deye SG05LP3-20K (košarica solar-kit).
- Cijene svih dostupnih Asceta i Bastiona po shopovima su lokalno u `data/analize/` (gitignored).

Cijela elektrana (Tongwei 505 Wp ×32 = 2.101 €, nosači Enerack ~300–750 €, mjerenje,
zaštite, kabeli) ≈ 6.400–7.050 € neto opreme, + rad ~1.500–3.000 €.

Usporedni dokumenti (Claude Docs): Deye sustav
<https://claude.ai/code/artifact/07a6465d-09b4-42d6-93dd-6505f0fa8bd8>, nJoy sustav
<https://claude.ai/code/artifact/dcb17ee4-17bb-4e33-ac83-67c3bba68625>.

## Otvoreno

- HEP ODS: prihvaća li 15/20 kW inverter softverski ograničen na 11,04 kW? Ako ne → SG05LP3-10K.
- Cijene SG05LP3-10K/12K/15K (restock 05.10. i 20.10.2026.).
- Vrsta krova (lim / membrana / crijep) i 32 panela vs puna paleta → točan popis nosača.
- Smiješ li kao kupac s vlastitom proizvodnjom puniti bateriju iz mreže (NT punjenje).
- Račun 9/2026 (~08.10.) potvrđuje cijenu nakon 1.9.2026. (vidi `rezije`).
- nJoy: cijena Ascet LV 20K (dobili HV 25K), prijevoz, jamstvo (god. i MWh), OEM, HEP ODS certifikati, kompatibilnost s SE-F16 Max.
