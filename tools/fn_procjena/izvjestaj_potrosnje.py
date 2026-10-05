#!/usr/bin/env python3
"""PDF s mjesečnom potrošnjom (VT/NT) iz očitanja s Moje mreže, za slanje izvođačima.

    python3 tools/fn_procjena/izvjestaj_potrosnje.py data/ocitanja_0100031779.csv \
        --od 2024-10 --do 2026-09 --izlaz data/potrosnja.pdf \
        --naslovni "OMM 0100031779 · Ciglenice 38/A, Donja Lomnica" \
        --prikljucak "11,04 kW trofazno" --tarifa "Kućanstvo NN Bijeli (VT/NT)"

Mjesečne vrijednosti: HEP-ove automatske procjene se odbacuju, a potrošnja između
dva stvarna očitanja raspoređuje se ravnomjerno po danima. Mjesec u kojem više od
pola dana pada u razmak između očitanja dulji od 40 dana označen je kao interpoliran.
"""
import argparse
import calendar
import csv
import datetime as dt
from collections import defaultdict

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.patches import Patch

NEPRAVA = ("Automatska procjena", "Očitanje procijenjeno")
MJ = ["sij", "velj", "ožu", "tra", "svi", "lip", "srp", "kol", "ruj", "lis", "stu", "pro"]

# Paleta (dataviz referentna, validirana za svijetlu podlogu)
SURFACE, INK, INK2, MUTED, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#8a8984", "#e6e5e0"
VT_C, NT_C = "#2a78d6", "#eb6834"
G1_C, G2_C = "#1baf7a", "#4a3aa7"
DUGI_RAZMAK = 40


def ucitaj(csv_path):
    tocke = {}
    with open(csv_path, newline="") as fh:
        for r in csv.DictReader(fh):
            if r["opis"] in NEPRAVA:
                continue
            d = dt.date.fromisoformat(r["datum"])
            st = (int(r["t1_kwh"]), int(r["t2_kwh"]))
            tocke[d] = max(tocke.get(d, (0, 0)), st)
    t = sorted(tocke.items())
    # isto stanje ponovno dostavljeno kasnije (npr. 14.05. i 20.05.2025.) nije stvarno očitanje
    ocisceno = [t[0]]
    for d, st in t[1:]:
        if st != ocisceno[-1][1]:
            ocisceno.append((d, st))
    return ocisceno


def svi_redovi(csv_path):
    with open(csv_path, newline="") as fh:
        r = [(dt.date.fromisoformat(x["datum"]), x["opis"], int(x["t1_kwh"]), int(x["t2_kwh"]))
             for x in csv.DictReader(fh)]
    return sorted(r, key=lambda x: (x[0], x[1]))


def mjesecno(tocke):
    """{(g, m): dict(vt, nt, interp_dana, dana)}"""
    mj = defaultdict(lambda: dict(vt=0.0, nt=0.0, interp=0, dana=0))
    for (d0, (a1, a2)), (d1, (b1, b2)) in zip(tocke, tocke[1:]):
        n = (d1 - d0).days
        for i in range(n):
            d = d0 + dt.timedelta(days=i)
            z = mj[(d.year, d.month)]
            z["vt"] += (b1 - a1) / n
            z["nt"] += (b2 - a2) / n
            z["dana"] += 1
            z["interp"] += n > DUGI_RAZMAK
    return mj


