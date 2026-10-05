#!/usr/bin/env python3
"""Procjena FN elektrane za jedan OMM: PVGIS proizvodnja + stvarna potrošnja s Moje mreže.

Samo standardna biblioteka. Primjer:

    python3 tools/fn_procjena/fn_procjena.py data/ocitanja_0100031779.csv \
        --lat 45.727 --lon 16.022 --aspect 0

Što radi:
1. Iz očitanja (bez automatskih procjena) složi dnevnu potrošnju VT/NT linearnom
   interpolacijom i zbroji je po mjesecima zadnjih 12 punih mjeseci.
2. Iz PVGIS-a (seriescalc, satni podaci po kWp) za svaki nagib izračuna
   proizvodnju, vlastitu potrošnju sat po sat i višak predan u mrežu.
3. Za svaku snagu i nagib izračuna godišnju uštedu i jednostavni povrat.

Model opterećenja: unutar dana potrošnja je ravnomjerna po satima, posebno za VT
i NT razdoblje (VT = 06–20 UTC, što je 7–21 zimi / 8–22 ljeti po lokalnom vremenu).
Bez satnog brojila ne znamo stvarni dnevni profil, pa je vlastita potrošnja
procjena. Grijanje noću i zimi je u modelu, jer dolazi iz stvarnih mjesečnih NT/VT.
"""
import argparse
import calendar
import csv
import datetime as dt
import json
import pathlib
import urllib.parse
import urllib.request
from collections import defaultdict

PVGIS = "https://re.jrc.ec.europa.eu/api/v5_3/seriescalc"
CACHE = pathlib.Path(__file__).resolve().parents[2] / "data" / "pvgis_cache"

# Cijene s računa HEPI bijeli, 08/2026. Uštede su s PDV-om 13 %.
PDV = 1.13
VT_KUPNJA = (0.131205 + 0.013239 + 0.044446 + 0.021256) * PDV  # energija+OIE+distribucija+prijenos
NT_KUPNJA = (0.064379 + 0.013239 + 0.020514 + 0.008175) * PDV
VT_ENERGIJA, NT_ENERGIJA = 0.131205, 0.064379  # samo energija, za otkup viška

NEPRAVA = ("Automatska procjena", "Očitanje procijenjeno")


def mjesecna_potrosnja(csv_path):
    """{(godina, mjesec): (vt, nt)} za zadnjih 12 punih mjeseci iz stvarnih očitanja."""
    rows = []
    with open(csv_path, newline="") as fh:
        for r in csv.DictReader(fh):
            if r["opis"] in NEPRAVA:
                continue
            rows.append((dt.date.fromisoformat(r["datum"]), int(r["t1_kwh"]), int(r["t2_kwh"])))
    rows = sorted(set(rows))
    # isti dan s dva očitanja: uzmi zadnje (veće) stanje
    po_danu = {}
    for d, t1, t2 in rows:
        po_danu[d] = max(po_danu.get(d, (0, 0)), (t1, t2))
    tocke = sorted(po_danu.items())

    dnevno = {}
    for (d0, (a1, a2)), (d1, (b1, b2)) in zip(tocke, tocke[1:]):
        n = (d1 - d0).days
        for i in range(n):
            dnevno[d0 + dt.timedelta(days=i)] = ((b1 - a1) / n, (b2 - a2) / n)

    zadnji = tocke[-1][0]
    kraj = dt.date(zadnji.year, zadnji.month, 1)  # prvi dan nepotpunog mjeseca
    mj = defaultdict(lambda: [0.0, 0.0])
    for d, (v, n) in dnevno.items():
        if d < kraj:
            mj[(d.year, d.month)][0] += v
            mj[(d.year, d.month)][1] += n
    kljucevi = sorted(mj)[-12:]
    return {k: tuple(mj[k]) for k in kljucevi}, tocke


