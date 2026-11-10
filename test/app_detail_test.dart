import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/ui/pages/app_detail_page.dart';
import 'package:appstore_dashboard/ui/pages/apps_page.dart';
import 'package:appstore_dashboard/ui/pages/upload_tab.dart';
import 'package:appstore_dashboard/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Resource res(String type, String id, Map<String, dynamic> a) => Resource(id: id, type: type, attributes: a, relationships: const {});

AppSummary summary() => AppSummary(
      res('apps', 'A1', {'name': 'Vidyagram', 'bundleId': 'com.example.vidya', 'sku': 'VG1'}),
      res('appStoreVersions', 'V1', {'versionString': '1.1.16', 'appStoreState': 'READY_FOR_SALE', 'platform': 'IOS'}),
    );

/// Every read answers "nothing here", so a tab renders its empty state; the tests are about the page around the tabs.
FakeAsc quiet() => FakeAsc((r) => r.method == 'GET' ? json({'data': []}) : null);

Future<(FakeAsc, List<String>)> pump(WidgetTester tester, {int tab = 0}) async {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = quiet();
  final events = <String>[];
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AppDetailPage(client: fake.client, summary: summary(), initialTab: tab, onBack: () => events.add('back')))));
  await tester.pumpAndSettle();
  return (fake, events);
}

void main() {
  testWidgets('the header shows the app\'s details and quick actions', (tester) async {
    await pump(tester);
    expect(find.text('Vidyagram'), findsWidgets);
    expect(find.textContaining('com.example.vidya'), findsOneWidget);
    expect(find.textContaining('SKU VG1'), findsOneWidget);
    expect(find.textContaining('Apple ID A1'), findsOneWidget);
    expect(find.textContaining('Version 1.1.16'), findsOneWidget);
    expect(find.text('Ready for sale'), findsOneWidget);
    expect(find.text('View on App Store'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Upload .IPA'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);
  });

  testWidgets('the tabs come in the specified order', (tester) async {
    await pump(tester);
    final labels = ['Store Listing', 'TestFlight & Groups', 'Customer Reviews', 'Builds', 'Upload .IPA', 'In-App Purchases', 'App Review Preflight'];
    final xs = [for (final l in labels) tester.getTopLeft(find.descendant(of: find.byType(SegmentedTabs), matching: find.text(l))).dx];
    expect([...xs]..sort(), xs, reason: 'left to right in the order given');
    expect(find.text('Versions'), findsNothing);
  });

  testWidgets('"Upload .IPA" in the header jumps to the upload tab for this app', (tester) async {
    final (fake, _) = await pump(tester);
    expect(find.byType(UploadTab), findsNothing, reason: 'it opens on the Store Listing tab');
    await tester.tap(find.widgetWithText(FilledButton, 'Upload .IPA'));
    await tester.pumpAndSettle();
    final tab = tester.widget<UploadTab>(find.byType(UploadTab));
    expect(tab.bundleId, 'com.example.vidya');
    expect(tab.appId, 'A1');
    expect(fake.log.where((r) => r.method != 'GET'), isEmpty, reason: 'switching tabs never writes');
  });

  testWidgets('the back link returns to the Apps list', (tester) async {
    final (_, events) = await pump(tester);
    await tester.tap(find.text('Applications'));
    expect(events, ['back']);
  });

  testWidgets('it can open straight on another tab', (tester) async {
    await pump(tester, tab: 2);
    expect(find.text('No customer reviews yet.'), findsOneWidget);
  });
}
