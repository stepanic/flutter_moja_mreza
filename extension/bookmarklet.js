// Bookmarklet „Uvezi iz HEP-a“: isti uvoz kao extension, bez instalacije.
//
// Oznaka u pregledniku ubacuje <script src="https://omm.domovina.ai/hep-uvoz.js?v=…#k=<ključ>">
// u prijavljenu karticu Moje mreže, Mojeg računa (Elektra) ili Mojeg Hepi
// računa. Ta datoteka je spoj uvoz.js + mojracun.js + hepi.js + ove datoteke
// (tools/bookmarklet.mjs), pa se kod
// izvršava na HEP-ovoj domeni: fetch je same-origin s cookiejima sesije, kao u
// extensionu. Na omm.domovina.ai odlazi samo gotov JSON, i to tek na klik.
//
// Prikaz je fiksni desni stupac (shadow DOM) u izgledu omm.domovina.ai (znak B):
// prvo kaže što čita, što šalje i što ne dira, nakon čitanja pokaže sažetak i
// cijeli JSON, a šalje tek na drugi klik.
//
// Zašto radi: nijedan portal nema CSP koji ograničava script-src ili
// connect-src (provjereno 2026-10-14), a /api/snimak ima CORS *. Ako se to
// promijeni, rezerva je nova kartica omm.domovina.ai/?primi=1 i postMessage.