def stil(ax):
    ax.set_facecolor(SURFACE)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.spines["bottom"].set_color(GRID)
    ax.tick_params(colors=INK2, labelsize=8, length=0)
    ax.yaxis.grid(True, color=GRID, linewidth=0.6)
    ax.set_axisbelow(True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ocitanja")
    ap.add_argument("--od", required=True, help="YYYY-MM")
    ap.add_argument("--do", required=True, help="YYYY-MM")
    ap.add_argument("--izlaz", required=True)
    ap.add_argument("--naslovni", default="")
    ap.add_argument("--prikljucak", default="")
    ap.add_argument("--tarifa", default="")
    a = ap.parse_args()

    tocke = ucitaj(a.ocitanja)
    mj = mjesecno(tocke)
    g0, m0 = map(int, a.od.split("-"))
    g1, m1 = map(int, a.do.split("-"))
    kljucevi = []
    g, m = g0, m0
    while (g, m) <= (g1, m1):
        kljucevi.append((g, m))
        g, m = (g + 1, 1) if m == 12 else (g, m + 1)
    for k in kljucevi:
        dana = calendar.monthrange(*k)[1]
        if mj[k]["dana"] < dana:
            raise SystemExit(f"{k}: nema očitanja koja pokrivaju cijeli mjesec")

    redovi = []
    for g, m in kljucevi:
        z = mj[(g, m)]
        dana = calendar.monthrange(g, m)[1]
        redovi.append(dict(g=g, m=m, vt=round(z["vt"]), nt=round(z["nt"]), dana=dana,
                           interp=z["interp"] > dana / 2))
    for r in redovi:
        r["uk"] = r["vt"] + r["nt"]
        r["dnevno"] = r["uk"] / r["dana"]
    oznaka = [f"{MJ[r['m'] - 1]}\n{r['g'] % 100:02d}" for r in redovi]

    # godine (12-mjesečna razdoblja od početka) i polugodišta (X–III, IV–IX)
    razdoblja = [redovi[i:i + 12] for i in range(0, len(redovi), 12)]
    polugodista = defaultdict(lambda: [0, 0])
    for r in redovi:
        if r["m"] >= 10:
            kljuc = f"zima {r['g']}/{(r['g'] + 1) % 100:02d}"
        elif r["m"] <= 3:
            kljuc = f"zima {r['g'] - 1}/{r['g'] % 100:02d}"
        else:
            kljuc = f"ljeto {r['g']}"
        polugodista[kljuc][0] += r["uk"]
        polugodista[kljuc][1] += 1

    plt.rcParams.update({"font.family": "DejaVu Sans", "figure.facecolor": SURFACE})
    with PdfPages(a.izlaz) as pdf:
        # ---- stranica 1: sažetak + stupci VT/NT ----
        fig = plt.figure(figsize=(8.27, 11.69))
        fig.text(0.07, 0.95, "Potrošnja električne energije po mjesecima", fontsize=17,
                 weight="bold", color=INK)
        fig.text(0.07, 0.925, f"{MJ[m0 - 1]} {g0} – {MJ[m1 - 1]} {g1} · izvor: HEP ODS Moja mreža (stanja brojila)",
                 fontsize=9.5, color=INK2)
        info = [x for x in (a.naslovni, f"Priključak: {a.prikljucak}" if a.prikljucak else "",
                            f"Tarifni model: {a.tarifa}" if a.tarifa else "") if x]
        for i, t in enumerate(info):
            fig.text(0.07, 0.895 - i * 0.018, t, fontsize=9.5, color=INK)

        # ključne brojke
        y = 0.82
        fig.text(0.07, y, "Ključne brojke", fontsize=11, weight="bold", color=INK)
        stupci = []
        for raz in razdoblja:
            uk = sum(r["uk"] for r in raz)
            vt = sum(r["vt"] for r in raz)
            pr, zr = raz[0], raz[-1]
            stupci.append((f"{MJ[pr['m'] - 1]} {pr['g']} – {MJ[zr['m'] - 1]} {zr['g']}",
                           f"{uk:,.0f} kWh".replace(",", "."), f"VT {100 * vt / uk:.0f} % · NT {100 - 100 * vt / uk:.0f} %"))
        maks = max(redovi, key=lambda r: r["uk"])
        mini = min(redovi, key=lambda r: r["uk"])
        stupci.append(("Najveći mjesec", f"{maks['uk']:,.0f} kWh".replace(",", "."),
                       f"{MJ[maks['m'] - 1]} {maks['g']} · {maks['dnevno']:.0f} kWh/dan"))
        stupci.append(("Najmanji mjesec", f"{mini['uk']:,.0f} kWh".replace(",", "."),
                       f"{MJ[mini['m'] - 1]} {mini['g']} · {mini['dnevno']:.0f} kWh/dan"))
        sir = 0.86 / len(stupci)
        for i, (n, v, p) in enumerate(stupci):
            x = 0.07 + i * sir
            fig.text(x, y - 0.03, n, fontsize=8.5, color=INK2)
            fig.text(x, y - 0.058, v, fontsize=14, weight="bold", color=INK)
            fig.text(x, y - 0.078, p, fontsize=8, color=INK2)
        pol = "   ·   ".join(f"{k}: {v[0]:,.0f} kWh".replace(",", ".") +
                             ("" if v[1] == 6 else f" ({v[1]} mj.)") for k, v in polugodista.items())
        fig.text(0.07, y - 0.105, "Po polugodištima (X–III / IV–IX):", fontsize=8.5, color=INK2)
        fig.text(0.07, y - 0.122, pol, fontsize=8.5, color=INK)

        ax = fig.add_axes([0.09, 0.30, 0.86, 0.33])
        stil(ax)
        x = range(len(redovi))
        sirina = 0.78
        for i, r in enumerate(redovi):
            h = "////" if r["interp"] else None
            ax.bar(i, r["nt"], sirina, color=NT_C, edgecolor=SURFACE if not h else "white",
                   linewidth=0, hatch=h)
            ax.bar(i, r["vt"], sirina, bottom=r["nt"] + 12, color=VT_C,
                   edgecolor="white" if h else SURFACE, linewidth=0, hatch=h)
            ax.text(i, r["uk"] + 30, f"{r['uk']}", ha="center", va="bottom", fontsize=6.3, color=INK2)
        ax.set_xticks(list(x), oznaka, fontsize=7)
        ax.set_xlim(-0.6, len(redovi) - 0.4)
        ax.set_ylabel("kWh", color=INK2, fontsize=8.5)
        ax.set_title("Mjesečna potrošnja, viša (VT) i niža (NT) tarifa", loc="left", fontsize=11,
                     color=INK, weight="bold", pad=22)
        leg = [Patch(color=VT_C, label="VT (viša tarifa)"), Patch(color=NT_C, label="NT (niža tarifa)"),
               Patch(facecolor="#bdbcb6", hatch="////", edgecolor="white", label="interpolirano (nema očitanja > 40 dana)")]
        ax.legend(handles=leg, loc="lower left", bbox_to_anchor=(0, 1.0), ncol=3, frameon=False,
                  fontsize=8, labelcolor=INK2, handlelength=1.4, borderaxespad=0.2)

        fig.text(0.07, 0.235, "Napomene", fontsize=10, weight="bold", color=INK)
        nap = [
            "• Vrijednosti su izračunate iz stvarnih stanja brojila (očitanja kupca i HEP ODS-a). HEP-ove automatske",
            "   procjene su odbačene, a potrošnja između dva očitanja raspoređena je ravnomjerno po danima.",
            "• Iznosi se zato mogu razlikovati od kWh na pojedinim računima, koji uključuju procjene i naknadne korekcije.",
            "• Šrafirani mjeseci padaju u razdoblje bez očitanja dulje od 40 dana: zbroj je točan, raspodjela po",
            "   mjesecima je procjena (posebno II–VII 2026., razmak 31.01.–26.07.2026.).",
            "• VT: 07–21 h zimi / 08–22 h ljeti; NT ostatak dana. Od 07/2026 brojilo se očitava daljinski (mjesečno).",
        ]
        for i, t in enumerate(nap):
            fig.text(0.07, 0.212 - i * 0.017, t, fontsize=8.2, color=INK2)
        fig.text(0.07, 0.03, f"Izrađeno {dt.date.today():%d.%m.%Y.} iz podataka HEP ODS Moja mreža.",
                 fontsize=7.5, color=MUTED)
        pdf.savefig(fig)
        plt.close(fig)

        # ---- stranica 2: dnevni prosjek po godinama + tablica ----
        fig = plt.figure(figsize=(8.27, 11.69))
        ax = fig.add_axes([0.09, 0.66, 0.86, 0.26])
        stil(ax)
        boje = [G1_C, G2_C]
        for j, raz in enumerate(razdoblja):
            xs = list(range(len(raz)))
            ys = [r["dnevno"] for r in raz]
            naziv = f"{MJ[raz[0]['m'] - 1]} {raz[0]['g']} – {MJ[raz[-1]['m'] - 1]} {raz[-1]['g']}"
            ax.plot(xs, ys, color=boje[j], linewidth=2, label=naziv, zorder=3)
            ax.scatter(xs, ys, s=30, color=boje[j], edgecolor=SURFACE, linewidth=2, zorder=4)
            ax.text(xs[-1] + 0.15, ys[-1], naziv.split(" – ")[1], fontsize=7.5, color=INK2, va="center")
        ax.set_xticks(range(12), [MJ[(m0 - 1 + i) % 12] for i in range(12)], fontsize=8)
        ax.set_xlim(-0.4, 11.9)
        ax.set_ylim(0, None)
        ax.set_ylabel("kWh na dan", color=INK2, fontsize=8.5)
        ax.set_title("Prosječna dnevna potrošnja, usporedba godina", loc="left", fontsize=11,
                     color=INK, weight="bold", pad=22)
        ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), ncol=2, frameon=False, fontsize=8,
                  labelcolor=INK2, borderaxespad=0.2)

        # tablica
        fig.text(0.07, 0.585, "Tablica po mjesecima (kWh)", fontsize=11, weight="bold", color=INK)
        zag = ["Mjesec", "VT", "NT", "Ukupno", "kWh/dan", "Napomena"]
        xs = [0.07, 0.27, 0.38, 0.49, 0.62, 0.74]
        y0 = 0.56
        for x, t in zip(xs, zag):
            fig.text(x, y0, t, fontsize=8.5, weight="bold", color=INK, ha="left")
        fig.add_artist(plt.Line2D([0.07, 0.93], [y0 - 0.006, y0 - 0.006], color=GRID,
                                  transform=fig.transFigure))
        dy = 0.0195
        for i, r in enumerate(redovi):
            yy = y0 - 0.022 - i * dy
            if i % 2:
                fig.add_artist(plt.Rectangle((0.065, yy - 0.006), 0.87, dy, color="#f2f1ec",
                                             transform=fig.transFigure, zorder=-1))
            vals = [f"{MJ[r['m'] - 1]} {r['g']}", f"{r['vt']}", f"{r['nt']}", f"{r['uk']}",
                    f"{r['dnevno']:.1f}", "interpolirano" if r["interp"] else ""]
            for x, t in zip(xs, vals):
                fig.text(x, yy, t, fontsize=8.2, color=INK if t != "interpolirano" else MUTED)
        yy = y0 - 0.022 - len(redovi) * dy
        fig.add_artist(plt.Line2D([0.07, 0.93], [yy + 0.012, yy + 0.012], color=GRID,
                                  transform=fig.transFigure))
        for raz in razdoblja:
            vt = sum(r["vt"] for r in raz)
            nt = sum(r["nt"] for r in raz)
            dana = sum(r["dana"] for r in raz)
            vals = [f"Σ {MJ[raz[0]['m'] - 1]} {raz[0]['g'] % 100:02d} – {MJ[raz[-1]['m'] - 1]} {raz[-1]['g'] % 100:02d}",
                    f"{vt}", f"{nt}", f"{vt + nt}", f"{(vt + nt) / dana:.1f}", ""]
            for x, t in zip(xs, vals):
                fig.text(x, yy, t, fontsize=8.2, weight="bold", color=INK)
            yy -= dy
        pdf.savefig(fig)
        plt.close(fig)

        # ---- stranica 3: sva očitanja s portala u razdoblju ----
        korištena = {d: st for d, st in tocke}
        pocetak = dt.date(g0, m0, 1)
        prije = max(d for d, _ in tocke if d < pocetak)
        svi = [x for x in svi_redovi(a.ocitanja) if x[0] >= prije]
        fig = plt.figure(figsize=(8.27, 11.69))
        fig.text(0.07, 0.95, "Očitanja brojila s datumima", fontsize=15, weight="bold", color=INK)
        fig.text(0.07, 0.93, "Svi zapisi s mojamreza.hep.hr/Ocitanja u razdoblju. Sivo: HEP-ove procjene "
                 "i ponovljena stanja, nisu korišteni u izračunu.", fontsize=8.5, color=INK2)
        zag = ["Datum", "Opis", "Stanje VT", "Stanje NT", "Dana", "VT kWh", "NT kWh", "kWh/dan"]
        xs = [0.07, 0.18, 0.50, 0.59, 0.66, 0.74, 0.82, 0.91]
        desno = [False, False, True, True, True, True, True, True]
        y0 = 0.895
        for x, t, d in zip(xs, zag, desno):
            fig.text(x + (0.065 if d else 0), y0, t, fontsize=8, weight="bold", color=INK,
                     ha="right" if d else "left")
        fig.add_artist(plt.Line2D([0.07, 0.98], [y0 - 0.006, y0 - 0.006], color=GRID,
                                  transform=fig.transFigure))
        dy = min(0.0185, 0.82 / max(len(svi), 1))
        vidjeno = set()
        for i, (d, opis, t1, t2) in enumerate(reversed(svi)):
            yy = y0 - 0.02 - i * dy
            koristen = (korištena.get(d) == (t1, t2) and opis not in NEPRAVA
                        and (d, t1, t2) not in vidjeno)
            if koristen:
                vidjeno.add((d, t1, t2))
            boja = INK if koristen else MUTED
            vals = [f"{d:%d.%m.%Y.}", opis.replace("Dostavljeno stanje preračunato na zadnji dan u mjesecu",
                                                   "Stanje kupca preračunato na kraj mjeseca"),
                    f"{t1}", f"{t2}", "", "", "", ""]
            if koristen:
                prethodni = max((x for x in tocke if x[0] < d), default=None)
                if prethodni and prethodni[0] >= prije:
                    n = (d - prethodni[0]).days
                    dv, dn = t1 - prethodni[1][0], t2 - prethodni[1][1]
                    vals[4:] = [f"{n}", f"{dv}", f"{dn}", f"{(dv + dn) / n:.1f}"]
            for x, t, dsn in zip(xs, vals, desno):
                fig.text(x + (0.065 if dsn else 0), yy, t, fontsize=7.6, color=boja,
                         ha="right" if dsn else "left")
        fig.text(0.07, 0.03, "Stanja su u kWh (cijeli brojevi, kako ih prikazuje portal). Dana/VT/NT/kWh dan = "
                 "razlika prema prethodnom korištenom očitanju.", fontsize=7.5, color=MUTED)
        pdf.savefig(fig)
        plt.close(fig)
    print("Spremljeno:", a.izlaz)
    for r in redovi:
        print(f"{r['g']}-{r['m']:02d} VT {r['vt']:5d} NT {r['nt']:5d} uk {r['uk']:5d} {r['dnevno']:5.1f}/dan"
              f"{'  interp' if r['interp'] else ''}")


if __name__ == "__main__":
    main()
