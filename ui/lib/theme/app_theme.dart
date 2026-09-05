import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens.
///
/// These previously lived in both main.dart and dashboard.dart, so a colour
/// change had to be made twice. Every widget now imports them from here.
///
/// On a dark ground, drop shadows read as mud rather than as elevation, so
/// depth comes from three layered surfaces plus borders, and emphasis comes
/// from an accent glow. That is why there is a surface ramp here and only one
/// shadow helper.
///
/// The accent itself is no longer one of these constants: it is a user
/// setting (see [AccentColorController]), because a fixed brand blue can't
/// double as "pick your own colour." Everything downstream of it — the text
/// drawn on a filled accent button, the hover/press variants, the glow — is
/// computed from whatever colour is chosen, rather than hand-picked to match
/// one specific hue.
const Color kAppBackground = Color(0xFF14111C);
const Color kSurface = Color(0xFF1B1726);
const Color kSurfaceElevated = Color(0xFF241F33);
const Color kBorder = Color(0xFF362F49);

const Color kTextPrimary = Color(0xFFF1EEF7);
const Color kTextSecondary = Color(0xFFA79FBC);
const Color kTextFaint = Color(0xFF756D8C);
const Color kDangerRed = Color(0xFFF85149);

/// Kept so older call sites that referenced the light tokens still resolve to
/// something sensible; both now point at the dark equivalents.
const Color kSlateText = kTextPrimary;
const Color kEdgeTint = kSurface;

/// The accent the app ships with before a user ever opens the colour picker.
const Color kDefaultAccent = Color(0xFFA78BFA);

/// The swatches offered in the accent-colour setting. Curated rather than a
/// full colour wheel, since the point is a handful of good choices, not every
/// possible hue.
const List<Color> kAccentSwatches = <Color>[
  Color(0xFFA78BFA), // Purple
  Color(0xFF60A5FA), // Blue
  Color(0xFFEF4444), // Red
  Color(0xFF34D399), // Green
  Color(0xFFFBBF24), // Amber
  Color(0xFFFFFFFF), // White
];

/// Fixed identity colours for subjects, distinct from the user's accent
/// choice. A task's own subject always reads the same colour regardless of
/// which colour the user has picked for the app, so at-a-glance scanning by
/// subject keeps working no matter the accent setting — the selected task is
/// the one exception, which borrows the accent instead (see [TaskCard]).
const List<Color> kSubjectPalette = <Color>[
  Color(0xFFF27C93), // Rose
  Color(0xFF6FC7C0), // Teal
  Color(0xFF7FB2FA), // Blue
  Color(0xFFF0C36B), // Amber
  Color(0xFF85CFA0), // Green
  Color(0xFFC792EA), // Lilac
  Color(0xFFE8967A), // Terracotta
];

/// A stable colour for a subject name, independent of list position or sort
/// order — the same subject always lands on the same colour, the same way
/// task identity in the backend no longer depends on scrape order.
Color subjectColorFor(String subjectName) {
  final hash = subjectName.trim().toLowerCase().codeUnits.fold<int>(
    0,
    (acc, unit) => (acc * 31 + unit) & 0x7fffffff,
  );
  return kSubjectPalette[hash % kSubjectPalette.length];
}

/// A simple line icon standing in for a subject, chosen by keyword rather
/// than by exact subject name, since ManageBac subject names vary by school
/// and by IB programme (MYP vs. DP) for what is conceptually the same class.
IconData subjectIconFor(String subjectName) {
  final name = subjectName.toLowerCase();
  if (name.contains('math')) return Icons.grid_4x4_rounded;
  if (name.contains('design') || name.contains('art')) {
    return Icons.palette_outlined;
  }
  if (name.contains('arabic') ||
      name.contains('language') ||
      name.contains('literature')) {
    return Icons.translate_rounded;
  }
  if (name.contains('science') ||
      name.contains('biology') ||
      name.contains('chemistry') ||
      name.contains('physics')) {
    return Icons.science_outlined;
  }
  if (name.contains('individuals') ||
      name.contains('societ') ||
      name.contains('history') ||
      name.contains('geography')) {
    return Icons.public_outlined;
  }
  return Icons.menu_book_outlined;
}

const double kCardRadius = 16;
const double kPanelRadius = 20;
const Duration kFastMotion = Duration(milliseconds: 180);
const Duration kMediumMotion = Duration(milliseconds: 220);
const Duration kSlowMotion = Duration(milliseconds: 320);

