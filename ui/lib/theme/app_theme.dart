import 'package:flutter/material.dart';

/// Design tokens.
///
/// These previously lived in both main.dart and dashboard.dart, so a colour
/// change had to be made twice. Every widget now imports them from here.
const Color kAppBackground = Color(0xFFFAFBFD);
const Color kAccentBlue = Color(0xFF007BFF);
const Color kSlateText = Color(0xFF2C3E50);
const Color kEdgeTint = Color(0xFFEFF4FB);
const Color kDangerRed = Color(0xFFB91C1C);

/// Radii and motion constants shared by the panels, so the surfaces stay
/// visually consistent as widgets move between files.
const double kCardRadius = 16;
const double kPanelRadius = 24;
const Duration kFastMotion = Duration(milliseconds: 180);
const Duration kMediumMotion = Duration(milliseconds: 220);
const Duration kSlowMotion = Duration(milliseconds: 320);

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: kAccentBlue,
      brightness: Brightness.light,
      primary: kAccentBlue,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: kAppBackground,
    dividerColor: kSlateText.withValues(alpha: 0.08),
    hoverColor: kAccentBlue.withValues(alpha: 0.06),
    splashColor: kAccentBlue.withValues(alpha: 0.10),
    highlightColor: kAccentBlue.withValues(alpha: 0.05),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: kSlateText,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: kSlateText,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: kSlateText,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.35, color: kSlateText),
      bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: kSlateText),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.3, color: kSlateText),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: kSlateText,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        borderSide: BorderSide(color: kSlateText.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        borderSide: BorderSide(color: kSlateText.withValues(alpha: 0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
        borderSide: const BorderSide(color: kAccentBlue, width: 1.1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return kAccentBlue.withValues(alpha: 0.35);
          }
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF006BE0);
          }
          if (states.contains(WidgetState.hovered)) {
            return const Color(0xFF0A88FF);
          }
          return kAccentBlue;
        }),
        foregroundColor: WidgetStateProperty.all<Color>(Colors.white),
        padding: WidgetStateProperty.all<EdgeInsets>(
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardRadius),
          ),
        ),
        textStyle: WidgetStateProperty.all<TextStyle>(
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        elevation: WidgetStateProperty.all<double>(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all<Color>(kSlateText),
        side: WidgetStateProperty.resolveWith<BorderSide>((states) {
          if (states.contains(WidgetState.hovered)) {
            return BorderSide(color: kAccentBlue.withValues(alpha: 0.45));
          }
          return BorderSide(color: kSlateText.withValues(alpha: 0.12));
        }),
        padding: WidgetStateProperty.all<EdgeInsets>(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kCardRadius),
          ),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSlateText,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    useMaterial3: true,
  );
}
