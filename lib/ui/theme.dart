import 'package:flutter/material.dart';

/// Design tokens: a native-macOS look in light and dark. Light is a white card on a pale canvas with Apple's developer
/// blue; dark is deep graphite with a brighter blue.
class Tokens {
  const Tokens._({
    required this.ground,
    required this.surface,
    required this.inset,
    required this.line,
    required this.ink,
    required this.body,
    required this.muted,
    required this.accent,
    required this.accentSoft,
    required this.accentInk,
    required this.sidebar,
    required this.titlebar,
    required this.shadow,
    required this.good,
    required this.goodSoft,
    required this.warn,
    required this.warnSoft,
    required this.bad,
    required this.badSoft,
    required this.neutralInk,
    required this.neutralSoft,
    required this.star,
    required this.scrim,
  });

  final Color ground, surface, inset, line, ink, body, muted, accent, accentSoft, accentInk, sidebar, titlebar;

  /// Status colours: text/icon colour and its pale fill. Each pair keeps 4.5:1 contrast in its own theme.
  final Color good, goodSoft, warn, warnSoft, bad, badSoft, neutralInk, neutralSoft;

  /// Rating stars.
  final Color star;

  /// Dims the page behind dialogs and the command palette.
  final Color scrim;
  final List<BoxShadow> shadow;

  // Matches the light screens in the Stitch design: slate text on a cool grey canvas, white cards, blue accent.
  static const light = Tokens._(
    ground: Color(0xFFF7F8FA),
    surface: Color(0xFFFFFFFF),
    inset: Color(0xFFF1F3F6),
    line: Color(0xFFE4E7EC),
    ink: Color(0xFF0F172A),
    body: Color(0xFF334155),
    muted: Color(0xFF64748B),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0xFFEFF4FF),
    accentInk: Color(0xFF1D4ED8),
    sidebar: Color(0xF2F3F5F8),
    titlebar: Color(0xF5F9FAFB),
    shadow: [
      BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(color: Color(0x050F172A), blurRadius: 2, offset: Offset(0, 1)),
    ],
    good: Color(0xFF047857),
    goodSoft: Color(0xFFECFDF5),
    warn: Color(0xFFB45309),
    warnSoft: Color(0xFFFFFBEB),
    bad: Color(0xFFB91C1C),
    badSoft: Color(0xFFFEF2F2),
    neutralInk: Color(0xFF475569),
    neutralSoft: Color(0xFFF1F5F9),
    star: Color(0xFFF59E0B),
    scrim: Color(0x660F172A),
  );

  static const dark = Tokens._(
    ground: Color(0xFF111318),
    surface: Color(0xFF1A1E27),
    inset: Color(0xFF101217),
    line: Color(0x14FFFFFF), // rgba(255,255,255,.08)
    ink: Color(0xFFF5F5F7),
    body: Color(0xFFD1D5DB),
    muted: Color(0xFF9CA3AF),
    accent: Color(0xFF2997FF),
    accentSoft: Color(0x292997FF), // rgba(41,151,255,.16)
    accentInk: Color(0xFF58A6FF),
    sidebar: Color(0xE0121520),
    titlebar: Color(0xEB161922),
    shadow: [],
    good: Color(0xFF34D399),
    goodSoft: Color(0x2410B981),
    warn: Color(0xFFFBBF24),
    warnSoft: Color(0x24F59E0B),
    bad: Color(0xFFFB7185),
    badSoft: Color(0x24F43F5E),
    neutralInk: Color(0xFFC3CAD6),
    neutralSoft: Color(0xFF232832),
    star: Color(0xFFFFB020),
    scrim: Color(0x99000000),
  );

  static Tokens of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness b) {
  final k = b == Brightness.dark ? Tokens.dark : Tokens.light;
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: k.accent, brightness: b).copyWith(
    primary: k.accent,
    onPrimary: dark ? const Color(0xFF06121F) : Colors.white,
    primaryContainer: k.accentSoft,
    onPrimaryContainer: k.accentInk,
    surface: k.surface,
    onSurface: k.ink,
    onSurfaceVariant: k.muted,
    outline: dark ? const Color(0x24FFFFFF) : const Color(0x24000000),
    outlineVariant: k.line,
    surfaceContainerHighest: k.inset,
    surfaceContainerLow: k.inset,
    surfaceContainer: k.inset,
    error: k.bad,
  );
  final r9 = BorderRadius.circular(8);
  final borderStrong = dark ? const Color(0x24FFFFFF) : const Color(0x24000000);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: k.ground,
    canvasColor: k.surface,
    dividerColor: k.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: dark ? const Color(0x0DFFFFFF) : const Color(0x0A000000),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: k.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: k.line),
      ),
    ),
    dividerTheme: DividerThemeData(color: k.line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(borderRadius: r9),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        side: BorderSide(color: borderStrong),
        shape: RoundedRectangleBorder(borderRadius: r9),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: r9),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r9)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: k.inset,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: r9,
        borderSide: BorderSide(color: k.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: r9,
        borderSide: BorderSide(color: k.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: r9,
        borderSide: BorderSide(color: k.accent, width: 1.5),
      ),
    ),
    // Segmented control, like System Settings: an inset track with a raised selected segment.
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: r9)),
        side: WidgetStatePropertyAll(BorderSide(color: k.line)),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.surface : k.inset),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.ink : k.muted),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: k.ink,
      unselectedLabelColor: k.muted,
      indicatorColor: k.accent,
      dividerColor: k.line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? const Color(0xFF34C759) : (dark ? const Color(0xFF3A3F4B) : const Color(0xFFD1D1D6)),
      ),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    dialogTheme: DialogThemeData(
      backgroundColor: k.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: k.line),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2C2F3A) : const Color(0xFF1D1D1F),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      width: 520,
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: k.line),
      ),
      color: k.surface,
      surfaceTintColor: Colors.transparent,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: dark ? const Color(0xFF2C2F3A) : const Color(0xFF1D1D1F), borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}
