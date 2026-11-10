import 'package:flutter/material.dart';

/// Design tokens from the redesign prototype. Light is the primary look; dark follows the same structure.
class Tokens {
  const Tokens._(this.ground, this.surface, this.line, this.ink, this.muted, this.accent, this.accentSoft, this.accentInk);
  final Color ground, surface, line, ink, muted, accent, accentSoft, accentInk;

  static const light = Tokens._(Color(0xFFF4F5F8), Colors.white, Color(0xFFE3E6EB), Color(0xFF14171F), Color(0xFF5B6472), Color(0xFF2F5BEA), Color(0xFFEAF0FF), Color(0xFF1F44C4));
  static const dark = Tokens._(Color(0xFF0F1115), Color(0xFF181B21), Color(0xFF2A2F38), Color(0xFFF2F4F8), Color(0xFF9AA3B2), Color(0xFF6C8BFF), Color(0xFF1B2540), Color(0xFFA9BCFF));

  static Tokens of(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? dark : light;
}

ThemeData buildTheme(Brightness b) {
  final k = b == Brightness.dark ? Tokens.dark : Tokens.light;
  final scheme = ColorScheme.fromSeed(seedColor: k.accent, brightness: b).copyWith(
    primary: k.accent,
    onPrimary: b == Brightness.dark ? const Color(0xFF0B1020) : Colors.white,
    surface: k.surface,
    onSurface: k.ink,
    onSurfaceVariant: k.muted,
    outlineVariant: k.line,
    surfaceContainerHighest: b == Brightness.dark ? const Color(0xFF232832) : const Color(0xFFEEF0F4),
  );
  final radius9 = BorderRadius.circular(9);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: k.ground,
    dividerColor: k.line,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: k.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: k.line)),
    ),
    dividerTheme: DividerThemeData(color: k.line.withValues(alpha: 0.7), space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        shape: RoundedRectangleBorder(borderRadius: radius9),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 38),
        side: BorderSide(color: b == Brightness.dark ? k.line : const Color(0xFFD5D9E0)),
        shape: RoundedRectangleBorder(borderRadius: radius9),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: radius9), textStyle: const TextStyle(fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius9, borderSide: BorderSide(color: k.line)),
      enabledBorder: OutlineInputBorder(borderRadius: radius9, borderSide: BorderSide(color: b == Brightness.dark ? k.line : const Color(0xFFCBD0D9))),
      focusedBorder: OutlineInputBorder(borderRadius: radius9, borderSide: BorderSide(color: k.accent, width: 1.6)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: k.ink,
      unselectedLabelColor: k.muted,
      indicatorColor: k.accent,
      dividerColor: k.line,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
      unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? k.accent : (b == Brightness.dark ? const Color(0xFF3A404C) : const Color(0xFFCBD0D9))),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
    dialogTheme: DialogThemeData(backgroundColor: k.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF14171F),
      contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      width: 520,
    ),
    popupMenuTheme: PopupMenuThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: k.line)), color: k.surface, surfaceTintColor: Colors.transparent),
  );
}
