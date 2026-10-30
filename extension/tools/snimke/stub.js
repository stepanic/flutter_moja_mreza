// Lažni chrome.* za snimke zaslona za Web Store (tools/snimke/okvir.html).
// Podaci su izmišljeni; nijedan pravi OMM ni adresa.
(() => {
  const s = new URLSearchParams(parent.location.search).get('stanje') || 'mreza';
  const url = { mreza: 'https://mojamreza.hep.hr/', hepi: 'https://mojracun.hep.hr/hepi/#!/racuni', racun: 'https://mojracun.hep.hr/elektra/', drugo: 'https://example.com/' }[s.split('-')[0]];
  const izvor = { mreza: 'mreza', hepi: 'hepi', racun: 'racun' }[s.split('-')[0]];
  const mjesto = { omm: '0100012345', adresa: 'Ulica primjera 12, Zagreb', ocitanja: Array(14), potrosnja: Array(24) };
  const posao = !s.endsWith('-gotovo') ? null : {
    tabId: 1, izvor, faza: 'gotovo', status: '',
    uvoz: izvor === 'mreza' ? { mjesta: [mjesto], dohvaceno: '2026-10-30T17:25:20Z' }
      : { kupci: [{ ...mjesto, racuni: Array(20), promet: Array(41) }], dohvaceno: '2026-10-30T17:21:38Z' },
    poslano: 'novo',
    racuni: izvor === 'hepi' ? { novi: 3, procitano: 3 } : null,
  };
  window.chrome = {
    tabs: { query: async () => [{ id: 1, url }], create: async () => {} },
    runtime: { sendMessage: () => {} },
    storage: {
      local: { get: async () => ({ kljuc: 'primjer' }) },
      session: { get: async () => ({ posao }) },
      onChanged: { addListener: () => {} },
    },
  };
})();
