import 'package:flutter/material.dart';

abstract final class AisleColors {
  static const ink = Color(0xFF1B1D1A);
  static const muted = Color(0xFF6E716A);
  static const cream = Color(0xFFF6F3EC);
  static const card = Colors.white;
  static const forest = Color(0xFF1F4E3D);
  static const saffron = Color(0xFFF4A23C);
  static const line = Color(0xFFE8E3D9);

  /// Soft backgrounds for category tiles and product photos.
  static const pastels = [
    Color(0xFFFCE3D6), // peach
    Color(0xFFDDF0E3), // mint
    Color(0xFFFBF0C8), // butter
    Color(0xFFE6E1F6), // lavender
    Color(0xFFDCEAF6), // sky
    Color(0xFFF8DCE4), // blush
  ];

  static Color pastel(int index) => pastels[index % pastels.length];
}

ThemeData buildAisleTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AisleColors.forest,
    primary: AisleColors.forest,
    secondary: AisleColors.saffron,
    surface: AisleColors.cream,
    onSurface: AisleColors.ink,
  );
  final base = ThemeData(colorScheme: colorScheme);
  final text = base.textTheme.apply(
    bodyColor: AisleColors.ink,
    displayColor: AisleColors.ink,
  );

  return base.copyWith(
    scaffoldBackgroundColor: AisleColors.cream,
    textTheme: text.copyWith(
      headlineLarge: text.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -1.2,
        height: 1.1,
      ),
      headlineMedium: text.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AisleColors.cream,
      foregroundColor: AisleColors.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AisleColors.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AisleColors.ink,
      actionTextColor: AisleColors.saffron,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: AisleColors.saffron,
      textColor: AisleColors.ink,
    ),
    dividerTheme: const DividerThemeData(color: AisleColors.line, space: 1),
  );
}
