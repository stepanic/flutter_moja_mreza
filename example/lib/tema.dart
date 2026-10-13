import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tokeni iz energy.domovina.ai (`tailwind.config.ts`, `docs/09-dizajn-sustav.md`).
/// Boja se u widgetima uzima odavde ili iz teme, nikad kao hex.
abstract final class Boje {
  static const cream = Color(0xFFFBF8F3);
  static const sand = Color(0xFFF5EFE6);
  static const sandDeep = Color(0xFFF0E6D2);
  static const ink = Color(0xFF1A1A1A);
  static const inkSoft = Color(0xFF3A3A3A);
  static const inkMuted = Color(0xFF6B6B6B);
  static const border = Color(0x1F1A1A1A);

  /// Primarni akcent i jedina CTA boja.
  static const forest = Color(0xFF2D6A4F);
  static const forest800 = Color(0xFF1C4331);
  static const forestSoft = Color(0xFFDDEBE3);
  static const teal = Color(0xFF0F4C5C);
  static const teal300 = Color(0xFF6491A0);
  static const rust = Color(0xFF9B2226);

  /// Jantar nosi podatak (kWh), nikad gumb: na bijelom ima nizak kontrast.
  static const solar = Color(0xFFE8A33D);
  static const solarSoft = Color(0xFFFBF0DC);

  /// Tekst na svijetloj podlozi uz jantar (AA).
  static const solarInk = Color(0xFF7A4F08);

  /// Tamnoplava iz mediakita (logo, donja traka zastave).
  static const navy = Color(0xFF002F6C);
}

/// Brojke u stupcima se ne smiju micati.
const tabularno = [FontFeature.tabularFigures()];

abstract final class DomovinaTema {
  static ThemeData svijetla() {
    const shema = ColorScheme.light(
      primary: Boje.forest,
      onPrimary: Boje.cream,
      primaryContainer: Boje.forestSoft,
      onPrimaryContainer: Boje.forest800,
      secondary: Boje.teal,
      onSecondary: Colors.white,
      tertiary: Boje.solar,
      onTertiary: Boje.ink,
      tertiaryContainer: Boje.solarSoft,
      onTertiaryContainer: Boje.solarInk,
      error: Boje.rust,
      onError: Colors.white,
      errorContainer: Color(0xFFF6E3E3),
      onErrorContainer: Boje.rust,
      surface: Boje.cream,
      onSurface: Boje.ink,
      onSurfaceVariant: Boje.inkMuted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: Boje.sand,
      surfaceContainerHigh: Boje.sand,
      surfaceContainerHighest: Boje.sandDeep,
      outline: Boje.border,
      outlineVariant: Boje.border,
    );

    const naslov = TextStyle(
      fontFamily: 'Fraunces',
      fontWeight: FontWeight.w600,
      color: Boje.ink,
      letterSpacing: -0.3,
    );
    final tekst = Typography.material2021().black.apply(
      fontFamily: 'Inter',
      bodyColor: Boje.ink,
      displayColor: Boje.ink,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: shema,
      scaffoldBackgroundColor: Boje.cream,
      fontFamily: 'Inter',
      textTheme: tekst.copyWith(
        displaySmall: naslov.copyWith(fontSize: 34, height: 1.1),
        headlineMedium: naslov.copyWith(fontSize: 28, height: 1.15),
        headlineSmall: naslov.copyWith(fontSize: 22, height: 1.2),
        titleLarge: naslov.copyWith(fontSize: 20, height: 1.25),
        titleMedium: tekst.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: tekst.labelSmall?.copyWith(
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: Boje.inkMuted,
        ),
        bodyMedium: tekst.bodyMedium?.copyWith(color: Boje.inkSoft),
        bodySmall: tekst.bodySmall?.copyWith(color: Boje.inkMuted),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Boje.cream,
        foregroundColor: Boje.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0.5,
        shadowColor: Boje.border,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Fraunces',
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: Boje.ink,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Boje.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Boje.border, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Boje.forest,
          foregroundColor: Boje.cream,
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Boje.ink,
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
          side: const BorderSide(color: Boje.border),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Boje.forest,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Boje.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Boje.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Boje.teal, width: 2),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Boje.ink,
        unselectedLabelColor: Boje.inkMuted,
        indicatorColor: Boje.forest,
        dividerColor: Boje.border,
        labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Boje.forest : null,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Boje.ink,
        behavior: SnackBarBehavior.floating,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Boje.forest,
        linearTrackColor: Boje.sand,
      ),
    );
  }

  /// OFL licence fontova na stranici „Licence“.
  static void registrirajLicence() {
    LicenseRegistry.addLicense(() async* {
      for (final (font, datoteka) in const [
        ('Inter', 'OFL-Inter.txt'),
        ('Fraunces', 'OFL-Fraunces.txt'),
      ]) {
        yield LicenseEntryWithLineBreaks([
          font,
        ], await rootBundle.loadString('assets/fonts/$datoteka'));
      }
    });
  }
}
