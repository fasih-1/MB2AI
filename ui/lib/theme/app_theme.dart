import 'package:flutter/material.dart';

/// Design tokens for the dark theme.
///
/// These previously lived in both main.dart and dashboard.dart, so a colour
/// change had to be made twice. Every widget now imports them from here.
///
/// On a dark ground, drop shadows read as mud rather than as elevation, so
/// depth comes from three layered surfaces plus borders, and emphasis comes
/// from an accent glow. That is why there is a surface ramp here and only one
/// shadow helper.
const Color kAppBackground = Color(0xFF0D1117);
const Color kSurface = Color(0xFF161B22);
const Color kSurfaceElevated = Color(0xFF1C2331);
const Color kBorder = Color(0xFF2A3441);

const Color kAccentBlue = Color(0xFF4C9AFF);
const Color kAccentDeep = Color(0xFF1F6FEB);
const Color kAccentGlow = Color(0xFF58A6FF);

const Color kTextPrimary = Color(0xFFE6EDF3);
const Color kTextSecondary = Color(0xFF8B98A9);
const Color kDangerRed = Color(0xFFF85149);

/// Kept so older call sites that referenced the light tokens still resolve to
/// something sensible; both now point at the dark equivalents.
const Color kSlateText = kTextPrimary;
const Color kEdgeTint = kSurface;

const double kCardRadius = 16;
const double kPanelRadius = 20;
const Duration kFastMotion = Duration(milliseconds: 180);
const Duration kMediumMotion = Duration(milliseconds: 220);
const Duration kSlowMotion = Duration(milliseconds: 320);

/// A soft accent halo, used for the selected task and the busy generate button.
List<BoxShadow> accentGlow({double opacity = 0.22, double blur = 20}) {
  return <BoxShadow>[
    BoxShadow(
      color: kAccentGlow.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 0.4,
    ),
  ];
}

ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: kAccentBlue,
      onPrimary: Color(0xFF0A1020),
      secondary: kAccentGlow,
      surface: kSurface,
      onSurface: kTextPrimary,
      error: kDangerRed,
    ),
    scaffoldBackgroundColor: kAppBackground,
    canvasColor: kSurface,
    dividerColor: kBorder,
    hoverColor: kAccentBlue.withValues(alpha: 0.08),
    splashColor: kAccentBlue.withValues(alpha: 0.12),
    highlightColor: kAccentBlue.withValues(alpha: 0.06),
    iconTheme: const IconThemeData(color: kTextSecondary),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
        letterSpacing: -0.3,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
      ),
      bodyLarge: TextStyle(fontSize: 14.5, height: 1.45, color: kTextPrimary),
      bodyMedium: TextStyle(fontSize: 13.5, height: 1.4, color: kTextPrimary),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: kTextSecondary),
      labelLarge: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
        color: kTextPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kPanelRadius),
        side: const BorderSide(color: kBorder),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: kSurfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      textStyle: const TextStyle(fontSize: 12, color: kTextPrimary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kAppBackground,
      hintStyle: const TextStyle(color: kTextSecondary, fontSize: 13.5),
      labelStyle: const TextStyle(color: kTextSecondary, fontSize: 13.5),
      floatingLabelStyle: const TextStyle(color: kAccentBlue),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kAccentBlue, width: 1.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return kAccentDeep.withValues(alpha: 0.30);
          }
          if (states.contains(WidgetState.pressed)) {
            return kAccentDeep;
          }
          if (states.contains(WidgetState.hovered)) {
            return kAccentGlow;
          }
          return kAccentBlue;
        }),
        foregroundColor: WidgetStateProperty.all<Color>(
          const Color(0xFF0A1020),
        ),
        padding: WidgetStateProperty.all<EdgeInsets>(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: WidgetStateProperty.all<TextStyle>(
          const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        elevation: WidgetStateProperty.all<double>(0),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.hovered)) {
            return kAccentBlue;
          }
          return kTextPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.hovered)) {
            return kAccentBlue.withValues(alpha: 0.10);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith<BorderSide>((states) {
          if (states.contains(WidgetState.hovered)) {
            return BorderSide(color: kAccentBlue.withValues(alpha: 0.55));
          }
          return const BorderSide(color: kBorder);
        }),
        padding: WidgetStateProperty.all<EdgeInsets>(
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        shape: WidgetStateProperty.all<RoundedRectangleBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: WidgetStateProperty.all<TextStyle>(
          const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.all<Color>(kTextSecondary),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kSurfaceElevated,
      contentTextStyle: const TextStyle(color: kTextPrimary, fontSize: 13.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kBorder),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: kAccentBlue,
    ),
    useMaterial3: true,
  );
}
