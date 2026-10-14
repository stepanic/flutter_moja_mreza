# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build and Development
```bash
# Get dependencies
flutter pub get

# Run the example app
cd example && flutter run

# Analyze code
flutter analyze

# Run tests
flutter test

# Run integration tests
cd example && flutter test integration_test/plugin_integration_test.dart

# Format code
dart format .

# Build for specific platforms
cd example
flutter build apk          # Android
flutter build ios          # iOS (requires macOS)
flutter build web          # Web
```

### Plugin Development
```bash
# Build plugin for all platforms
flutter build-examples

# Clean build artifacts
flutter clean

# Upgrade dependencies
flutter pub upgrade
```

## Architecture

Flutter plugin whose public API is `FlutterMojaMreza.uvezi(context)`: Certilia/NIAS
login to mojamreza.hep.hr, then import of all OMMs with readings and consumption
(`HepUvoz`). `FlutterMojaMreza.dostavi(context, t1:, t2:)` submits a meter
reading (`GET /DostavaOcitanja` → `POST /Omm/Dostava`), refusing values outside
the portal's expected range unless `svejedno: true`. Details and the trust model: `docs/2026-10-05-uvoz-arhitektura-i-povjerenje.md`.

- **Platform = authenticated HTTP transport only** (`lib/flutter_moja_mreza_platform_interface.dart`):
  `prijava({portal})` (`HepPortal.mojaMreza` | `mojRacun`), `dohvati(putanja, {forma})`
  (GET inside the session, or form POST when `forma` is given; returns
  url/status/html), `stanje()` (current page url/html/Resource Timing URLs),
  `napredak`, `zatvori`, `odjava`. Per-portal config (start URL, login check,
  allowlist) is `HepPortal` in both native files. Ordering and parsing live in Dart.
- **iOS (native)**: `ios/Classes/MojaMrezaSesija.swift` — SwiftUI sheet + WKWebView,
  `callAsyncJavaScript` fetch; bridged by `lib/flutter_moja_mreza_method_channel.dart`.
  Minimum iOS 15.
- **Android (native)**: `android/src/main/kotlin/.../MojaMrezaSesija.kt` — full-screen
  Dialog + android.webkit.WebView, fetch result via `addWebMessageListener` limited to
  the open portal's origin. Tested end to end on an emulator (2026-10-05).
- **Trust measures (both)**: ephemeral storage wiped on `zatvori()` (login on every
  import), main-frame domain allowlist per portal, JS only on the portal's origin.
- **Web**: unsupported (CORS), throws `MojaMrezaGreska.nepodrzano`.
- **Desktop**: Chrome MV3 extension in `extension/` (`uvoz.js` is a JS port of the
  parser, same JSON as `HepUvoz.toJson()`; `npm test` there uses the same fixtures).
  Keep both parsers in sync. Details: `docs/2026-10-05-desktop-extension.md`.
- **No-install web import**: `extension/bookmarklet.js` + both parsers are bundled by
  `npm run bookmarklet` (in `extension/`) into `omm.domovina.ai/public/hep-uvoz.js`;
  the bookmarklet on omm.domovina.ai/uvoz injects it into the logged-in portal tab. HEP bills
  forwarded by mail to `racuni+<key>@omm.domovina.ai` are parsed in that Worker. Rebuild and
  deploy omm.domovina.ai after any parser change. Details: `docs/2026-10-14-uvoz-bez-instalacije.md`.
- **Moj račun (HEP Elektra)**: mojracun.hep.hr/elektra is an Angular SPA with a
  JSON API (`/elektra/v1/api/…`, password login). Parser: `lib/src/moj_racun.dart`
  (`MojRacunParser`, `MojRacunUvoz`) and `extension/mojracun.js`, fixtures in
  `test/fixtures/mojracun/`. Imported by the extension and by
  `FlutterMojaMreza.uveziMojRacun` (example app: card „Uvezi s Mojeg računa“). Routes and
  the kupacId trick: `docs/hep-moj-racun-recept.md`.
- **Reports**: `tools/izvjestaj/izvjestaj.py data/omm/<omm>.yaml [--anonimno] [--html]`
  computes the yearly report and writes `<report>.json`; Typst (`izvjestaj.typ`, QR via
  `@preview/tiaoma`) lays out the branded PDF, `--html` uses `predlozak.html.j2` + headless
  Chrome instead (web version). One YAML profile per OMM in gitignored `data/omm/` adds what
  the portals lack (naziv, faza, snaga, lokacija, ručna očitanja, napomene); prices come from
  the public Moj račun cjenik. Method and Typst-vs-HTML: `docs/2026-10-13-izvjestaj-potrosnje.md`.
- **Transparency**: `docs/kako-citamo-podatke.md` lists every request the import
  makes and what it reads. Update it whenever a route, field or permission changes.
- **Parser**: `lib/src/parser.dart` (`package:html`), columns found by `thead` name;
  the first cell of a row is often `<th scope="row">`. Fixtures in `test/fixtures/`
  are real anonymised rows.
- **omm.domovina.ai** (repo `~/git/domovinatv/omm.domovina.ai`, Astro on Workers):
  the example app's "Očitaj brojilo" screen sends a meter photo there for OCR
  (1.8.1/1.8.2), saves snapshots (reading, photo, location, HEP import). No auth
  yet: random device key. Plan: `docs/2026-10-12-omm-domovina-ai-plan.md`.
- **Example app** (`example/`) is branded **Domovina Energy**: tokens from
  energy.domovina.ai (`example/lib/tema.dart`, `Boje`), logo from
  `~/git/domovinatv/mediakit.domovina.tv`, Inter + Fraunces bundled (no google_fonts).
  `podaci.dart` merges any number of Moja mreža and Moj račun accounts by OMM
  (`spojiMjesta`) from their `toJson()`; the last import per account (`Racun`,
  identified by the OMMs/kupci it sees) is kept in SharedPreferences (`Spremiste`).
  Decisions and traps: `docs/2026-10-13-domovina-energy-dizajn.md`.
  Bundle ID `com.stepanic.mojamreza`, team ITalk
  (6SCK58757K). In debug it dumps raw HTML to the app's tmp dir (`MOJA_MREZA_HTML`
  in the log). OTA install to iPhone over Tailscale: `tools/ios_ota.sh`.

## Moja mreža endpoints

Routes, HTML selectors, the `POST /Omm/Dostava` meter-reading format and a JS
snippet are in `docs/hep-moja-mreza-recept.md`. HEP ODS has no OAuth/API for
third parties (checked 2026-10-05). Data pulled from the portal goes to
`data/` (gitignored: contains OIB).