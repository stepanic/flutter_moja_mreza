#!/usr/bin/env python3
"""Godišnji izvještaj potrošnje struje za jedno mjerno mjesto (OMM), PDF.

    python3 tools/izvjestaj/izvjestaj.py data/omm/0100031779.yaml
    python3 tools/izvjestaj/izvjestaj.py data/omm/*.yaml --anonimno

Ulaz je profil OMM-a (YAML) koji pokazuje na uvoz s Moje mreže (HepUvoz ili
jedno mjesto) ili s Mojeg računa (MojRacunUvoz). Profil dodaje ono što portal
ne daje: naziv, priključak (faza, snaga), lokaciju, ručna očitanja, napomene.
Profili sadrže osobne podatke i žive u gitignored data/omm/.

Metoda: mjesečno = stanje brojila na prvi dan mjeseca, linearno između
stvarnih očitanja. Procjene ODS-a se izbacuju, osim kad bez njih razdoblje
nema početak ili kraj. Cijene su današnji cjenik HEP Elektre (javni API Mojeg
računa), primijenjene na cijelo razdoblje.
"""
import argparse
import datetime as dt
import json
import math
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

import jinja2
import yaml

OVDJE = Path(__file__).parent
CJENIK_URL = "https://mojracun.hep.hr/elektra/v1/api/obracun/cjenik"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
DUGI_RAZMAK = 45  # dana bez stvarnog očitanja nakon kojih je mjesec „raspodijeljen“
PRAG = 3000  # kWh po polugodištu (lis–ožu, tra–ruj); iznad toga energija +35 %
MJ = ["sij", "velj", "ožu", "tra", "svi", "lip", "srp", "kol", "ruj", "lis", "stu", "pro"]
MJD = ["siječanj", "veljača", "ožujak", "travanj", "svibanj", "lipanj", "srpanj",
       "kolovoz", "rujan", "listopad", "studeni", "prosinac"]
DANI = ["pon", "uto", "sri", "čet", "pet", "sub", "ned"]


def hr(x, dec=0):
    return f"{x:,.{dec}f}".replace(",", "X").replace(".", ",").replace("X", ".")


def hr_datum(d):
    return f"{d.day}.{d.month}.{d.year}."


# ---------------------------------------------------------------- ulaz

def mjesto_iz_uvoza(uvoz, omm):
    """Normalizira uvoz s Moje mreže ili Mojeg računa u jedan rječnik."""
    if "kupci" in uvoz:  # Moj račun
        k = next(k for k in uvoz["kupci"] if k.get("omm") == omm)
        return dict(izvor="Moj račun (HEP Elektra)", dohvaceno=uvoz["dohvaceno"], korisnik=k.get("ime"),
                    adresa=k.get("adresa"), brojilo=None, ugovorni_racun=k.get("ugovorni_racun"),
                    tarifni_model=None, ocitanja=k["ocitanja"],
                    racuni=[s for s in k.get("promet", []) if s["opis"] == "Račun"])
    if "mjesta" in uvoz:  # HepUvoz
        dohvaceno = uvoz["dohvaceno"]
        uvoz = next(m for m in uvoz["mjesta"] if m["omm"] == omm)
        uvoz = {**uvoz, "dohvaceno": dohvaceno}
    return dict(izvor="Moja mreža (HEP ODS)", dohvaceno=uvoz.get("dohvaceno"), korisnik=uvoz.get("korisnik"),
                adresa=uvoz.get("adresa"), brojilo=uvoz.get("broj_brojila"), ugovorni_racun=None,
                tarifni_model=uvoz.get("tarifni_model"), ocitanja=uvoz["ocitanja"], racuni=[])


def cjenik(cache):
    if cache.exists() and dt.date.fromtimestamp(cache.stat().st_mtime) == dt.date.today():
        return json.loads(cache.read_text())
    with urllib.request.urlopen(CJENIK_URL, timeout=20) as r:
        c = json.load(r)
    cache.write_text(json.dumps(c))
    return c


