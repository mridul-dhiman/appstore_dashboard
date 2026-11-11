import 'package:appstore_dashboard/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';
import 'support/fake_state.dart';

Map<String, dynamic> appsJson() => {
  'data': [
    {
      'type': 'apps',
      'id': 'A1',
      'attributes': {'name': 'Vidyagram', 'bundleId': 'com.example.vidya', 'sku': 'VG1'},
    },
  ],
};

Future<StateHarness> pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = StateHarness((r) => r.method == 'GET' && r.path.startsWith('/v1/apps') ? json(appsJson()) : null);
  await h.state.unlock();
  await tester.pumpWidget(MaterialApp(home: Shell(state: h.state)));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('renaming the client (which replaces its HTTP client) does not leave the Apps list on the closed one', (tester) async {
    final h = await pumpShell(tester);
    expect(find.text('Vidyagram'), findsWidgets);

    await h.state.rename(h.state.credentials!.id, 'Renamed');
    await tester.pumpAndSettle();
    expect(h.clients.first.closed, isTrue, reason: 'the old client was closed');

    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already closed'), findsNothing);
    expect(find.textContaining('Could not reach'), findsNothing);
    expect(find.text('Vidyagram'), findsWidgets);
  });

  testWidgets('keyboard: Cmd-2 goes to Sales, Cmd-R reloads the page, Cmd-[ leaves an open app', (tester) async {
    final h = await pumpShell(tester);
    int appLoads() => h.log.where((r) => r.path.startsWith('/v1/apps?')).length;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Sales & Trends'), findsWidgets);
    expect(find.textContaining('vendor number'), findsWidgets);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    final before = appLoads();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(appLoads(), before + 1, reason: 'Cmd-R loads the list again');

    await tester.tap(find.text('Vidyagram').first);
    await tester.pumpAndSettle();
    expect(find.text('Store Listing'), findsWidgets);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
    expect(find.text('Store Listing'), findsNothing);
  });

  testWidgets('custom controls are labelled buttons, and the current place is marked selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpShell(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    expect(
      tester.getSemantics(find.text('Apps').first),
      matchesSemantics(
        label: 'Apps',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Search apps and actions')),
      isSemantics(isButton: true, hint: 'Opens the command palette, Ctrl K'),
    );
    handle.dispose();
  });
}
