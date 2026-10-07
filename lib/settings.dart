import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences de l'appareil (thème).
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

const _themeKey = 'theme_mode';

Future<void> loadSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_themeKey);
    themeMode.value = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  } catch (_) {
    // Préférences indisponibles : thème du téléphone
  }
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeMode.value = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  } catch (_) {}
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Comme le téléphone',
  ThemeMode.light => 'Clair',
  ThemeMode.dark => 'Sombre',
};

const brandGreen = Color(0xFF0A6B4E);

/// Police de l'application.
const appFont = 'PlusJakartaSans';

ThemeData buildTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: brandGreen,
        brightness: brightness,
      ).copyWith(
        primary: light ? brandGreen : null,
        onPrimary: light ? Colors.white : null,
        primaryContainer: light ? const Color(0xFFE3F1EB) : null,
        onPrimaryContainer: light ? const Color(0xFF064B37) : null,
        surface: light ? Colors.white : null,
        onSurface: light ? const Color(0xFF0F2219) : null,
        onSurfaceVariant: light ? const Color(0xFF55655E) : null,
        outlineVariant: light ? const Color(0xFFE1E7E4) : null,
        outline: light ? const Color(0xFFC9D3CE) : null,
      );
  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: appFont,
  );
  final shape12 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  );
  return base.copyWith(
    scaffoldBackgroundColor: light ? const Color(0xFFF3F5F4) : scheme.surface,
    textTheme: base.textTheme.apply(
      fontFamily: appFont,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: light ? const Color(0xFFF3F5F4) : scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: light ? Colors.white : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      filled: true,
      fillColor: light ? Colors.white : scheme.surfaceContainerHighest,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: shape12,
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        shape: shape12,
        side: BorderSide(color: scheme.outline),
        foregroundColor: scheme.onSurface,
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        minimumSize: const Size(0, 46),
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: light ? Colors.white : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? Colors.white : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: appFont,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    ),
  );
}