(() => {
  const skripta = document.currentScript;
  const adresa = new URL(skripta ? skripta.src : 'https://omm.domovina.ai/hep-uvoz.js');
  const SERVER = adresa.origin;
  const HOST = SERVER.replace('https://', '');
  // Ključ je u fragmentu (#k=), koji se ne šalje serveru ni u logove; ?k= je za
  // oznake napravljene prije 2026-10-17.
  const KLJUC = new URLSearchParams(adresa.hash.slice(1)).get('k') ?? adresa.searchParams.get('k');

  // Elektra i Hepi dijele origin mojracun.hep.hr, pa se razlikuju po putanji.
  // `zahtjevi` su točno oni koje uvoz šalje portalu (docs/kako-citamo-podatke.md).
  const IZVORI = [
    { adresa: 'https://mojamreza.hep.hr/', ime: 'Moja mreža (HEP ODS)', funkcija: 'mojaMrezaUvoz', ommIzvor: 'hep', datoteka: 'moja-mreza',
      cita: ['mjerna mjesta: broj OMM-a i brojila, adresa, tarifni model', 'očitanja brojila: datum, T1 i T2 u kWh', 'potrošnju po obračunskim razdobljima'],
      zahtjevi: ['GET /Postavke', 'GET /Ocitanja?omm=…', 'GET /Potrosnja?omm=…'] },
    { adresa: 'https://mojracun.hep.hr/elektra', ime: 'Moj račun (HEP Elektra)', funkcija: 'mojRacunUvoz', ommIzvor: 'hep-moj-racun', datoteka: 'moj-racun',
      cita: ['kupca iz zaglavlja stranice: ime, ugovorni račun, OMM, adresa', 'očitanja i potrošnju po razdobljima', 'promet: račune, uplate i saldo'],
      zahtjevi: ['GET /elektra/v1/api/ocitanja/{kupac}', 'GET /elektra/v1/api/potrosnja/{kupac}', 'GET /elektra/v1/api/promet/{kupac}'] },
    { adresa: 'https://mojracun.hep.hr/hepi', ime: 'Moj Hepi račun (HEP Opskrba)', funkcija: 'hepiUvoz', ommIzvor: 'hep-hepi', datoteka: 'hepi',
      cita: ['kupca: OMM, adresa, tarifni model', 'saldo, račune i uplate', 'potrošnju i očitanja', 'PDF-ove računa koje omm.domovina.ai još nema'],
      zahtjevi: ['GET /hepi/api/kupci', 'GET /hepi/api/promet/{kupac}', 'GET /hepi/api/potrosnja/{kupac}', 'POST /hepi/api/report/racun (PDF računa, kao gumb Ispis)'],
      racuni: true },
  ];
  const PORUKE = {
    sesijaIstekla: 'Nisi prijavljen. Prijavi se na ovoj stranici pa klikni oznaku ponovno.',
    neocekivanHtml: 'Stranica ne izgleda kako uvoz očekuje (HEP ju je možda promijenio).',
    neocekivanOdgovor: 'Odgovor Mojeg računa ne izgleda kako uvoz očekuje (HEP ga je možda promijenio).',
    nemaKupca: 'Ne vidim kupca. Otvori Potrošnju ili Promet u Mojem računu pa klikni oznaku ponovno.',
    mreza: 'Mreža ili preglednik javili su grešku.',
  };

  // Klik na oznaku na samom omm.domovina.ai je provjera da je oznaka u traci:
  // naslovnica sluša ovaj događaj, potvrdi i zapamti. Stupac se ne otvara.
  if (location.origin === SERVER) {
    window.dispatchEvent(new CustomEvent('omm-oznaka', { detail: { kljuc: KLJUC } }));
    return;
  }

  // Na širokom zaslonu stupac odmakne stranicu ulijevo (margin na <html>), pa
  // ne prekriva portal; na uskom leži preko nje. Fiksna zaglavlja portala se
  // ne pomiču, ali HEP-ovi portali ih nemaju desno.
  const SIRINA = 400;
  const odmakni = (da) => {
    const h = document.documentElement.style;
    if (da && innerWidth >= SIRINA + 640) h.setProperty('margin-right', `${SIRINA}px`, 'important');
    else h.removeProperty('margin-right');
  };

  // Drugi klik na oznaku samo vrati postojeći stupac.
  const postojeci = document.getElementById('omm-domovina-uvoz');
  if (postojeci) {
    postojeci.style.display = '';
    odmakni(true);
    return;
  }

  const domacin = document.createElement('div');
  domacin.id = 'omm-domovina-uvoz';
  domacin.style.cssText = 'position:fixed;top:0;right:0;bottom:0;z-index:2147483647;';
  // Shadow DOM: HEP-ov CSS ne dira stupac i obrnuto.
  const korijen = domacin.attachShadow({ mode: 'closed' });
  // Tokeni i znak (pločica B) su s omm.domovina.ai (src/components/Tema.astro,
  // public/logo.svg i logo-noc.svg). Tema prati sustav: prekidač s našeg
  // origina ovdje ne vidimo.
  korijen.innerHTML = `
    <style>
      :host { all: initial; }
      .s { --bg: #f5f7fb; --kartica: #fff; --tekst: #0e1a2e; --blijedo: #55617a; --rub: #dde3ee;
        --akcent: #002F6C; --akcent-tekst: #fff; --akcent-blago: #e6ecf5; --greska: #b3261e; --greska-bg: #fdf2f2;
        --uspjeh: #196931; --uspjeh-bg: #eaf6ee; --plocica: #002F6C; --prsten: #fff;
        width: min(${SIRINA}px, 100vw); height: 100%; box-sizing: border-box; display: flex; flex-direction: column;
        background: var(--bg); color: var(--tekst); border-left: 1px solid var(--rub); box-shadow: -8px 0 32px rgba(0,0,0,.14);
        font: 14px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; color-scheme: light; }
      @media (prefers-color-scheme: dark) {
        .s { --bg: #001a3d; --kartica: #002452; --tekst: #eef2f8; --blijedo: #9fb0c9; --rub: #1d3a66;
          --akcent: #E3AF35; --akcent-tekst: #001a3d; --akcent-blago: #0d2d58; --greska: #ff8a80; --greska-bg: #321616;
          --uspjeh: #6dd489; --uspjeh-bg: #12281a; --plocica: #fff; --prsten: #002F6C; color-scheme: dark; }
      }
      * { box-sizing: border-box; }
      header { display: flex; align-items: center; gap: 10px; padding: 14px 16px; border-bottom: 1px solid var(--rub); background: var(--kartica); }
      header svg { width: 32px; height: 32px; flex: none; }
      .marka { flex: 1; font-size: 15px; letter-spacing: .02em; }
      .marka b { font-weight: 800; } .marka span { color: var(--blijedo); font-weight: 500; }
      .tijelo { position: relative; flex: 1; overflow-y: auto; padding: 16px; }
      .podnozje { padding: 12px 16px 16px; border-top: 1px solid var(--rub); background: var(--kartica); }
      h2 { font-size: 17px; line-height: 1.3; margin: 0 0 4px; }
      h3 { font-size: 12px; font-weight: 700; letter-spacing: .06em; text-transform: uppercase; color: var(--blijedo); margin: 0 0 6px; }
      p, ul { margin: 8px 0; } ul { padding-left: 18px; } li { margin: 2px 0; }
      .kartica { background: var(--kartica); border: 1px solid var(--rub); border-radius: 12px; padding: 12px 14px; margin: 12px 0; }
      .kartica > :last-child { margin-bottom: 0; }
      .blijedo { color: var(--blijedo); font-size: 13px; }
      code, pre { font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace; }
      .zahtjevi { list-style: none; padding: 0; margin: 8px 0 0; }
      .zahtjevi li { padding: 3px 8px; margin: 3px 0; background: var(--akcent-blago); border-radius: 6px; overflow-wrap: anywhere; }
      .ne li::marker { content: "✕  "; color: var(--blijedo); }
      details { margin-top: 10px; } summary { cursor: pointer; font-weight: 600; color: var(--akcent); }
      pre { max-height: 320px; overflow: auto; margin: 8px 0 0; padding: 10px; background: var(--akcent-blago); border-radius: 8px; white-space: pre; }
      button { display: block; width: 100%; min-height: 44px; margin-top: 8px; padding: 0 14px; border: 0; border-radius: 10px;
        font: inherit; font-weight: 600; cursor: pointer; background: var(--akcent); color: var(--akcent-tekst); }
      button:first-child { margin-top: 0; }
      button.sporedni { background: transparent; color: var(--tekst); border: 1px solid var(--rub); }
      button:disabled { opacity: .5; cursor: default; }
      button.x { width: 32px; min-height: 32px; margin: 0; padding: 0; background: transparent; color: var(--blijedo); font-size: 22px; line-height: 1; }
      .status { margin: 0 0 10px; font-size: 13px; color: var(--blijedo); }
      .greska { color: var(--greska); } .greska.kartica { background: var(--greska-bg); border-color: transparent; }
      .uspjeh { background: var(--uspjeh-bg); color: var(--uspjeh); border-color: transparent; }
      .uspjeh b { display: block; } .uspjeh span { display: block; margin-top: 4px; font-size: 13px; color: var(--tekst); }
      a { color: var(--akcent); }
      [hidden] { display: none !important; }
    </style>
    <aside class="s" role="complementary" aria-label="Uvoz na ${HOST}">
      <header>
        <svg viewBox="0 0 32 32" aria-hidden="true">
          <rect width="32" height="32" rx="8" fill="var(--plocica)"/>
          <path d="M6 16A10 10 0 1 0 26 16A10 10 0 1 0 6 16ZM9 16A7 7 0 1 1 23 16A7 7 0 1 1 9 16Z" fill="var(--prsten)" fill-rule="evenodd"/>
          <path d="M17.94 10.53 L12.76 15.71 L15.64 15.71 L14.06 21.47 L19.24 16.29 L16.36 16.29Z" fill="#E3AF35"/>
        </svg>
        <div class="marka"><b>OMM</b> <span>uvoz s HEP-a</span></div>
        <button class="x" id="zatvori" title="Zatvori" aria-label="Zatvori">×</button>
      </header>
      <div class="tijelo" id="sadrzaj"></div>
      <div class="podnozje" id="podnozje" hidden>
        <p id="status" class="status" hidden></p>
        <div id="gumbi"></div>
      </div>
    </aside>`;
  document.body.append(domacin);
  odmakni(true);
  const $ = (id) => korijen.getElementById(id);
  $('zatvori').onclick = () => {
    domacin.style.display = 'none';
    odmakni(false);
  };

  const status = (tekst, greska = false) => {
    $('status').hidden = !tekst;
    $('status').textContent = tekst || '';
    $('status').className = greska ? 'status greska' : 'status';
  };
  const gumb = (tekst, klik, sporedni = false) => {
    const b = document.createElement('button');
    b.textContent = tekst;
    if (sporedni) b.className = 'sporedni';
    b.onclick = klik;
    return b;
  };
  // Gumbi stoje u podnožju stupca, uvijek vidljivi; svaki korak ih zamijeni.
  const gumbi = (...lista) => {
    $('podnozje').hidden = false;
    $('gumbi').replaceChildren(...lista);
  };
  const el = (oznaka, html, klasa) => {
    const e = document.createElement(oznaka);
    if (html != null) e.innerHTML = html;
    if (klasa) e.className = klasa;
    return e;
  };
  const lista = (stavke, klasa) => {
    const ul = el('ul', null, klasa);
    for (const s of stavke) {
      const li = document.createElement('li');
      li.textContent = s;
      ul.append(li);
    }
    return ul;
  };
  const kartica = (naslov, ...djeca) => {
    const k = el('section', null, 'kartica');
    if (naslov) k.append(el('h3', naslov));
    k.append(...djeca);
    return k;
  };

  const izvor = IZVORI.find((i) => location.href.startsWith(i.adresa));
  const sadrzaj = $('sadrzaj');
  // Skrola se .tijelo, ne stranica: scrollIntoView iz zatvorenog shadow roota
  // pomicao je portal ili ništa. offsetTop je relativan na .tijelo (position: relative).
  const pokazi = (e) => requestAnimationFrame(() =>
    sadrzaj.scrollTo({ top: Math.max(0, e.offsetTop - 12), behavior: 'smooth' }));

  if (!KLJUC || !/^[A-Za-z0-9_-]{22,64}$/.test(KLJUC)) {
    sadrzaj.append(el('p', `Oznaka nema ključ. Napravi je ponovno na <a href="${SERVER}/" target="_blank">${HOST}</a>.`, 'greska kartica'));
    return;
  }
  if (!izvor) {
    sadrzaj.append(
      el('h2', 'Ovo nije HEP-ov portal'),
      el('p', 'Oznaka radi samo na HEP-ovim portalima. Otvori jedan, prijavi se i klikni oznaku ponovno.'),
    );
    gumbi(
      gumb('Otvori Moju mrežu (HEP ODS)', () => { location.href = 'https://mojamreza.hep.hr/'; }),
      gumb('Otvori Moj račun (HEP Elektra)', () => { location.href = 'https://mojracun.hep.hr/elektra/'; }, true),
      gumb('Otvori Moj Hepi račun (HEP Opskrba)', () => { location.href = 'https://mojracun.hep.hr/hepi/'; }, true),
    );
    return;
  }

  // Korak 1: prije ičega reći što će se dogoditi.
  sadrzaj.append(
    el('h2', `Uvoz s portala ${izvor.ime}`),
    el('p', `Ovaj stupac je dodala tvoja oznaka s <b>${HOST}</b>. Dok ne klikneš gumb dolje, nije pročitao ni poslao ništa.`, 'blijedo'),
    kartica('1. Što čitamo s ove stranice',
      el('p', 'Iz tvoje prijavljene sesije, isto što vidiš kad klikaš po portalu:'),
      lista(izvor.cita),
      el('p', 'Zahtjevi koje šaljemo portalu:', 'blijedo'),
      lista(izvor.zahtjevi, 'zahtjevi'),
    ),
    kartica('2. Što šaljemo na omm.domovina.ai',
      el('p', `Samo pročitane podatke kao JSON, na <code>${HOST}/api/snimak</code>. Prije slanja ih vidiš ovdje i tek onda klikneš <b>Pošalji</b>.`),
      ...(izvor.racuni
        ? [el('p', `PDF-ove računa šaljemo na <code>${HOST}/api/racun</code>: server iz njih pročita iznose i stavke, a PDF ne čuva.`)]
        : []),
      el('p', 'Uz podatke ide samo ključ ove oznake, po kojem ih poslije vidiš pod „Moji uvozi“. Ni ime ni mail ne trebaju.', 'blijedo'),
    ),
    kartica('3. Što ne diramo',
      lista([
        'OIB i lozinku',
        izvor.racuni ? 'token prijave: koristimo ga samo na ovoj stranici, ne šaljemo ga nikamo' : 'kolačiće i prijavu: ostaju u ovom pregledniku',
        'ništa ne mijenjamo na portalu: nema predaje očitanja ni promjene podataka',
      ], 'ne'),
    ),
    el('p', `Kod koji se upravo izvršava: <a href="${SERVER}/hep-uvoz.js" target="_blank" rel="noopener">${HOST}/hep-uvoz.js</a>. ` +
      'Popis svih zahtjeva: <a href="https://github.com/stepanic/flutter_moja_mreza/blob/main/docs/kako-citamo-podatke.md" target="_blank" rel="noopener">kako čitamo podatke</a>.', 'blijedo'),
  );
  const procitaj = gumb('Pročitaj podatke', pokreni);
  gumbi(procitaj);

  // OMM snimka kad uvoz ima točno jedno mjesto (Moja mreža) ili kupca (Moj račun).
  const jediniOmm = (u) => {
    const lista = u.mjesta || u.kupci || [];
    return lista.length === 1 ? lista[0].omm || null : null;
  };

  const sazetak = (u) =>
    (u.mjesta || u.kupci || []).map((m) =>
      `${m.omm || `kupac ${m.kupac_id}`}${m.adresa ? `, ${m.adresa}` : ''}: ${m.ocitanja.length} očitanja, ${m.potrosnja.length} razdoblja potrošnje` +
      (m.promet ? `, ${m.promet.length} stavki prometa` : '') +
      (m.racuni ? `, ${m.racuni.length} računa` : ''));

  const tijelo = (u) => ({ izvor: izvor.ommIzvor, omm: jediniOmm(u), uvoz: u, lokacija: null });

  // Korak 2: čitanje, pa pregled svega što bi otišlo.
  async function pokreni() {
    procitaj.disabled = true;
    status('Čitam…');
    let uvoz;
    try {
      uvoz = await globalThis[izvor.funkcija]({ napredak: status });
    } catch (e) {
      status(`${PORUKE[e.greska] || PORUKE.mreza} (${e.message || e})`, true);
      procitaj.disabled = false;
      procitaj.textContent = 'Pokušaj ponovno';
      return;
    }
    status('');
    const stavke = sazetak(uvoz);
    const json = el('pre');
    json.textContent = JSON.stringify(tijelo(uvoz), null, 2);
    const detalji = el('details');
    detalji.append(el('summary', `Pogledaj točno što šaljemo (${Math.max(1, Math.round(json.textContent.length / 1024))} kB JSON)`), json);
    const pregled = kartica('Pročitano, još ništa nije poslano',
      stavke.length ? lista(stavke) : el('p', 'Nema mjernih mjesta na ovom računu.'),
      el('p', izvor.racuni
        ? `Klikom na Pošalji ovo ide na ${HOST}, a zatim PDF-ovi računa koje ondje još nemamo.`
        : `Klikom na Pošalji ovo ide na ${HOST}.`, 'blijedo'),
      detalji,
    );
    sadrzaj.append(pregled);
    pokazi(pregled);
    gumbi(
      gumb(`Pošalji na ${HOST}`, () => posalji(uvoz)),
      gumb('Samo preuzmi JSON', () => preuzmi(uvoz), true),
    );
  }

  async function posalji(uvoz) {
    for (const b of $('gumbi').querySelectorAll('button')) b.disabled = true;
    status(`Šaljem na ${HOST}…`);
    try {
      const o = await fetch(`${SERVER}/api/snimak`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${KLJUC}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(tijelo(uvoz)),
        credentials: 'omit',
      });
      const j = await o.json().catch(() => ({}));
      if (o.status !== 200 && o.status !== 201) throw new Error(j.greska || `HTTP ${o.status}`);
      if (izvor.racuni) await posaljiRacune(uvoz);
      // Duplikat: server je po sadržaju prepoznao isti uvoz i vratio prvi (s `stvoren`).
      // To nije greška, nego „od zadnjeg puta na portalu nema ništa novo“.
      if (j.duplikat) {
        const kad = j.stvoren ? new Date(j.stvoren).toLocaleString('hr-HR', { day: 'numeric', month: 'numeric', year: 'numeric', hour: '2-digit', minute: '2-digit' }) : null;
        gotovo('Nema ništa novo ✓', `Ovi podaci su već na ${HOST}${kad ? ` (uvoz od ${kad})` : ''}, pa nismo spremili još jednu kopiju. Novi uvoz se sprema kad na portalu dođe novo očitanje, račun ili uplata.`);
      } else {
        gotovo(`Spremljeno na ${HOST} ✓`, 'Podatke vidiš pod „Moji uvozi“, a odande možeš preuzeti i izvještaj potrošnje.');
      }
    } catch (e) {
      status(`Izravno slanje nije uspjelo (${e.message || e}).`, true);
      rezerva(uvoz);
    }
  }

  // Hepi: PDF-ove računa koje server još nema šalje na /api/racun, gdje se
  // pročitaju (isti parser kao za račune mailom) i odbace. Server vraća popis
  // poziva na broj koje već ima, pa se ponovni uvoz svodi na nove račune.
  async function posaljiRacune(uvoz) {
    const auth = { Authorization: `Bearer ${KLJUC}` };
    let imamo = [];
    try {
      const o = await fetch(`${SERVER}/api/racun`, { headers: auth, credentials: 'omit' });
      if (o.ok) imamo = await o.json();
    } catch {}
    const novi = uvoz.kupci.flatMap((k) => k.racuni).filter((r) => r.link && r.poziv_na_broj && !imamo.includes(r.poziv_na_broj));
    let procitano = 0;
    for (const [i, r] of novi.entries()) {
      status(`Račun ${i + 1}/${novi.length}…`);
      try {
        const pdf = await globalThis.hepiRacunPdf(r.link);
        const o = await fetch(`${SERVER}/api/racun`, {
          method: 'POST', headers: { ...auth, 'Content-Type': 'application/pdf' }, body: pdf, credentials: 'omit',
        });
        if (o.ok) procitano++;
      } catch {}
    }
    if (novi.length) {
      sadrzaj.append(el('p', `Pročitano ${procitano} od ${novi.length} novih računa.`, procitano === novi.length ? 'blijedo' : 'greska'));
    }
  }

  function gotovo(naslov, opis) {
    status('');
    const k = el('p', null, 'kartica uspjeh');
    k.append(el('b'), el('span'));
    k.firstChild.textContent = naslov;
    if (opis) k.lastChild.textContent = opis;
    else k.lastChild.remove();
    sadrzaj.append(k);
    pokazi(k);
    gumbi(
      // #k= prenosi ključ oznake: kad je oznaka napravljena u drugom pregledniku
      // ili profilu, stranica ponudi da ga preuzme i pokaže uvoze.
      gumb(`Otvori ${HOST}`, () => window.open(`${SERVER}/#k=${encodeURIComponent(KLJUC)}`, '_blank')),
      gumb('Zatvori', () => $('zatvori').click(), true),
    );
  }

  function preuzmi(uvoz) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([JSON.stringify(uvoz, null, 2)], { type: 'application/json' }));
    a.download = `${izvor.datoteka}-${uvoz.dohvaceno.slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  // Ako HEP jednom uvede CSP ili WAF koji priječi fetch prema nama: nova
  // kartica omm.domovina.ai/?primi=1 javi „spreman“, dobije JSON preko
  // postMessage (provjerava event.origin) i sama ga spremi.
  function rezerva(uvoz) {
    gumbi(
      gumb('Pošalji preko nove kartice', () => {
        const prozor = window.open(`${SERVER}/?primi=1`, '_blank');
        if (!prozor) return status('Preglednik je blokirao novu karticu.', true);
        const slusaj = (e) => {
          if (e.origin !== SERVER || e.source !== prozor || !e.data || e.data.omm !== 'spreman') return;
          window.removeEventListener('message', slusaj);
          prozor.postMessage({ omm: 'uvoz', tijelo: tijelo(uvoz) }, SERVER);
          gotovo(`Poslano u novu karticu ${HOST}`, 'Ondje se uvoz sprema i pojavi pod „Moji uvozi“.');
        };
        window.addEventListener('message', slusaj);
      }),
      gumb('Preuzmi JSON', () => preuzmi(uvoz), true),
    );
  }
})();