def cijene(c):
    def mreza(m, t):
        return c[m]["prijenos"][t] + c[m]["distribucija"][t]
    return dict(
        bijeli=dict(ev=c["bijeli"]["proizvodnja"]["vt"], en=c["bijeli"]["proizvodnja"]["nt"],
                    mv=mreza("bijeli", "vt"), mn=mreza("bijeli", "nt")),
        plavi=dict(e=c["plavi"]["proizvodnja"]["vt"], m=mreza("plavi", "vt")),
        oie=c["oie"], fiksno=c["opskrba"] + c["plavi"]["mjernaUsluga"], pdv=1 + c["pdv"],
    )


# ---------------------------------------------------------------- izračun

def procjena(opis):
    return bool(re.search(r"proc|preračun", opis or "", re.I))


def tocke(m, profil, od, do):
    """Točke (datum, t1, t2, opis, vrsta) od kojih se interpolira; vrsta: stvarno|rucno|procjena."""
    rucna = [(dt.datetime.fromisoformat(a), float(v)) for a, v in profil.get("rucna_ocitanja") or []]
    rucni_dani = {d.date() for d, _ in rucna}
    sve = []
    for o in m["ocitanja"]:
        if o.get("t1_kwh") is None:
            continue
        d = dt.datetime.fromisoformat(o["datum"])
        sve.append((d, o["t1_kwh"], o.get("t2_kwh") or 0, o["opis"],
                    "procjena" if procjena(o["opis"]) or not o["t1_kwh"] else "stvarno"))
    stvarne = [t for t in sve if t[4] == "stvarno" and t[0].date() not in rucni_dani]
    t2_rucno = max((t[2] for t in stvarne), default=0)  # ručno se piše samo T1; T2 stoji
    stvarne += [(d, v, t2_rucno, "Ručno očitanje", "rucno") for d, v in rucna]
    # Dva očitanja istog trenutka (kupac i ODS 1.10.): vrijedi veće stanje.
    po_trenutku = {}
    for t in stvarne:
        if t[0] not in po_trenutku or (t[1], t[2]) > (po_trenutku[t[0]][1], po_trenutku[t[0]][2]):
            po_trenutku[t[0]] = t
    stvarne = sorted(po_trenutku.values())
    # Isto stanje ponovno dostavljeno kasnije nije novo očitanje.
    ocisceno = []
    for t in stvarne:
        if not ocisceno or (t[1], t[2]) != (ocisceno[-1][1], ocisceno[-1][2]):
            ocisceno.append(t)
    procjene = sorted(t for t in sve if t[4] == "procjena" and t[1])
    if not any(t[0] <= od for t in ocisceno):
        prije = [t for t in procjene if t[0] <= od]
        if not prije:
            sys.exit(f"{profil['omm']}: nema očitanja prije {od:%d.%m.%Y}")
        ocisceno.insert(0, prije[-1])
    if not any(t[0] >= do for t in ocisceno):
        poslije = [t for t in procjene if t[0] >= do and t[0] > ocisceno[-1][0]]
        if not poslije:
            sys.exit(f"{profil['omm']}: nema očitanja ni procjene nakon {do:%d.%m.%Y}")
        ocisceno.append(poslije[0])
    return ocisceno


def dana(a, b):
    return (b - a).total_seconds() / 86400


def stanje(pts, d, k):
    for a, b in zip(pts, pts[1:]):
        if a[0] <= d <= b[0]:
            return a[k] + (b[k] - a[k]) * dana(a[0], d) / dana(a[0], b[0])
    raise ValueError(d)


def interval(pts, d):
    for a, b in zip(pts, pts[1:]):
        if a[0] <= d < b[0]:
            return a, b


def mjeseci(pts, od, n=12):
    out = []
    for i in range(n):
        y, mo = od.year + (od.month - 1 + i) // 12, (od.month - 1 + i) % 12 + 1
        a = dt.datetime(y, mo, 1)
        b = dt.datetime(y + (mo == 12), mo % 12 + 1, 1)
        t1 = stanje(pts, b, 1) - stanje(pts, a, 1)
        t2 = stanje(pts, b, 2) - stanje(pts, a, 2)
        raspodijeljeno = False
        for d in range((b - a).days):
            p, q = interval(pts, a + dt.timedelta(d))
            if dana(p[0], q[0]) > DUGI_RAZMAK or "procjena" in (p[4], q[4]):
                raspodijeljeno = True
        out.append(dict(od=a, t1=t1, t2=t2, kwh=t1 + t2, raspodijeljeno=raspodijeljeno))
    return out


