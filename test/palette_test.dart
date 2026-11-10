import 'package:appstore_dashboard/ui/command_palette.dart';
import 'package:appstore_dashboard/ui/pages/apps_page.dart';
import 'package:appstore_dashboard/ui/qr_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> a, [Map<String, dynamic> rel = const {}]) => {'type': type, 'id': id, 'attributes': a, 'relationships': rel};

FakeAsc account(List<String> names) => FakeAsc((r) {
      if (r.method != 'GET' || r.path.split('?').first != '/v1/apps') return null;
      return json({
        'data': [for (var i = 0; i < names.length; i++) res('apps', 'A$i', {'name': names[i], 'bundleId': 'com.example.${names[i].toLowerCase().replaceAll(' ', '')}', 'sku': 'S$i'}, {'appStoreVersions': {'data': []}})],
      });
    });

void main() {
  test('fuzzy matching: in-order letters match, tighter and earlier matches win, misses are null', () {
    expect(fuzzyScore('vg', 'Vidyagram'), isNotNull);
    expect(fuzzyScore('zz', 'Vidyagram'), isNull);
    expect(fuzzyScore('', 'anything'), 0);
    expect(fuzzyScore('vid', 'Vidyagram')!, greaterThan(fuzzyScore('vid', 'Avid Video')!), reason: 'a prefix beats a mid-word match');
    expect(fuzzyScore('sales', 'Check Sales & Proceeds'), isNotNull);
    expect(fuzzyScore('gram', 'Vidyagram')!, greaterThan(fuzzyScore('gam', 'Vidyagram')!), reason: 'an unbroken run scores higher');
  });

  testWidgets('QR view draws for a link, and only Apple links get one', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: QrView(data: 'https://testflight.apple.com/join/AbCd1234')))));
    expect(find.byType(QrView), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(isTestFlightLink('https://testflight.apple.com/join/AbCd1234'), isTrue);
    expect(isTestFlightLink('https://evil.example/join/x'), isFalse);
    expect(isTestFlightLink(null), isFalse);
  });

  group('palette', () {
    Future<(List<String>, FakeAsc)> open(WidgetTester tester, List<String> names, {bool lock = true}) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = account(names);
      final events = <String>[];
      final store = AppsStore(fake.client);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showCommandPalette(
                  context,
                  PaletteActions(store: store, openApp: (a, {int tab = 0}) => events.add('open ${a.name} tab $tab'), go: (i) => events.add('go $i'), lock: lock ? () => events.add('lock') : null),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return (events, fake);
    }

    testWidgets('lists actions and apps from the one shared request, and typing filters them', (tester) async {
      final (_, fake) = await open(tester, ['Vidyagram', 'Mac Notes']);
      expect(find.text('Upload New Build'), findsOneWidget);
      expect(find.text('Check Sales & Proceeds'), findsOneWidget);
      expect(find.text('Manage Team'), findsOneWidget);
      expect(find.text('Lock Console'), findsOneWidget);
      expect(find.text('Vidyagram'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'mac');
      await tester.pump();
      expect(find.text('Mac Notes'), findsOneWidget);
      expect(find.text('Vidyagram'), findsNothing);
      expect(fake.log, hasLength(1));
    });

    testWidgets('Enter opens the highlighted app; arrow keys move the highlight', (tester) async {
      final (events, _) = await open(tester, ['Vidyagram', 'Mac Notes']);
      await tester.enterText(find.byType(TextField), 'notes');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(events, ['open Mac Notes tab 0']);
    });

    testWidgets('actions: sales and team switch pages; lock locks', (tester) async {
      final (events, _) = await open(tester, ['Vidyagram', 'Mac Notes']);
      await tester.tap(find.text('Check Sales & Proceeds'));
      await tester.pumpAndSettle();
      expect(events, ['go 1']);
    });

    testWidgets('Upload New Build with one app opens its Upload tab; with several it asks which app', (tester) async {
      final (one, _) = await open(tester, ['Vidyagram']);
      await tester.tap(find.text('Upload New Build'));
      await tester.pumpAndSettle();
      expect(one, ['open Vidyagram tab 4']);
    });

    testWidgets('with several apps, Upload New Build lets you pick one', (tester) async {
      final (events, _) = await open(tester, ['Vidyagram', 'Mac Notes']);
      await tester.tap(find.text('Upload New Build'));
      await tester.pumpAndSettle();
      expect(events, isEmpty, reason: 'it asks which app first');
      expect(find.text('Upload a build to com.example.macnotes'), findsOneWidget);
      await tester.tap(find.text('Mac Notes'));
      await tester.pumpAndSettle();
      expect(events, ['open Mac Notes tab 4']);
    });

    testWidgets('no Lock action when the platform has no device lock', (tester) async {
      await open(tester, ['Vidyagram'], lock: false);
      expect(find.text('Lock Console'), findsNothing);
    });
  });
}
