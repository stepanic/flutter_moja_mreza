// Godišnji izvještaj potrošnje struje za jedno mjerno mjesto.
//
// Podatke računa izvjestaj.py i predaje ih kao JSON:
//   typst compile --root / --input podaci=/apsolutna/putanja.json izvjestaj.typ out.pdf
// Ovdje je samo izgled: boje, raspored, grafovi, tablice.

#import "@preview/tiaoma:0.3.0": qrcode

#let p = json(sys.inputs.podaci)

// ---------------------------------------------------------------- boje i oblik

// DOMOVINA brend (mediakit.domovina.tv): tamnoplava i crvena hrvatske zastave.
// Logo je kopija domovina_energy_logo_square.svg iz mediakita.
#let marka = rgb("#002F6C")
#let crvena = rgb("#FF0000")
#let s1 = marka
#let s2 = rgb("#D9343A")
#let s3 = rgb("#9AAAC2")
#let ink2 = rgb("#52514e")
#let mute = rgb("#8a8984")
#let crta = rgb("#e6e5e1")
#let ploha = rgb("#fcfcfb")
#let srafura = tiling(size: (5pt, 5pt), {
  place(rect(width: 5pt, height: 5pt, fill: rgb("#C9D3E3")))
  place(line(start: (0pt, 5pt), end: (5pt, 0pt), stroke: 1.6pt + s1))
})

#set document(title: "Potrošnja struje · " + p.naslov, author: "DOMOVINA Energy · omm.domovina.ai")
#set text(font: ("Helvetica Neue", "Helvetica"), size: 9.5pt, lang: "hr")
#set par(leading: 0.55em)
#set page("a4", margin: (x: 14mm, top: 12mm, bottom: 16mm), footer: context text(7.5pt, fill: mute)[
  #text(weight: "bold", fill: marka)[DOMOVINA] Energy · omm.domovina.ai · izvještaj potrošnje struje
  #h(1fr)
  #counter(page).display() / #counter(page).final().first()
])
#show heading.where(level: 2): set text(12pt)
#show heading.where(level: 2): set block(above: 1.1em, below: 0.6em)

// ---------------------------------------------------------------- brojevi

// 1234.5 → „1.234,5“ (hrvatski: točka za tisuće, zarez za decimale)
#let hr(x, d: 0) = {
  let n = int(calc.round(calc.abs(x) * calc.pow(10, d)))
  let s = str(n)
  while s.len() <= d { s = "0" + s }
  let cijeli = s.slice(0, s.len() - d)
  let tisuce = cijeli.clusters().rev().chunks(3).map(g => g.rev().join()).rev().join(".")
  (if x < 0 and n > 0 { "−" } else { "" }) + tisuce + if d > 0 { "," + s.slice(s.len() - d) } else { "" }
}
#let jedan(x) = if calc.fract(x) == 0 { hr(x) } else { hr(x, d: 1) }

// ---------------------------------------------------------------- graf

// Lijepa gornja granica i korak osi, najviše pet koraka: 576 → (600, 200), 106 → (125, 25).
#let os(v) = {
  let e = calc.pow(10, calc.floor(calc.log(v)))
  for k in (0.1, 0.2, 0.25, 0.5, 1, 2, 2.5, 5, 10) {
    if v / (k * e) <= 5 { return (k * e * calc.ceil(v / (k * e)), k * e) }
  }
}

// stavke: za svaki stupac lista (vrijednost, boja) odozdo prema gore.
#let graf(stavke, oznake, fmt: hr, visina: 5.3cm, prosjek: none, podoznake: none) = layout(size => {
  let (L, T) = (26pt, 12pt)
  let B = if podoznake == none { 14pt } else { 25pt }
  let W = size.width
  let zbroj = stavke.map(s => s.map(x => x.at(0)).sum())
  let (vrh, korak) = os(calc.max(..zbroj) * 1.08)
  let h = visina - T - B
  let y(v) = T + h * (1 - v / vrh)
  let slot = (W - L) / stavke.len()
  let sirina = slot * 0.62
  block(width: W, height: visina, {
    let v = 0
    while v <= vrh + 1e-9 {
      place(dy: y(v), line(start: (L, 0pt), end: (W, 0pt), stroke: 0.5pt + crta))
      place(dy: y(v) - 4pt, box(width: L - 5pt, align(right, text(6.5pt, fill: ink2, fmt(v)))))
      v += korak
    }
    for (i, segmenti) in stavke.enumerate() {
      let x = L + slot * i
      let dno = visina - B
      for (j, (vrijednost, boja)) in segmenti.enumerate() {
        let v = h * vrijednost / vrh
        let gornji = j == segmenti.len() - 1
        place(dx: x + (slot - sirina) / 2, dy: dno - v,
          rect(width: sirina, height: v - if j > 0 { 1.2pt } else { 0pt }, fill: boja,
            radius: if gornji { (top: 2.5pt) } else { 0pt }))
        dno -= v
      }
      place(dx: x, dy: dno - 10pt, box(width: slot, align(center, text(6.5pt, fmt(zbroj.at(i))))))
      place(dx: x, dy: visina - B + 4pt, box(width: slot, align(center, text(6.5pt, fill: ink2, oznake.at(i)))))
      if podoznake != none {
        place(dx: x, dy: visina - B + 13pt, box(width: slot, align(center, text(6pt, fill: ink2, podoznake.at(i)))))
      }
    }
    if prosjek != none {
      place(dy: y(prosjek), line(start: (L, 0pt), end: (W, 0pt), stroke: (paint: ink2, thickness: 1pt, dash: "dashed")))
    }
    place(dy: visina - B, line(start: (L, 0pt), end: (W, 0pt), stroke: 0.6pt + luma(180)))
  })
})

