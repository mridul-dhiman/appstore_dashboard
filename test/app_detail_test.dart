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
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AppDetailPage(client: fake.client, summary: summary(), initialTab: tab, onBack: () => events.add('back')),
      ),
    ),
  );
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
    final labels = [
      'Store Listing',
      'TestFlight & Groups',
      'Customer Reviews',
      'Builds',
      'Upload .IPA',
      'In-App Purchases',
      'App Review Preflight',
    ];
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

  testWidgets('Expire asks first, sends nothing on Cancel, and PATCHes expired on confirm; expired builds have no button', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var expired = false;
    final fake = FakeAsc((r) {
      if (r.method == 'PATCH') {
        expired = true;
        return json({
          'data': {'type': 'builds', 'id': 'B1'},
        });
      }
      if (r.path.startsWith('/v1/builds') && r.method == 'GET') {
        return json({
          'data': [
            {
              'type': 'builds',
              'id': 'B1',
              'attributes': {'version': '7', 'processingState': 'VALID', 'expired': expired, 'uploadedDate': '2026-01-01T00:00:00Z'},
            },
            {
              'type': 'builds',
              'id': 'B0',
              'attributes': {'version': '6', 'processingState': 'VALID', 'expired': true, 'uploadedDate': '2025-12-01T00:00:00Z'},
            },
          ],
        });
      }
      return r.method == 'GET' ? json({'data': []}) : null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDetailPage(client: fake.client, summary: summary(), initialTab: 3, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, 'Expire'), findsOneWidget, reason: 'only the unexpired build');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Expire'));
    await tester.pumpAndSettle();
    expect(find.textContaining('can not be undone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.log.where((r) => r.method == 'PATCH'), isEmpty);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Expire'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expire Build'));
    await tester.pumpAndSettle();
    final patches = fake.log.where((r) => r.method == 'PATCH').toList();
    expect(patches, hasLength(1));
    expect(patches.single.path, startsWith('/v1/builds/B1'));
    expect(find.widgetWithText(OutlinedButton, 'Expire'), findsNothing, reason: 'list reloaded, both now expired');
  });

  testWidgets('a build still processing at Apple is listed (it is only in buildUploads, not /v1/builds)', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeAsc((r) {
      if (r.path.startsWith('/v1/apps/A1/buildUploads')) {
        return json({
          'data': [
            {
              'type': 'buildUploads',
              'id': 'U2',
              'attributes': {
                'cfBundleShortVersionString': '2.0.0',
                'cfBundleVersion': '2',
                'uploadedDate': DateTime.now().toUtc().toIso8601String(),
                'state': {'state': 'PROCESSING', 'errors': []},
              },
            },
          ],
        });
      }
      if (r.path.startsWith('/v1/builds') && r.path.contains('buildBetaDetail')) {
        return json({
          'data': [
            {
              'type': 'builds',
              'id': 'B1',
              'attributes': {},
              'relationships': {
                'buildBetaDetail': {
                  'data': {'type': 'buildBetaDetails', 'id': 'D1'},
                },
              },
            },
          ],
          'included': [
            {
              'type': 'buildBetaDetails',
              'id': 'D1',
              'attributes': {'internalBuildState': 'IN_BETA_TESTING', 'externalBuildState': 'READY_FOR_BETA_SUBMISSION'},
            },
          ],
        });
      }
      if (r.path.startsWith('/v1/builds')) {
        return json({
          'data': [
            {
              'type': 'builds',
              'id': 'B1',
              'attributes': {'version': '1', 'processingState': 'VALID', 'expired': false, 'uploadedDate': '2026-01-01T00:00:00Z'},
              'relationships': {
                'preReleaseVersion': {
                  'data': {'type': 'preReleaseVersions', 'id': 'P1'},
                },
              },
            },
          ],
          'included': [
            {
              'type': 'preReleaseVersions',
              'id': 'P1',
              'attributes': {'version': '2.0.0'},
            },
          ],
        });
      }
      return r.method == 'GET' ? json({'data': []}) : null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDetailPage(client: fake.client, summary: summary(), initialTab: 3, onBack: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Version 2.0.0'), findsOneWidget, reason: 'the upload and the build share one version group');
    expect(find.text('2 builds'), findsOneWidget);
    expect(find.text('Build 2'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    expect(find.text('Build 1'), findsOneWidget, reason: 'the finished build is still listed, and not shown twice');
    expect(find.textContaining('refreshes by itself'), findsOneWidget);
    expect(find.textContaining('TestFlight: internal In testing · external Ready for beta review'), findsOneWidget);

    // Leave no pending poll timer behind.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a builds list Apple cut short says so', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeAsc((r) {
      if (r.path.startsWith('/v1/builds') && !r.path.contains('buildBetaDetail')) {
        return json({
          'data': [
            {
              'type': 'builds',
              'id': 'B1',
              'attributes': {'version': '1', 'processingState': 'VALID', 'expired': true, 'uploadedDate': '2026-01-01T00:00:00Z'},
            },
          ],
          'links': {'next': 'https://api.appstoreconnect.apple.com/v1/builds?cursor=abc'},
        });
      }
      return r.method == 'GET' ? json({'data': []}) : null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDetailPage(client: fake.client, summary: summary(), initialTab: 3, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Showing the first 1 builds'), findsOneWidget);
  });

  testWidgets('a processing build that finishes is announced, and the live build is marked', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var done = false;
    final fake = FakeAsc((r) {
      if (r.path.startsWith('/v1/apps/A1/buildUploads')) {
        return json({
          'data': [
            {
              'type': 'buildUploads',
              'id': 'U2',
              'attributes': {
                'cfBundleShortVersionString': '2.0.0',
                'cfBundleVersion': '2',
                'uploadedDate': DateTime.now().toUtc().toIso8601String(),
                'state': {'state': done ? 'COMPLETE' : 'PROCESSING', 'errors': []},
              },
            },
          ],
        });
      }
      if (r.path.startsWith('/v1/apps/A1/appStoreVersions')) {
        return json({
          'data': [
            {
              'type': 'appStoreVersions',
              'id': 'V2',
              'attributes': {'platform': 'IOS'},
              'relationships': {
                'build': {
                  'data': {'type': 'builds', 'id': 'B1'},
                },
              },
            },
            {
              'type': 'appStoreVersions',
              'id': 'V1',
              'attributes': {'platform': 'IOS'},
              'relationships': {
                'build': {
                  'data': {'type': 'builds', 'id': 'B0'},
                },
              },
            },
          ],
        });
      }
      if (r.path.startsWith('/v1/builds') && !r.path.contains('buildBetaDetail')) {
        return json({
          'data': [
            if (done)
              {
                'type': 'builds',
                'id': 'B2',
                'attributes': {'version': '2', 'processingState': 'VALID', 'expired': false},
                'relationships': {
                  'preReleaseVersion': {
                    'data': {'type': 'preReleaseVersions', 'id': 'P2'},
                  },
                },
              },
            {
              'type': 'builds',
              'id': 'B1',
              'attributes': {'version': '1', 'processingState': 'VALID', 'expired': false},
              'relationships': {
                'preReleaseVersion': {
                  'data': {'type': 'preReleaseVersions', 'id': 'P1'},
                },
              },
            },
            {
              'type': 'builds',
              'id': 'B0',
              'attributes': {'version': '9', 'processingState': 'VALID', 'expired': false},
              'relationships': {
                'preReleaseVersion': {
                  'data': {'type': 'preReleaseVersions', 'id': 'P0'},
                },
              },
            },
          ],
          'included': [
            {
              'type': 'preReleaseVersions',
              'id': 'P2',
              'attributes': {'version': '2.0.0'},
            },
            {
              'type': 'preReleaseVersions',
              'id': 'P1',
              'attributes': {'version': '1.9.0'},
            },
            {
              'type': 'preReleaseVersions',
              'id': 'P0',
              'attributes': {'version': '1.8.0'},
            },
          ],
        });
      }
      return r.method == 'GET' ? json({'data': []}) : null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDetailPage(client: fake.client, summary: summary(), initialTab: 3, onBack: () {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Live on App Store'), findsOneWidget, reason: 'only the newest release is live, not every READY_FOR_SALE one');
    expect(
      fake.log.where((r) => r.path.contains('READY_FOR_SALE')).single.path,
      contains('include=build'),
      reason: 'without it Apple sends no build linkage (seen on the real account)',
    );

    done = true;
    await tester.pump(const Duration(seconds: 21)); // the processing poll
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('2.0.0 (2) finished processing'), findsOneWidget);

    expect(find.text('Version 1.8.0'), findsOneWidget);
    expect(find.text('Build 9'), findsNothing, reason: 'older versions start collapsed; the newest and the live one are open');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Expire').at(1)); // the live 1.9.0 (1)
    await tester.pumpAndSettle();
    expect(find.textContaining('live on the App Store now'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Version 1.8.0'));
    await tester.pump();
    expect(find.text('Build 9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
