import 'package:appstore_dashboard/ui/theme.dart';
import 'package:appstore_dashboard/ui/widgets.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  testWidgets('the title bar offers System, Light and Dark and reports the pick', (tester) async {
    ThemeMode? picked;
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: MacTitleBar(onSearch: () {}, themeMode: ThemeMode.system, onThemeMode: (m) => picked = m),
        ),
      ),
    );
    expect(find.byTooltip('Appearance: System'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<ThemeMode>));
    // The title bar zooms the window on double-click, so a single tap lands once the double-tap window has passed.
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(picked, ThemeMode.dark);
  });

  testWidgets('status chips take their colours from the active theme', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(b),
          home: const Scaffold(body: StateChip('READY_FOR_SALE')),
        ),
      );
      await tester.pumpAndSettle(); // the theme animates between brightnesses
      final k = b == Brightness.dark ? Tokens.dark : Tokens.light;
      final text = tester.widget<Text>(find.text('Ready for sale'));
      expect(text.style!.color, k.good);
    }
  });

  test('text and status colours stay readable on their backgrounds in both themes', () {
    for (final k in [Tokens.light, Tokens.dark]) {
      for (final fg in [k.ink, k.body, k.muted, k.good, k.warn, k.bad, k.neutralInk]) {
        expect(_contrast(fg, k.surface), greaterThanOrEqualTo(4.5), reason: '$fg on surface');
      }
    }
    for (final (fg, bg) in [
      (Tokens.light.good, Tokens.light.goodSoft),
      (Tokens.light.warn, Tokens.light.warnSoft),
      (Tokens.light.bad, Tokens.light.badSoft),
      (Tokens.light.neutralInk, Tokens.light.neutralSoft),
    ]) {
      expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
    }
  });
}