def pvgis_satno(lat, lon, angle, aspect, loss, godine, mountingplace="building"):
    CACHE.mkdir(parents=True, exist_ok=True)
    q = dict(lat=lat, lon=lon, peakpower=1, loss=loss, angle=angle, aspect=aspect,
             pvcalculation=1, mountingplace=mountingplace,
             startyear=godine[0], endyear=godine[1], outputformat="json")
    f = CACHE / ("_".join(f"{k}{v}" for k, v in q.items() if k != "outputformat") + ".json")
    if not f.exists():
        url = PVGIS + "?" + urllib.parse.urlencode(q)
        with urllib.request.urlopen(url, timeout=120) as r:
            f.write_bytes(r.read())
    h = json.loads(f.read_text())["outputs"]["hourly"]
    # (godina, mjesec, dan, sat_utc) -> kWh po kWp (P je u W za 1 kWp)
    return [(int(x["time"][:4]), int(x["time"][4:6]), int(x["time"][6:8]),
             int(x["time"][9:11]), x["P"] / 1000) for x in h]


def zbroji_polja(a, god, opis):
    """'6:0:5,90:0:2' (nagib:azimut:kWp) -> zbirna satna proizvodnja u kWh i ukupni kWp.

    Okomita polja (nagib >= 60) računaju se kao slobodnostojeća (ograda, bolje hlađenje)."""
    ukupno, kwp_uk = {}, 0.0
    for polje in opis.split(","):
        n, az, kwp = (float(x) for x in polje.split(":"))
        mp = "free" if n >= 60 else "building"
        for g, m, d, h, p in pvgis_satno(a.lat, a.lon, int(n), int(az), a.loss, god, mp):
            k = (g, m, d, h)
            ukupno[k] = ukupno.get(k, 0.0) + p * kwp
        kwp_uk += kwp
    return [(*k, v) for k, v in ukupno.items()], kwp_uk