/// A soft accent halo, used for the selected task and the busy generate
/// button. Takes the colour explicitly rather than reading a constant, since
/// that colour is now a user setting.
List<BoxShadow> accentGlow(Color color, {double opacity = 0.22, double blur = 20}) {
  return <BoxShadow>[
    BoxShadow(
      color: color.withValues(alpha: opacity),
      blurRadius: blur,
      spreadRadius: 0.4,
    ),
  ];
}

double _relativeLuminance(Color color) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
}

double _contrastRatio(double luminanceA, double luminanceB) {
  final lighter = math.max(luminanceA, luminanceB);
  final darker = math.min(luminanceA, luminanceB);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Whichever of near-black or white actually reads best on a filled button in
/// this colour — not a fixed choice, because a pale lavender and a vivid red
/// don't want the same answer, and a user picking "White" as their accent
/// still needs to be able to read the Generate button.
Color onAccentFor(Color accent) {
  const darkText = Color(0xFF14101F);
  final accentLuminance = _relativeLuminance(accent);
  final withDark = _contrastRatio(accentLuminance, _relativeLuminance(darkText));
  final withWhite = _contrastRatio(accentLuminance, 1.0);
  return withDark >= withWhite ? darkText : Colors.white;
}

/// A pressed/hover-darker variant of an arbitrary accent colour.
Color darkenAccent(Color color, [double amount = 0.16]) {
  return Color.lerp(color, Colors.black, amount) ?? color;
}

/// A hover-lighter variant of an arbitrary accent colour.
Color lightenAccent(Color color, [double amount = 0.14]) {
  return Color.lerp(color, Colors.white, amount) ?? color;
}

ThemeData buildAppTheme(Color accent) {
  final onAccent = onAccentFor(accent);
  final accentDeep = darkenAccent(accent);
  final accentGlowColor = lightenAccent(accent);

  final baseTextTheme = GoogleFonts.ibmPlexSansTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  );
  final displayFont = GoogleFonts.bricolageGrotesque;

  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: ColorScheme.dark(
      primary: accent,
      onPrimary: onAccent,
      secondary: accentGlowColor,
      surface: kSurface,
      onSurface: kTextPrimary,
      error: kDangerRed,
    ),
    scaffoldBackgroundColor: kAppBackground,
    canvasColor: kSurface,
    dividerColor: kBorder,
    hoverColor: accent.withValues(alpha: 0.08),
    splashColor: accent.withValues(alpha: 0.12),
    highlightColor: accent.withValues(alpha: 0.06),
    iconTheme: const IconThemeData(color: kTextSecondary),
    textTheme: baseTextTheme.copyWith(
      headlineSmall: displayFont(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: kTextPrimary,
        letterSpacing: -0.4,
      ),
      titleLarge: displayFont(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
      titleMedium: displayFont(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: kTextPrimary,
      ),
      bodyLarge: baseTextTheme.bodyLarge?.copyWith(
        fontSize: 14.5,
        height: 1.45,
        color: kTextPrimary,
      ),
      bodyMedium: baseTextTheme.bodyMedium?.copyWith(
        fontSize: 13.5,
        height: 1.4,
        color: kTextPrimary,
      ),
      bodySmall: baseTextTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        color: kTextSecondary,
      ),
      labelLarge: baseTextTheme.labelLarge?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
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
      titleTextStyle: displayFont(
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
      floatingLabelStyle: TextStyle(color: accent),
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
        borderSide: BorderSide(color: accent, width: 1.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.disabled)) {
            return accentDeep.withValues(alpha: 0.30);
          }
          if (states.contains(WidgetState.pressed)) {
            return accentDeep;
          }
          if (states.contains(WidgetState.hovered)) {
            return accentGlowColor;
          }
          return accent;
        }),
        foregroundColor: WidgetStateProperty.all<Color>(onAccent),
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
            return accent;
          }
          return kTextPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.hovered)) {
            return accent.withValues(alpha: 0.10);
          }
          return Colors.transparent;
        }),
        side: WidgetStateProperty.resolveWith<BorderSide>((states) {
          if (states.contains(WidgetState.hovered)) {
            return BorderSide(color: accent.withValues(alpha: 0.55));
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
    progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    useMaterial3: true,
  );
}
