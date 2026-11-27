import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/ui/pages/apps_page.dart';
import 'package:appstore_dashboard/ui/shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> a, [Map<String, dynamic> rel = const {}]) => {
  'type': type,
  'id': id,
  'attributes': a,
  'relationships': rel,
};

Map<String, dynamic> appsResponse() => {
  'data': [
    res(
      'apps',
      'A1',
      {'name': 'Vidyagram', 'bundleId': 'com.example.vidya', 'sku': 'VG1'},
      {
        'appStoreVersions': {
          'data': [
            {'type': 'appStoreVersions', 'id': 'V3'},
            {'type': 'appStoreVersions', 'id': 'V2'},
          ],
        },
      },
    ),
    res(
      'apps',
      'A2',
      {'name': 'Mac Notes', 'bundleId': 'com.example.notes', 'sku': 'MN1'},
      {
        'appStoreVersions': {
          'data': [
            {'type': 'appStoreVersions', 'id': 'V9'},
          ],
        },
      },
    ),
    res(
      'apps',
      'A3',
      {'name': 'Empty App', 'bundleId': 'com.example.empty', 'sku': 'EA1'},
      {
        'appStoreVersions': {'data': []},
      },
    ),
  ],
  'included': [
    res('appStoreVersions', 'V3', {'versionString': '2.0.0', 'appStoreState': 'WAITING_FOR_REVIEW', 'platform': 'IOS'}),
    res('appStoreVersions', 'V2', {'versionString': '1.9.0', 'appStoreState': 'READY_FOR_SALE', 'platform': 'IOS'}),
    res('appStoreVersions', 'V9', {'versionString': '3.1.0', 'appStoreState': 'READY_FOR_SALE', 'platform': 'MAC_OS'}),
  ],
};

FakeAsc account() => FakeAsc((r) => r.method == 'GET' && r.path.split('?').first == '/v1/apps' ? json(appsResponse()) : null);

Future<(FakeAsc, List<AppSummary>)> pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = account();
  final opened = <AppSummary>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppsPage(store: AppsStore(fake.client), onOpen: opened.add),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, opened);
}

void main() {
  testWidgets('the Apps page makes exactly one request, asking for the versions to be included', (tester) async {
    final (fake, _) = await pump(tester);
    expect(fake.log, hasLength(1), reason: 'no per-app calls for builds, versions, icons or reviews');
    final r = fake.log.single;
    expect(r.method, 'GET');
    expect(r.path, startsWith('/v1/apps?'));
    expect(Uri.splitQueryString(r.path.split('?').last)['include'], 'appStoreVersions');
    expect(find.text('Vidyagram'), findsOneWidget);
    expect(find.text('Mac Notes'), findsOneWidget);
  });

  testWidgets('each card shows the newest version and its status, and no rating or build number', (tester) async {
    await pump(tester);
    expect(find.text('Version 2.0.0'), findsOneWidget, reason: 'the first version Apple lists is the newest');
    expect(find.text('SKU VG1'), findsOneWidget);
    expect(find.text('Manage'), findsWidgets);
    expect(find.text('Waiting for review'), findsOneWidget);
    expect(find.text('Ready for sale'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.textContaining('Build'), findsNothing);
    expect(find.textContaining('Upload'), findsNothing, reason: 'uploading an .ipa belongs inside an app');
    expect(find.text('1 API request'), findsNothing);
  });

  testWidgets('filters, search and the grid/list switch work on the data already loaded', (tester) async {
    final (fake, opened) = await pump(tester);
    await tester.tap(find.textContaining('In Review'));
    await tester.pump();
    expect(find.text('Vidyagram'), findsOneWidget);
    expect(find.text('Mac Notes'), findsNothing);

    await tester.tap(find.textContaining('Universal & macOS'));
    await tester.pump();
    expect(find.text('Mac Notes'), findsOneWidget);
    expect(find.text('Vidyagram'), findsNothing);

    await tester.tap(find.textContaining('All Apps'));
    await tester.enterText(find.byType(TextField), 'empty');
    await tester.pump();
    expect(find.text('Empty App'), findsOneWidget);
    expect(find.text('Vidyagram'), findsNothing);

    await tester.tap(find.byTooltip('List'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empty App'));
    expect(opened.single.name, 'Empty App');
    expect(fake.log, hasLength(1), reason: 'none of that may cost another request');
  });

  test('an app with no versions still lists, with no status', () {
    final apps = summarizeApps(ResourcePage.fromJson(appsResponse()));
    expect(apps.map((a) => a.versionString), ['2.0.0', '3.1.0', null]);
    expect(apps.last.state, isNull);
  });

  test('the store loads once and shares the result; refresh asks again', () async {
    final fake = account();
    final store = AppsStore(fake.client);
    await store.apps;
    await store.apps;
    expect(fake.log, hasLength(1));
    await store.refresh();
    expect(fake.log, hasLength(2));
  });

  test('the sidebar has exactly five destinations and no TestFlight', () {
    expect(shellDestinationLabels, ['Apps', 'Sales & Trends', 'Analytics', 'Signing', 'Users and Access']);
  });
}
