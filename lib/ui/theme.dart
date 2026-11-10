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
  });

  final Color ground, surface, inset, line, ink, body, muted, accent, accentSoft, accentInk, sidebar, titlebar;
  final List<BoxShadow> shadow;

  static const light = Tokens._(
    ground: Color(0xFFF5F6F9),
    surface: Color(0xFFFFFFFF),
    inset: Color(0xFFF0F2F5),
    line: Color(0x14000000), // rgba(0,0,0,.08)
    ink: Color(0xFF1D1D1F),
    body: Color(0xFF3A3A3C),
    muted: Color(0xFF6E6E73),
    accent: Color(0xFF0071E3),
    accentSoft: Color(0xFFEBF3FF),
    accentInk: Color(0xFF0062C4),
    sidebar: Color(0xEBF0F2F6),
    titlebar: Color(0xF0F6F7FA),
    shadow: [BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)), BoxShadow(color: Color(0x05000000), blurRadius: 2, offset: Offset(0, 1))],
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
    error: dark ? const Color(0xFFFF6B6B) : const Color(0xFFD70015),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: k.line)),
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
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r9), textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: r9))),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: k.inset,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: r9, borderSide: BorderSide(color: k.line)),
      enabledBorder: OutlineInputBorder(borderRadius: r9, borderSide: BorderSide(color: k.line)),
      focusedBorder: OutlineInputBorder(borderRadius: r9, borderSide: BorderSide(color: k.accent, width: 1.5)),
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
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? const Color(0xFF34C759) : (dark ? const Color(0xFF3A3F4B) : const Color(0xFFD1D1D6))),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
    dialogTheme: DialogThemeData(backgroundColor: k.surface, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: k.line))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF2C2F3A) : const Color(0xFF1D1D1F),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      width: 520,
    ),
    popupMenuTheme: PopupMenuThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: k.line)), color: k.surface, surfaceTintColor: Colors.transparent),
    tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: dark ? const Color(0xFF2C2F3A) : const Color(0xFF1D1D1F), borderRadius: BorderRadius.circular(6)), textStyle: const TextStyle(color: Colors.white, fontSize: 12)),
  );
}