def trosak(mj, model, c):
    """Mjesečni trošak s PDV-om za model 'bijeli' ili 'plavi'; prag po polugodištu."""
    kum, out = 0, []
    for x in mj:
        if x["od"].month in (10, 4):
            kum = 0
        preko = max(0, kum + x["kwh"] - PRAG) - max(0, kum - PRAG)
        kum += x["kwh"]
        f = 1 + 0.35 * (preko / x["kwh"] if x["kwh"] else 0)
        if model == "bijeli":
            b = c["bijeli"]
            en = (x["t1"] * b["ev"] + x["t2"] * b["en"]) * f
            mr = x["t1"] * (b["mv"] + c["oie"]) + x["t2"] * (b["mn"] + c["oie"])
        else:
            en = x["kwh"] * c["plavi"]["e"] * f
            mr = x["kwh"] * (c["plavi"]["m"] + c["oie"])
        out.append(dict(energija=en * c["pdv"], mreza=mr * c["pdv"], fiksno=c["fiksno"] * c["pdv"], preko=preko,
                        ukupno=(en + mr + c["fiksno"]) * c["pdv"]))
    return out


def raspon_mjeseci(mjs):
    if not mjs:
        return ""
    a, b = mjs[0]["od"], mjs[-1]["od"]
    return MJD[a.month - 1] if a == b else f"{MJD[a.month - 1]}–{MJD[b.month - 1]}"


# ---------------------------------------------------------------- grafovi (SVG)

def zaokruzi_gore(v):
    if v <= 0:
        return 1, 1
    e = 10 ** math.floor(math.log10(v))
    for k in (1, 2, 2.5, 5, 10):
        if v <= k * e * 5:
            korak = k * e
            return korak * math.ceil(v / korak), korak
    return v, v / 5


def put_stupca(x, y, w, h, r):
    if h <= 0:
        return ""
    r = min(r, h, w / 2)
    return (f"M{x:.1f},{y + h:.1f} V{y + r:.1f} Q{x:.1f},{y:.1f} {x + r:.1f},{y:.1f} H{x + w - r:.1f} "
            f"Q{x + w:.1f},{y:.1f} {x + w:.1f},{y + r:.1f} V{y + h:.1f} Z")


def stupci(stavke, oznake, fmt, W=680, H=215, L=46, R=10, T=18, B=34, crta=None, podoznake=None):
    """stavke: lista lista (vrijednost, css klasa) odozdo prema gore."""
    maxv, korak = zaokruzi_gore(max(sum(v for v, _ in s) for s in stavke) * 1.08)
    s = f'<svg viewBox="0 0 {W} {H}" width="100%">'
    v = 0
    while v <= maxv + 1e-9:
        y = T + (H - T - B) * (1 - v / maxv)
        s += (f'<line x1="{L}" x2="{W - R}" y1="{y:.1f}" y2="{y:.1f}" class="grid"/>'
              f'<text x="{L - 6}" y="{y + 4:.1f}" class="ax" text-anchor="end">{fmt(v)}</text>')
        v += korak
    slot = (W - L - R) / len(stavke)
    bw = slot * 0.62
    for i, segs in enumerate(stavke):
        cx, y0 = L + slot * i + slot / 2, H - B
        for j, (val, cls) in enumerate(segs):
            h = (H - T - B) * val / maxv
            s += f'<path d="{put_stupca(cx - bw / 2, y0 - h, bw, h - (2 if j else 0), 4 if j == len(segs) - 1 else 0)}" class="{cls}"/>'
            y0 -= h
        s += f'<text x="{cx:.1f}" y="{y0 - 5:.1f}" class="val" text-anchor="middle">{fmt(sum(v for v, _ in segs))}</text>'
        s += f'<text x="{cx:.1f}" y="{H - B + 15}" class="ax" text-anchor="middle">{oznake[i]}</text>'
        if podoznake:
            s += f'<text x="{cx:.1f}" y="{H - B + 28}" class="ax" text-anchor="middle">{podoznake[i]}</text>'
    if crta is not None:
        y = T + (H - T - B) * (1 - crta / maxv)
        s += f'<line x1="{L}" x2="{W - R}" y1="{y:.1f}" y2="{y:.1f}" class="prosjek"/>'
    return s + f'<line x1="{L}" x2="{W - R}" y1="{H - B}" y2="{H - B}" class="base"/></svg>'