#let legenda(..stavke) = text(8pt, fill: ink2, stavke.pos().map(((boja, opis)) =>
  box(width: 8pt, height: 8pt, radius: 1.5pt, fill: boja, baseline: 1pt) + h(4pt) + opis
).join(h(14pt)))

#let kartica(vrijednost, opis) = block(width: 100%, fill: ploha, stroke: 0.6pt + crta, radius: 6pt, inset: (x: 9pt, y: 8pt),
  text(15pt, weight: "bold", vrijednost) + linebreak() + text(8pt, fill: ink2, opis))

// ---------------------------------------------------------------- 1. stranica

#let logo(sirina) = image("domovina_energy_logo.svg", width: sirina)

#block(width: 100%, fill: marka, radius: 8pt, inset: (x: 10pt, y: 8pt), grid(
  columns: (auto, auto, 1fr, auto), column-gutter: 10pt, align: horizon,
  logo(1.45cm),
  [#text(15pt, weight: "black", fill: white, tracking: 0.03em)[DOMOVINA]     #v(-7pt)
    #text(11pt, fill: white)[Energy] #text(7.5pt, fill: rgb("#B9C6DA"))[· omm.domovina.ai]],
  text(8.5pt, fill: rgb("#D3DCEA"))[#text(9.5pt, weight: "bold", fill: white)[Koliko zapravo trošiš struje?] \
    Uvezi potrošnju s HEP-ove Moje mreže ili Mojeg računa i dobij ovakav izvještaj, besplatno.],
  box(fill: white, radius: 4pt, inset: 3pt, qrcode(p.url, width: 1.45cm)),
))

#v(4pt)
#text(19pt, weight: "bold")[Potrošnja struje: #p.naslov]
#v(-10pt)
#text(fill: ink2)[#p.adresa · #p.razdoblje \ #text(8pt, p.izvor)]

#block(width: 100%, stroke: 0.6pt + crta, radius: 6pt, clip: true, grid(
  columns: (1fr,) * 4, inset: (x: 7pt, y: 5pt), stroke: 0.5pt + crta,
  ..p.zaglavlje.map(z => [
    #text(6.5pt, fill: mute, tracking: 0.04em, upper(z.oznaka)) \
    #if z.vrijednost != none { text(weight: "semibold", z.vrijednost) } else { text(fill: mute, style: "italic")[nije upisano] }
  ]),
))

