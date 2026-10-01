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

This is a Flutter plugin that provides platform-specific implementations for Android, iOS, and Web. The plugin follows the federated plugin architecture:

1. **Platform Interface** (`lib/flutter_moja_mreza_platform_interface.dart`): Abstract class defining the plugin API
2. **Method Channel** (`lib/flutter_moja_mreza_method_channel.dart`): Default implementation using platform channels
3. **Main API** (`lib/flutter_moja_mreza.dart`): Public API exposed to consumers
4. **Platform Implementations**:
   - Android: `android/src/main/kotlin/com/example/flutter_moja_mreza/FlutterMojaMrezaPlugin.kt`
   - iOS: `ios/Classes/FlutterMojaMrezaPlugin.swift`
   - Web: `lib/flutter_moja_mreza_web.dart`

The plugin uses:
- Method channels for native platform communication
- `plugin_platform_interface` for platform interface verification
- Standard Flutter plugin project structure with example app

The plugin implements:
- `getPlatformVersion()`: Returns platform version information
- `openMojaMreza(BuildContext context)`: Opens Moja Mreža portal with automatic authentication detection
  - First tries to load /Ocitanja (meter readings page)
  - If not authenticated, automatically redirects to /NiasSignOnRequest (login page)
  - Detects successful authentication by checking for specific content on the page

Dependencies:
- `webview_flutter`: For displaying web content in a native view

## Moja mreža endpoints

Routes, HTML selectors, the `POST /Omm/Dostava` meter-reading format and a JS
snippet are in `docs/hep-moja-mreza-recept.md`. Data pulled from the portal goes to
`data/` (gitignored: contains OIB).