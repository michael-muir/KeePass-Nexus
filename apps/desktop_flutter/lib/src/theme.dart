import 'package:flutter/material.dart';

const _accent = Color(0xFF6B9F3E);
const _ink = Color(0xFF17211A);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _accent,
    brightness: brightness,
    surface: brightness == Brightness.light
        ? const Color(0xFFF7F8F6)
        : const Color(0xFF171B18),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: brightness == Brightness.light ? _ink : scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF202622),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light
          ? Colors.white
          : const Color(0xFF202622),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    ),
    dividerTheme:
        DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.7)),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
          bodyColor: brightness == Brightness.light ? _ink : scheme.onSurface,
          displayColor:
              brightness == Brightness.light ? _ink : scheme.onSurface,
        ),
  );
}

const accentColor = _accent;