#let u = p.ukupno
#grid(columns: (1fr,) * 4, column-gutter: 8pt,
  kartica[#hr(u.kwh) kWh][godišnja potrošnja],
  kartica[#hr(u.eur) €][godišnji trošak s PDV-om],
  kartica[#hr(u.eur / 12) €][prosječno mjesečno],
  kartica[#hr(u.eur / u.kwh * 100, d: 1) c][po kWh, sve uključeno],
)
#text(8.5pt, fill: ink2, p.sazetak)

#let mj = p.mjeseci
== Potrošnja po mjesecima (kWh)
#legenda((s1, [iz očitanja unutar mjeseca]), (srafura, [raspodijeljeno ravnomjerno (dugi razmak između očitanja ili procjena ODS-a)]))
#graf(mj.map(x => ((x.kwh, if x.raspodijeljeno { srafura } else { s1 }),)), mj.map(x => x.oznaka))

== Trošak po mjesecima (€ s PDV-om)
#legenda((s1, [energija (#p.opskrbljivac)]), (s2, [mrežarina + naknada za OIE]), (s3, [fiksno (opskrba + mjerno mjesto)]))
#graf(mj.map(x => ((x.fiksno, s3), (x.mreza, s2), (x.energija, s1))), mj.map(x => x.oznaka))

#pagebreak()

// ---------------------------------------------------------------- ručna očitanja (ako ih ima)

#if p.rucno != none {
  let r = p.rucno
  [== Ručna očitanja: #r.od – #r.do]
  text(8.5pt, fill: ink2)[Prosječna potrošnja po danu između dva očitanja (kWh/dan). Ukupno #hr(r.kwh, d: 1) kWh u #hr(r.dana, d: 1) dana; isprekidana linija je prosjek #hr(r.po_danu, d: 1) kWh/dan.]
  graf(r.intervali.map(i => ((i.po_danu, s1),)), r.intervali.map(i => i.oznaka), fmt: jedan, visina: 5cm,
    prosjek: r.po_danu, podoznake: r.intervali.map(i => i.dani + " · " + hr(i.kwh, d: 1) + " kWh"))
  grid(columns: (1fr,) * 3, column-gutter: 8pt,
    kartica[#hr(r.po_danu, d: 1) kWh][prosječno dnevno (ljeto srp–ruj oko #hr(r.ljeto_po_danu, d: 1))],
    kartica[#hr(r.mj30, d: 2) €][30 dana uz ovu potrošnju, ukupno na računu],
    kartica[#hr(r.kwh, d: 1) kWh][potrošeno u #hr(r.dana, d: 1) dana],
  )
}

// ---------------------------------------------------------------- tablica i metoda

== Tablica po mjesecima
#table(
  columns: (1.4fr, 1fr, 1fr, 1fr, 1fr, 1fr), align: (left, right, right, right, right, right),
  stroke: (_, y) => (bottom: 0.5pt + crta), inset: (x: 5pt, y: 3.2pt),
  table.header(..([Mjesec], [kWh], [Energija €], [Mreža + OIE €], [Fiksno €], [Ukupno €]).map(t => text(fill: ink2, weight: "semibold", t))),
  ..mj.map(x => (x.mjesec, hr(x.kwh) + if x.raspodijeljeno { " *" } else { "" }, hr(x.energija, d: 2),
    hr(x.mreza, d: 2), hr(x.fiksno, d: 2), strong(hr(x.ukupno, d: 2)))).flatten(),
  table.hline(stroke: 1pt),
  ..([Ukupno], hr(u.kwh), hr(u.energija, d: 2), hr(u.mreza, d: 2), hr(u.fiksno, d: 2), hr(u.eur, d: 2)).map(strong),
)
#text(8pt, fill: ink2)[\* mjesec unutar dugog razmaka između očitanja ili uz procjenu ODS-a; kWh su raspodijeljeni ravnomjerno po danima.#if p.dvotarifno [ kWh = VT (T1) + NT (T2).]]

#grid(columns: (1.1fr, 1fr), column-gutter: 16pt,
  [
    == Kako je izračunato
    #set text(8.5pt)
    #set list(spacing: 0.55em)
    #list(..p.biljeske)
  ],
  [
    == Očitanja
    #set text(8pt)
    #table(
      columns: if p.dvotarifno { (auto, auto, auto, 1fr) } else { (auto, auto, 1fr) },
      align: if p.dvotarifno { (left, right, right, left) } else { (left, right, left) },
      stroke: (_, y) => (bottom: 0.5pt + crta), inset: (x: 4pt, y: 3pt),
      table.header(..(([Datum], [T1]) + if p.dvotarifno { ([T2],) } else { () } + ([Vrsta],)).map(t => text(fill: ink2, weight: "semibold", t))),
      ..p.ocitanja.map(o => (o.datum, jedan(o.t1)) + if p.dvotarifno { (jedan(o.t2),) } else { () } + (o.opis,)).flatten(),
    )
    #v(8pt)
    #block(width: 100%, stroke: 1.2pt + marka, radius: 8pt, inset: 8pt, breakable: false, grid(
      columns: (auto, 1fr), column-gutter: 10pt, align: horizon,
      qrcode(p.url, width: 1.4cm, options: (fg-color: marka)),
      text(8pt, fill: ink2)[#text(fill: marka, weight: "bold")[DOMOVINA Energy] · izrađeno na omm.domovina.ai, #p.izradeno \
        Prijaviš se sam na HEP-ov portal, a mi samo pročitamo očitanja i potrošnju. Bez OIB-a, bez lozinki. Skeniraj kod i napravi izvještaj za svoje brojilo.],
    ))
  ],
)

