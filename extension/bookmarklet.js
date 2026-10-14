// Bookmarklet „Uvezi iz HEP-a“: isti uvoz kao extension, bez instalacije.
//
// Oznaka u pregledniku ubacuje <script src="https://omm.domovina.ai/hep-uvoz.js?k=<ključ>">
// u prijavljenu karticu Moje mreže ili Mojeg računa. Ta datoteka je spoj
// uvoz.js + mojracun.js + ove datoteke (tools/bookmarklet.mjs), pa se kod
// izvršava na HEP-ovoj domeni: fetch je same-origin s cookiejima sesije, kao u
// extensionu. Na omm.domovina.ai odlazi samo gotov JSON, i to tek na klik.
//
// Zašto radi: nijedan portal nema CSP koji ograničava script-src ili
// connect-src (provjereno 2026-10-14), a /api/snimak ima CORS *. Ako se to
// promijeni, rezerva je nova kartica omm.domovina.ai/uvoz i postMessage.

(() => {
  const skripta = document.currentScript;
  const adresa = new URL(skripta ? skripta.src : 'https://omm.domovina.ai/hep-uvoz.js');
  const SERVER = adresa.origin;
  const KLJUC = adresa.searchParams.get('k');

  const IZVORI = {
    'https://mojamreza.hep.hr': { ime: 'Moja mreža (HEP ODS)', funkcija: 'mojaMrezaUvoz', ommIzvor: 'hep', datoteka: 'moja-mreza' },
    'https://mojracun.hep.hr': { ime: 'Moj račun (HEP Elektra)', funkcija: 'mojRacunUvoz', ommIzvor: 'hep-moj-racun', datoteka: 'moj-racun' },
  };
  const PORUKE = {
    sesijaIstekla: 'Nisi prijavljen. Prijavi se na ovoj stranici pa klikni oznaku ponovno.',
    neocekivanHtml: 'Stranica ne izgleda kako uvoz očekuje (HEP ju je možda promijenio).',
    neocekivanOdgovor: 'Odgovor Mojeg računa ne izgleda kako uvoz očekuje (HEP ga je možda promijenio).',
    nemaKupca: 'Ne vidim kupca. Otvori Potrošnju ili Promet u Mojem računu pa klikni oznaku ponovno.',
    mreza: 'Mreža ili preglednik javili su grešku.',
  };

  // Drugi klik na oznaku samo vrati postojeći prozorčić.
  const postojeci = document.getElementById('omm-domovina-uvoz');
  if (postojeci) {
    postojeci.style.display = '';
    return;
  }

  const domacin = document.createElement('div');
  domacin.id = 'omm-domovina-uvoz';
  domacin.style.cssText = 'position:fixed;top:16px;right:16px;z-index:2147483647;';
  // Shadow DOM: HEP-ov CSS ne dira prozorčić i obrnuto.
  const korijen = domacin.attachShadow({ mode: 'closed' });
  korijen.innerHTML = `
    <style>
      :host { all: initial; }
      .p { width: min(360px, calc(100vw - 32px)); box-sizing: border-box; background: #fff; color: #1b1f1a;
        border: 1px solid #dfe3db; border-radius: 14px; padding: 16px; box-shadow: 0 8px 32px rgba(0,0,0,.18);
        font: 14px/1.45 system-ui, -apple-system, "Segoe UI", sans-serif; }
      h2 { font-size: 16px; margin: 0 0 4px; } p, ul { margin: 8px 0; } ul { padding-left: 18px; }
      .blijedo { color: #5d665b; font-size: 13px; }
      button { display: block; width: 100%; min-height: 40px; margin-top: 8px; border: 0; border-radius: 10px;
        font: inherit; font-weight: 600; cursor: pointer; background: #1f7a3a; color: #fff; }
      button.sporedni { background: transparent; color: #1b1f1a; border: 1px solid #dfe3db; }
      button:disabled { opacity: .5; cursor: default; }
      .x { position: absolute; top: 8px; right: 8px; width: 28px; min-height: 28px; margin: 0; padding: 0;
        background: transparent; color: #5d665b; font-size: 18px; }
      .greska { color: #b3261e; } a { color: #1f7a3a; }
      [hidden] { display: none !important; }
    </style>
    <div class="p" style="position:relative">
      <button class="x" id="zatvori" title="Zatvori">×</button>
      <h2>Uvoz na omm.domovina.ai</h2>
      <div id="sadrzaj"></div>
      <p id="status" class="blijedo" hidden></p>
    </div>`;
  document.body.append(domacin);
  const $ = (id) => korijen.getElementById(id);
  $('zatvori').onclick = () => { domacin.style.display = 'none'; };

  const status = (tekst, greska = false) => {
    $('status').hidden = !tekst;
    $('status').textContent = tekst || '';
    $('status').className = greska ? 'greska' : 'blijedo';
  };
  const gumb = (tekst, klik, sporedni = false) => {
    const b = document.createElement('button');
    b.textContent = tekst;
    if (sporedni) b.className = 'sporedni';
    b.onclick = klik;
    return b;
  };
  const odlomak = (html, klasa) => {
    const p = document.createElement('p');
    p.innerHTML = html;
    if (klasa) p.className = klasa;
    return p;
  };

  const izvor = IZVORI[location.origin];
  const sadrzaj = $('sadrzaj');

  if (!KLJUC || !/^[A-Za-z0-9_-]{22,64}$/.test(KLJUC)) {
    sadrzaj.append(odlomak(`Oznaka nema ključ. Napravi je ponovno na <a href="${SERVER}/uvoz" target="_blank">${SERVER.replace('https://', '')}/uvoz</a>.`, 'greska'));
    return;
  }
  if (!izvor) {
    sadrzaj.append(
      odlomak('Ova oznaka radi samo na HEP-ovim portalima. Otvori jedan, prijavi se i klikni je ponovno.'),
      gumb('Otvori Moju mrežu (HEP ODS)', () => { location.href = 'https://mojamreza.hep.hr/'; }),
      gumb('Otvori Moj račun (HEP Elektra)', () => { location.href = 'https://mojracun.hep.hr/elektra/'; }, true),
    );
    return;
  }

  const ul = document.createElement('ul');
  ul.innerHTML = location.origin === 'https://mojamreza.hep.hr'
    ? '<li>mjerna mjesta (OMM, adresa, tarifa)</li><li>očitanja brojila</li><li>potrošnju po razdobljima</li>'
    : '<li>kupca (OMM, adresa)</li><li>očitanja i potrošnju</li><li>promet (računi i uplate)</li>';
  sadrzaj.append(
    odlomak(`<b>${izvor.ime}</b>: pročitat ćemo iz ove prijavljene sesije`),
    ul,
    odlomak('i poslati na omm.domovina.ai. Ne čitamo OIB, lozinku ni kolačiće; prijava ostaje u ovom pregledniku.', 'blijedo'),
  );
  const uvezi = gumb('Uvezi', pokreni);
  sadrzaj.append(uvezi);

  // OMM snimka kad uvoz ima točno jedno mjesto (Moja mreža) ili kupca (Moj račun).
  const jediniOmm = (u) => {
    const lista = u.mjesta || u.kupci || [];
    return lista.length === 1 ? lista[0].omm || null : null;
  };

  const sazetak = (u) =>
    (u.mjesta || u.kupci || []).map((m) =>
      `${m.omm || `kupac ${m.kupac_id}`}: ${m.ocitanja.length} očitanja, ${m.potrosnja.length} razdoblja potrošnje` +
      (m.promet ? `, ${m.promet.length} stavki prometa` : ''));

  const tijelo = (u) => ({ izvor: izvor.ommIzvor, omm: jediniOmm(u), uvoz: u, lokacija: null });

  async function pokreni() {
    uvezi.disabled = true;
    status('Pokrećem…');
    let uvoz;
    try {
      uvoz = await globalThis[izvor.funkcija]({ napredak: status });
    } catch (e) {
      status(`${PORUKE[e.greska] || PORUKE.mreza} (${e.message || e})`, true);
      uvezi.disabled = false;
      uvezi.textContent = 'Pokušaj ponovno';
      return;
    }
    uvezi.remove();
    const lista = document.createElement('ul');
    for (const s of sazetak(uvoz)) {
      const li = document.createElement('li');
      li.textContent = s;
      lista.append(li);
    }
    if (!lista.children.length) lista.innerHTML = '<li>Nema mjernih mjesta na ovom računu.</li>';
    sadrzaj.append(lista);
    await posalji(uvoz);
  }

  async function posalji(uvoz) {
    status('Šaljem na omm.domovina.ai…');
    try {
      const o = await fetch(`${SERVER}/api/snimak`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${KLJUC}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(tijelo(uvoz)),
        credentials: 'omit',
      });
      const j = await o.json().catch(() => ({}));
      if (o.status !== 200 && o.status !== 201) throw new Error(j.greska || `HTTP ${o.status}`);
      gotovo(j.duplikat ? 'Isti uvoz je već bio na omm.domovina.ai ✓' : 'Spremljeno na omm.domovina.ai ✓');
    } catch (e) {
      status(`Izravno slanje nije uspjelo (${e.message || e}).`, true);
      rezerva(uvoz);
    }
  }

  function gotovo(poruka) {
    status('');
    sadrzaj.append(
      odlomak(`<b>${poruka}</b>`),
      gumb('Otvori omm.domovina.ai', () => window.open(`${SERVER}/uvoz`, '_blank')),
    );
  }

  // Ako HEP jednom uvede CSP ili WAF koji priječi fetch prema nama: nova
  // kartica omm.domovina.ai/uvoz javi „spreman“, dobije JSON preko
  // postMessage (provjerava event.origin) i sama ga spremi.
  function rezerva(uvoz) {
    sadrzaj.append(
      gumb('Pošalji preko nove kartice', () => {
        const prozor = window.open(`${SERVER}/uvoz?primi=1`, '_blank');
        if (!prozor) return status('Preglednik je blokirao novu karticu.', true);
        const slusaj = (e) => {
          if (e.origin !== SERVER || e.source !== prozor || !e.data || e.data.omm !== 'spreman') return;
          window.removeEventListener('message', slusaj);
          prozor.postMessage({ omm: 'uvoz', tijelo: tijelo(uvoz) }, SERVER);
          gotovo('Poslano u novu karticu omm.domovina.ai');
        };
        window.addEventListener('message', slusaj);
      }),
      gumb('Preuzmi JSON', () => {
        const a = document.createElement('a');
        a.href = URL.createObjectURL(new Blob([JSON.stringify(uvoz, null, 2)], { type: 'application/json' }));
        a.download = `${izvor.datoteka}-${uvoz.dohvaceno.slice(0, 10)}.json`;
        a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      }, true),
    );
  }
})();