# ---------------------------------------------------------------- izvještaj

def izvjestaj(profil_put, args):
    profil = yaml.safe_load(Path(profil_put).read_text())
    omm = str(profil["omm"])
    uvoz = json.loads((Path(profil_put).parent / profil["uvoz"]).read_text())
    m = mjesto_iz_uvoza(uvoz, omm)
    c = cijene(cjenik(Path(profil_put).parent / "cjenik.json"))

    # Izvoz jednog mjesta nema datum dohvata; tada ga daje profil.
    dohvaceno = dt.date.fromisoformat(str(profil.get("dohvaceno") or m["dohvaceno"])[:10])
    if args.od:
        od = dt.datetime.strptime(args.od, "%Y-%m")
    else:  # zadnjih 12 punih mjeseci prije dohvata
        od = dt.datetime(dohvaceno.year - 1, dohvaceno.month, 1)
    do = dt.datetime(od.year + 1, od.month, 1)

    pts = tocke(m, profil, od, do)
    mj = mjeseci(pts, od)
    tm = (profil.get("tarifni_model") or m["tarifni_model"] or "").lower()
    model = "bijeli" if "bijeli" in tm else "plavi"
    tr = trosak(mj, model, c)
    for x, t in zip(mj, tr):
        x.update(t)

    kwh = sum(x["kwh"] for x in mj)
    eur = sum(x["ukupno"] for x in mj)
    t2 = sum(x["t2"] for x in mj)
    dvoregistarsko = t2 > kwh * 0.01
    zima, ljeto = sum(x["kwh"] for x in mj[:6]), sum(x["kwh"] for x in mj[6:])
    preko = sum(x["preko"] for x in mj)

    # ---- tekst objašnjenja, iz podataka
    biljeske = ["Mjesečna potrošnja je razlika stanja brojila na prvi dan mjeseca, linearno interpolirana "
                "između očitanja s portala."]
    biljeske.append("Uzeta su samo stvarna očitanja (kupac, ODS, daljinsko"
                    + (", ručna s točnim satom" if profil.get("rucna_ocitanja") else "")
                    + "). Procjene ODS-a i „preračunata“ stanja su izbačena"
                    + (", osim gdje bez njih razdoblje nema početak ili kraj." if any(p[4] == "procjena" for p in pts) else "."))
    for a, b in zip(pts, pts[1:]):
        n = dana(a[0], b[0])
        if b[0] <= od or a[0] >= do:
            continue
        unutra = [x for x in mj if a[0] < x["od"] + dt.timedelta(days=27) and x["od"] < b[0]]
        k = (b[1] - a[1]) + (b[2] - a[2])
        if b[4] == "procjena":
            biljeske.append(f"Zadnje stvarno očitanje je {hr_datum(a[0])} Razdoblje {raspon_mjeseci(unutra)} ide do "
                            f"procjene ODS-a za {hr_datum(b[0])} ({hr(k / n, 1)} kWh/dan). Novo očitanje brojila "
                            "učinilo bi te mjesece točnima.")
        elif a[4] == "procjena":
            biljeske.append(f"Prvo stvarno očitanje u razdoblju je {hr_datum(b[0])}; početak se oslanja na procjenu "
                            f"ODS-a za {hr_datum(a[0])}.")
        elif n > DUGI_RAZMAK:
            biljeske.append(f"Od {hr_datum(a[0])} do {hr_datum(b[0])} nema stvarnog očitanja ({hr(k)} kWh u "
                            f"{hr(n)} dana, {hr(k / n, 1)} kWh/dan), pa je {raspon_mjeseci(unutra)} raspodijeljen ravnomjerno.")
    if preko:
        biljeske.append(f"Prag: potrošnja iznad {hr(PRAG)} kWh u polugodištu (lis–ožu, tra–ruj) plaća energiju 35 % "
                        f"skuplje; ovdje {hr(preko)} kWh. Mrežarina ostaje ista.")
    if dvoregistarsko:
        drugi = "plavi" if model == "bijeli" else "bijeli"
        eur2 = sum(t["ukupno"] for t in trosak(mj, drugi, c))
        razlika = eur2 - eur
        ime = {"bijeli": "Bijelom", "plavi": "Plavom"}
        s = (f"NT je {hr(t2 / kwh * 100)} % potrošnje. Na {ime[drugi]} bi ista godina koštala {hr(eur2, 2)} € "
             f"umjesto {hr(eur, 2)} €")
        if abs(razlika) < 10:
            s += ": tarifni modeli izađu praktički isto."
        elif razlika > 0:
            s += f", dakle sadašnji model štedi oko {hr(razlika)} € godišnje."
        else:
            s += f": prelazak bi uštedio oko {hr(-razlika)} € godišnje."
        biljeske.append(s)
    fakt = profil.get("fakturirano")
    if not fakt and m["racuni"]:
        # Poziv na broj nosi kraj obračunskog mjeseca: …-260920-… = rujan 2026.
        a, b = f"{od:%y%m}", f"{do - dt.timedelta(days=1):%y%m}"
        rac = [r for r in m["racuni"] if r["poziv_na_broj"] and a <= r["poziv_na_broj"].split("-")[1][:4] <= b]
        if rac:
            fakt = dict(od=f"{od:%Y-%m}", do=f"{do - dt.timedelta(days=1):%Y-%m}",
                        iznos=sum(r["duguje_eur"] for r in rac), racuna=len(rac), izvor="Moj račun")
    if fakt:
        isti = [x for x in mj if fakt["od"] <= f"{x['od']:%Y-%m}" <= fakt["do"]]
        biljeske.append(f"Stvarno fakturirano za {fakt['od'][5:]}/{fakt['od'][:4]}–{fakt['do'][5:]}/{fakt['do'][:4]} "
                        f"({fakt['racuna']} računa, {fakt['izvor']}): {hr(fakt['iznos'], 2)} €. Ovaj izračun za iste mjesece "
                        f"daje {hr(sum(x['ukupno'] for x in isti), 2)} €. Računi idu po procjenama i korigiraju se nakon "
                        "očitanja, a do 1.11.2025. cijene su bile niže.")
    if model == "bijeli":
        b = c["bijeli"]
        cj = (f"energija VT {hr(b['ev'], 6)} / NT {hr(b['en'], 6)}; mrežarina VT {hr(b['mv'], 6)} / "
              f"NT {hr(b['mn'], 6)}")
    else:
        cj = f"energija {hr(c['plavi']['e'], 6)}; mrežarina {hr(c['plavi']['m'], 6)}"
    biljeske.append(f"Cijene su <b>današnje</b> (bez PDV-a, €/kWh): {cj}; OIE {hr(c['oie'], 6)}. Fiksno "
                    f"{hr(c['fiksno'], 3)} €/mj. PDV {hr((c['pdv'] - 1) * 100)} %.")
    biljeske.append("Do 31.12.2025. mrežarina je bila oko 13 % niža, pa su listopad–prosinac 2025. malo precijenjeni. "
                    "Ovo je procjena, ne preslika računa. Solidarna naknada nije uključena (obračuna se i stornira).")
    biljeske += profil.get("napomene") or []

    # ---- ručna očitanja (opcionalno)
    rucno = None
    ruc = [p for p in pts if p[4] == "rucno"]
    if len(ruc) >= 2:
        iv = [(a, b, b[1] - a[1], (b[1] - a[1]) / dana(a[0], b[0])) for a, b in zip(ruc, ruc[1:])]
        uk, n = ruc[-1][1] - ruc[0][1], dana(ruc[0][0], ruc[-1][0])
        pros = uk / n
        sve_po_kwh = (mj[-1]["ukupno"] - mj[-1]["fiksno"]) / mj[-1]["kwh"] if mj[-1]["kwh"] else 0
        rucno = dict(
            graf=stupci([[(x[3], "s1")] for x in iv],
                        [f"{a[0].day}.{a[0].month}. → {b[0].day}.{b[0].month}." for a, b, _, _ in iv],
                        lambda v: hr(v, 1) if v % 1 else hr(v), H=210, B=44, crta=pros,
                        podoznake=[f"{DANI[a[0].weekday()]}–{DANI[b[0].weekday()]} · {hr(k, 1)} kWh" for a, b, k, _ in iv]),
            od=hr_datum(ruc[0][0]), do=hr_datum(ruc[-1][0]), ukupno=hr(uk, 1), dana=hr(n, 1), pros=hr(pros, 1),
            mj30=hr(pros * 30 * sve_po_kwh + mj[-1]["fiksno"], 2),
            ljeto=hr(sum(x["kwh"] for x in mj[-3:]) / 92, 1),
        )

    oznaka = lambda x: f"{MJ[x['od'].month - 1]} {x['od']:%y}"
    graf_kwh = stupci([[(x["kwh"], "s1 est" if x["raspodijeljeno"] else "s1")] for x in mj],
                      [oznaka(x) for x in mj], hr)
    graf_eur = stupci([[(x["fiksno"], "s3"), (x["mreza"], "s2"), (x["energija"], "s1")] for x in mj],
                      [oznaka(x) for x in mj], hr)

    # ---- zaglavlje
    anon = args.anonimno
    adresa = (m["adresa"] or "").title().replace(", Hr", "")
    prik = profil.get("prikljucak") or {}
    zaglavlje = [
        ("Mjerno mjesto (OMM)", f"{omm[:2]}•••••{omm[-3:]}" if anon else omm),
        ("Adresa", profil.get("mjesto") if anon else adresa),
        ("Korisnik", None if anon else (m["korisnik"] or "").title()),
        ("Brojilo", None if anon else m["brojilo"]),
        ("Tarifni model", f"{model.title()} ({'dvotarifni' if model == 'bijeli' else 'jednotarifni'})"
                          + (", brojilo mjeri VT i NT" if model == "plavi" and dvoregistarsko else "")),
        ("Opskrbljivač", profil.get("opskrbljivac")),
        ("Priključak", " · ".join(filter(None, [prik.get("faza"), prik.get("snaga_kw") and f"{hr(prik['snaga_kw'], 2)} kW"])) or None),
        ("Lokacija", None if anon or not profil.get("lokacija") else
         f"{hr(profil['lokacija']['lat'], 3)}° N, {hr(profil['lokacija']['lon'], 3)}° E"),
    ]
    razdoblje = f"{MJD[od.month - 1]} {od.year}. – {MJD[(do.month - 2) % 12]} {(do - dt.timedelta(days=1)).year}."
    izvor = f"podaci s portala {m['izvor']}, dohvaćeni {hr_datum(dohvaceno)}"
    if m["ugovorni_racun"] and not anon:
        zaglavlje.insert(4, ("Ugovorni račun", m["ugovorni_racun"]))
    if anon:
        zaglavlje = [z for z in zaglavlje if z[0] not in ("Korisnik", "Brojilo")]

    po_danu = lambda mjs: sum(x["kwh"] for x in mjs) / sum((x["od"].replace(month=x["od"].month % 12 + 1, year=x["od"].year + (x["od"].month == 12)) - x["od"]).days for x in mjs)
    vrh = max(mj, key=lambda x: x["kwh"])
    sazetak = (f"Zima (lis–ožu) {hr(zima)} kWh, oko {hr(po_danu(mj[:6]), 1)} kWh/dan · ljeto (tra–ruj) {hr(ljeto)} kWh, "
               f"oko {hr(po_danu(mj[6:]), 1)} kWh/dan. Najviši mjesec: {MJD[vrh['od'].month - 1]} {vrh['od'].year}. ({hr(vrh['kwh'])} kWh). "
               + (f"Prag od {hr(PRAG)} kWh po polugodištu je probijen, pa je {hr(preko)} kWh plaćeno s energijom skupljom za 35 %."
                  if preko else f"Prag od {hr(PRAG)} kWh po polugodištu nije probijen, pa nema uvećanja od 35 %."))

    env = jinja2.Environment(loader=jinja2.FileSystemLoader(OVDJE), autoescape=True)
    html = env.get_template("predlozak.html.j2").render(
        naslov=f"{profil.get('naziv') or 'Mjerno mjesto'} · {profil.get('mjesto') or ''}".strip(" ·"),
        adresa=profil.get("mjesto") if anon else adresa, zaglavlje=zaglavlje, razdoblje=razdoblje, izvor=izvor,
        kpi=[(f"{hr(kwh)} kWh", "godišnja potrošnja"), (f"{hr(eur)} €", "godišnji trošak s PDV-om"),
             (f"{hr(eur / 12)} €", "prosječno mjesečno"), (f"{hr(eur / kwh * 100, 1)} c", "po kWh, sve uključeno")],
        sazetak=sazetak, graf_kwh=graf_kwh, graf_eur=graf_eur,
        opskrbljivac=profil.get("opskrbljivac") or "opskrbljivač",
        retci=[dict(mjesec=f"{MJD[x['od'].month - 1]} {x['od'].year}", kwh=hr(x["kwh"]) + (" *" if x["raspodijeljeno"] else ""),
                    energija=hr(x["energija"], 2), mreza=hr(x["mreza"], 2), fiksno=hr(x["fiksno"], 2), ukupno=hr(x["ukupno"], 2))
               for x in mj],
        ukupno=dict(kwh=hr(kwh), energija=hr(sum(x["energija"] for x in mj), 2), mreza=hr(sum(x["mreza"] for x in mj), 2),
                    fiksno=hr(sum(x["fiksno"] for x in mj), 2), ukupno=hr(eur, 2)),
        dvotarifno=dvoregistarsko, biljeske=biljeske, rucno=rucno,
        ocitanja=[dict(datum=hr_datum(p[0]) + (f" {p[0]:%H:%M}" if p[4] == "rucno" else ""),
                       t1=hr(p[1], 1) if p[1] % 1 else hr(p[1]), t2=hr(p[2], 1) if p[2] % 1 else hr(p[2]), opis=p[3])
                  for p in pts if p[0] >= od - dt.timedelta(days=60)],
        izradeno=hr_datum(dt.date.today()),
    )

    izlaz = Path(args.izlaz) if args.izlaz else Path(profil_put).parent / "izvjestaji"
    izlaz.mkdir(parents=True, exist_ok=True)
    ime = re.sub(r"[^A-Za-z0-9]+", "-", f"{profil.get('naziv') or ''}-{profil.get('mjesto') or ''}".translate(
        str.maketrans("čćžšđČĆŽŠĐ", "cczsdCCZSD"))).strip("-")
    osnova = izlaz / f"Potrosnja-{ime}-{omm}-{od:%Y}-{do:%y}{'-anonimno' if anon else ''}"
    osnova.with_suffix(".html").write_text(html)
    pdf = osnova.with_suffix(".pdf")
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
                    f"--user-data-dir={izlaz / '.chrome'}", "--virtual-time-budget=5000",
                    f"--print-to-pdf={pdf}", osnova.with_suffix(".html").resolve().as_uri()],
                   check=True, capture_output=True)
    print(f"{omm}: {hr(kwh)} kWh, {hr(eur, 2)} € → {pdf}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("profili", nargs="+")
    p.add_argument("--od", help="prvi mjesec, YYYY-MM (zadano: 12 punih mjeseci prije dohvata)")
    p.add_argument("--izlaz", help="mapa za PDF (zadano: <mapa profila>/izvjestaji)")
    p.add_argument("--anonimno", action="store_true", help="bez imena, brojila i pune adrese, za dijeljenje")
    args = p.parse_args()
    for pr in args.profili:
        izvjestaj(pr, args)


if __name__ == "__main__":
    main()
