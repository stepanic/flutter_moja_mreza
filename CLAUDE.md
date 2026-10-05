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
(`HepUvoz`). Details and the trust model: `docs/2026-10-05-uvoz-arhitektura-i-povjerenje.md`.

- **Platform = authenticated HTTP transport only** (`lib/flutter_moja_mreza_platform_interface.dart`):
  `prijava`, `dohvati(putanja)` (GET inside the session, returns url/status/html),
  `napredak`, `zatvori`, `odjava`. Ordering and parsing live in Dart.
- **iOS (native)**: `ios/Classes/MojaMrezaSesija.swift` — SwiftUI sheet + WKWebView,
  `callAsyncJavaScript` fetch; bridged by `lib/flutter_moja_mreza_method_channel.dart`.
  Minimum iOS 15.
- **Android (native)**: `android/src/main/kotlin/.../MojaMrezaSesija.kt` — full-screen
  Dialog + android.webkit.WebView, fetch result via `addWebMessageListener` limited to
  the mojamreza.hep.hr origin. Tested end to end on an emulator (2026-10-05).
- **Trust measures (both)**: ephemeral storage wiped on `zatvori()` (login on every
  import), main-frame domain allowlist, JS only on mojamreza.hep.hr.
- **Web**: unsupported (CORS), throws `MojaMrezaGreska.nepodrzano`.
- **Desktop**: Chrome MV3 extension in `extension/` (`uvoz.js` is a JS port of the
  parser, same JSON as `HepUvoz.toJson()`; `npm test` there uses the same fixtures).
  Keep both parsers in sync. Details: `docs/2026-10-05-desktop-extension.md`.
- **Parser**: `lib/src/parser.dart` (`package:html`), columns found by `thead` name;
  the first cell of a row is often `<th scope="row">`. Fixtures in `test/fixtures/`
  are real anonymised rows.
- **Example app** (`example/`): bundle ID `com.stepanic.mojamreza`, team ITalk
  (6SCK58757K). In debug it dumps raw HTML to the app's tmp dir (`MOJA_MREZA_HTML`
  in the log). OTA install to iPhone over Tailscale: `tools/ios_ota.sh`.

## Moja mreža endpoints

Routes, HTML selectors, the `POST /Omm/Dostava` meter-reading format and a JS
snippet are in `docs/hep-moja-mreza-recept.md`. HEP ODS has no OAuth/API for
third parties (checked 2026-10-05). Data pulled from the portal goes to
`data/` (gitignored: contains OIB).