def simuliraj(sati, potrosnja, kwp, otkup_faktor, bat_kwh=0.0, bat_kw=5.0, nt_punjenje=False,
              bat_eff=0.9, ac_max=None, izvoz_max=None):
    """Prosječna godina: proizvodnja, vlastita potrošnja, višak i ušteda u eurima.

    Baterija (bat_kwh korisno) puni se viškom FN-a i prazni kad FN ne pokriva potrošnju.
    S nt_punjenje u mjesecima X–III dodatno se noću (NT) puni iz mreže i prazni samo u VT.
    Ušteda = trošak energije i mreže bez elektrane − trošak s elektranom (uključuje NT punjenje)."""
    po_mj = {m: v for (_, m), v in potrosnja.items()}
    godine = sorted({s[0] for s in sati})
    zbroj = defaultdict(lambda: defaultdict(float))
    ef = bat_eff ** 0.5  # gubitak pola pri punjenju, pola pri pražnjenju
    soc = 0.0
    for g, m, d, h, p in sati:
        vt, nt = po_mj[m]
        dana = calendar.monthrange(g, m)[1]
        jeVT = 6 <= h < 20
        opterecenje = (vt / dana / 14) if jeVT else (nt / dana / 10)
        pv = p * kwp
        z = zbroj[m]
        if ac_max and pv > ac_max:  # AC snaga invertera
            z["odbaceno"] += pv - ac_max
            pv = ac_max
        z["pv"] += pv
        direktno = min(pv, opterecenje)
        visak, manjak = pv - direktno, opterecenje - direktno
        iz_bat = 0.0
        if bat_kwh:
            u = min(visak, bat_kw, (bat_kwh - soc) / ef)
            soc += u * ef
            visak -= u
            zimsko_nt = nt_punjenje and m in (10, 11, 12, 1, 2, 3)
            if manjak and (jeVT or not zimsko_nt):
                iz_bat = min(manjak, bat_kw, soc * ef)
                soc -= iz_bat / ef
                manjak -= iz_bat
            if zimsko_nt and not jeVT and h < 6 and pv == 0:
                u = min(bat_kw, (bat_kwh - soc) / ef)
                soc += u * ef
                manjak += u  # punjenje iz mreže je dodatni uvoz po NT cijeni
                z["nt_punjenje"] += u
        z["vlastita"] += pv - visak  # FN potrošen direktno ili spremljen u bateriju
        if izvoz_max and visak > izvoz_max:  # softverski limit predaje u mrežu
            z["odbaceno"] += visak - izvoz_max
            visak = izvoz_max
        z["visak"] += visak
        z["visak_vt" if jeVT else "visak_nt"] += visak
        z["uvoz_vt" if jeVT else "uvoz_nt"] += manjak
    n = len(godine)
    rez = {}
    for m in range(1, 13):
        z = defaultdict(float, {k: v / n for k, v in zbroj[m].items()})
        vt, nt = po_mj[m]
        uvoz = z["uvoz_vt"] + z["uvoz_nt"]
        # Otkup viška (čl. 51. ZOIE, kako ga razumijemo): 0,9 × prosječna cijena energije,
        # umanjeno razmjerno ako je predano više nego preuzeto iz mreže u tom mjesecu.
        pkc = (VT_ENERGIJA * vt + NT_ENERGIJA * nt) / (vt + nt)
        cijena = otkup_faktor * pkc * min(1.0, uvoz / z["visak"]) if z["visak"] else 0
        rez[m] = dict(potrosnja=vt + nt, pv=z["pv"], vlastita=z["vlastita"],
                      visak=z["visak"], uvoz=uvoz, odbaceno=z["odbaceno"],
                      visak_vt=z["visak_vt"], visak_nt=z["visak_nt"],
                      uvoz_vt=z["uvoz_vt"], uvoz_nt=z["uvoz_nt"],
                      usteda=(vt - z["uvoz_vt"]) * VT_KUPNJA + (nt - z["uvoz_nt"]) * NT_KUPNJA,
                      otkup=z["visak"] * cijena)
    return rez


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ocitanja")
    ap.add_argument("--lat", type=float, required=True)
    ap.add_argument("--lon", type=float, required=True)
    ap.add_argument("--aspect", type=int, default=0, help="azimut: 0=jug, -90=istok, 90=zapad")
    ap.add_argument("--nagibi", default="10,20,30,40,50,60")
    ap.add_argument("--snage", default="3,4,5,6,7,8,10,12")
    ap.add_argument("--loss", type=float, default=14)
    ap.add_argument("--godine", default="2016,2023")
    ap.add_argument("--eur-po-kwp", type=float, default=1100, help="cijena ugradnje s PDV-om, pretpostavka")
    ap.add_argument("--otkup-faktor", type=float, default=0.9)
    ap.add_argument("--varijante", help="usporedba kombinacija polja odvojenih s ';', "
                    "polje = nagib:azimut:kWp, npr. '6:0:6;90:0:4;6:0:5,90:0:3'; "
                    "baterija iza '|' u kWh, sa 'n' i NT punjenje zimi: '6:0:6|10n'")
    ap.add_argument("--ac-max", type=float, help="AC snaga invertera u kW")
    ap.add_argument("--izvoz-max", type=float, help="limit predaje u mrežu u kW, npr. 11.04")
    ap.add_argument("--detalj", help="snaga,nagib za mjesečnu tablicu, npr. 6,40")
    a = ap.parse_args()

    potrosnja, _ = mjesecna_potrosnja(a.ocitanja)
    god = tuple(int(x) for x in a.godine.split(","))
    print("Potrošnja po mjesecima (iz stvarnih očitanja, interpolirano):")
    for (g, m), (vt, nt) in potrosnja.items():
        print(f"  {g}-{m:02d}  VT {vt:6.0f}  NT {nt:6.0f}  ukupno {vt + nt:6.0f} kWh")
    uk = sum(v + n for v, n in potrosnja.values())
    racun = sum(v * VT_KUPNJA + n * NT_KUPNJA for v, n in potrosnja.values()) + 12 * (0.982 + 1.983) * PDV
    print(f"  godišnje {uk:.0f} kWh, račun ~{racun:.0f} € s PDV-om "
          f"(VT {VT_KUPNJA:.4f}, NT {NT_KUPNJA:.4f} €/kWh)\n")

    if a.varijante:
        print(f"{'varijanta':<26} {'kWp':>5} {'kWh/god':>8} {'zima*':>6} {'kWh/kWp':>7} {'vlast.%':>7} "
              f"{'ušteda €':>8} {'otkup €':>7} {'ukupno €':>8} {'odbač.':>6} {'višak':>6}")
        for v in a.varijante.split(";"):
            polja, _, bat = v.partition("|")
            sati_v, kwp = zbroji_polja(a, god, polja)
            r = simuliraj(sati_v, potrosnja, 1.0, a.otkup_faktor,
                          bat_kwh=float(bat.rstrip("n") or 0), nt_punjenje=bat.endswith("n"),
                          ac_max=a.ac_max, izvoz_max=a.izvoz_max)
            odb = sum(x["odbaceno"] for x in r.values())
            pv = sum(x["pv"] for x in r.values())
            zima = sum(r[m]["pv"] for m in (11, 12, 1, 2))
            vl = sum(x["vlastita"] for x in r.values())
            us = sum(x["usteda"] for x in r.values())
            ot = sum(x["otkup"] for x in r.values())
            print(f"{v:<26} {kwp:5.1f} {pv:8.0f} {zima:6.0f} {pv / kwp:7.0f} {100 * vl / pv:7.0f} "
                  f"{us:8.0f} {ot:7.0f} {us + ot:8.0f} {odb:6.0f} {sum(x['visak'] for x in r.values()):6.0f}")
        print("* zima = proizvodnja XI–II u kWh")
        return

    nagibi = [int(x) for x in a.nagibi.split(",")]
    snage = [float(x) for x in a.snage.split(",")]
    sati = {n: pvgis_satno(a.lat, a.lon, n, a.aspect, a.loss, god) for n in nagibi}

    print(f"PVGIS {god[0]}–{god[1]}, azimut {a.aspect}°, gubici {a.loss} %, "
          f"ugradnja {a.eur_po_kwp:.0f} €/kWp\n")
    print(f"{'kWp':>4} {'nagib':>5} {'kWh/god':>8} {'zima*':>6} {'vlast.%':>7} {'pokriv.%':>8} "
          f"{'ušteda €':>8} {'otkup €':>7} {'ukupno €':>8} {'povrat g':>8}")
    for kwp in snage:
        najbolji = None
        for n in nagibi:
            r = simuliraj(sati[n], potrosnja, kwp, a.otkup_faktor)
            pv = sum(x["pv"] for x in r.values())
            zima = sum(r[m]["pv"] for m in (11, 12, 1, 2))
            vl = sum(x["vlastita"] for x in r.values())
            us = sum(x["usteda"] for x in r.values())
            ot = sum(x["otkup"] for x in r.values())
            povrat = kwp * a.eur_po_kwp / (us + ot)
            red = (us + ot, f"{kwp:4.0f} {n:5d} {pv:8.0f} {zima:6.0f} {100 * vl / pv:7.0f} "
                            f"{100 * vl / uk:8.0f} {us:8.0f} {ot:7.0f} {us + ot:8.0f} {povrat:8.1f}")
            najbolji = max(najbolji or red, red)
            print(red[1])
        print(f"     → najbolji nagib za {kwp:.0f} kWp: {najbolji[1].split()[1]}°\n")
    print("* zima = proizvodnja XI–II u kWh")

    if a.detalj:
        kwp, n = a.detalj.split(",")
        r = simuliraj(sati[int(n)], potrosnja, float(kwp), a.otkup_faktor)
        print(f"\nMjesečno za {kwp} kWp, nagib {n}°:")
        print(f"{'mj':>3} {'potr.':>6} {'PV':>6} {'vlast.':>6} {'višak':>6} {'uvoz':>6} {'ušteda €':>8} {'otkup €':>7}")
        for m, x in r.items():
            print(f"{m:3d} {x['potrosnja']:6.0f} {x['pv']:6.0f} {x['vlastita']:6.0f} {x['visak']:6.0f} "
                  f"{x['uvoz']:6.0f} {x['usteda']:8.0f} {x['otkup']:7.0f}")


if __name__ == "__main__":
    main()
