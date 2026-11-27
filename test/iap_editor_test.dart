import 'package:appstore_dashboard/api/iap_editor.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/ui/pages/iap_editor.dart';
import 'package:appstore_dashboard/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> attrs, [Map<String, dynamic> rels = const {}]) => {
  'type': type,
  'id': id,
  'attributes': attrs,
  'relationships': rels,
};

Map<String, dynamic> rel(String type, String id) => {
  'data': {'type': type, 'id': id},
};

/// An in-app purchase as Apple returns it: one localization, a USD price, on sale in two of three territories, no
/// review screenshot. Writes are answered so a save can run; anything else fails the test.
FakeAsc fakeIap({String state = 'READY_TO_SUBMIT', bool family = false}) => FakeAsc((r) {
  final p = r.path;
  if (r.method == 'GET') {
    if (p.startsWith('/v2/inAppPurchases/I1/inAppPurchaseLocalizations')) {
      return json({
        'data': [
          res('inAppPurchaseLocalizations', 'L1', {
            'locale': 'en-US',
            'name': 'Pro Lifetime',
            'description': 'Unlock every Pro feature.',
            'state': 'APPROVED',
          }),
        ],
      });
    }
    if (p.startsWith('/v2/inAppPurchases/I1/iapPriceSchedule')) {
      return json({
        'data': res('inAppPurchasePriceSchedules', 'I1', {}, {'baseTerritory': rel('territories', 'USA')}),
        'included': [
          res('territories', 'USA', {'currency': 'USD'}),
        ],
      });
    }
    if (p.startsWith('/v1/inAppPurchasePriceSchedules/I1/manualPrices')) {
      return json({
        'data': [
          res(
            'inAppPurchasePrices',
            'P1',
            {'startDate': null, 'endDate': null},
            {'territory': rel('territories', 'USA'), 'inAppPurchasePricePoint': rel('inAppPurchasePricePoints', 'PP1')},
          ),
        ],
        'included': [
          res('inAppPurchasePricePoints', 'PP1', {'customerPrice': '9.99', 'proceeds': '8.49'}),
        ],
      });
    }
    if (p.startsWith('/v2/inAppPurchases/I1/inAppPurchaseAvailability')) {
      return json({
        'data': res('inAppPurchaseAvailabilities', 'AV1', {'availableInNewTerritories': true}),
      });
    }
    if (p.startsWith('/v1/inAppPurchaseAvailabilities/AV1/availableTerritories')) {
      return json({
        'data': [res('territories', 'USA', {}), res('territories', 'GBR', {})],
      });
    }
    if (p.startsWith('/v2/inAppPurchases/I1/appStoreReviewScreenshot')) return json({'data': null});
    if (p.startsWith('/v1/territories')) {
      return json({
        'data': [
          res('territories', 'USA', {'currency': 'USD'}),
          res('territories', 'GBR', {'currency': 'GBP'}),
          res('territories', 'CHN', {'currency': 'CNY'}),
        ],
      });
    }
    if (p.startsWith('/v2/inAppPurchases/I1')) {
      return json({
        'data': res('inAppPurchases', 'I1', {
          'name': 'Pro Lifetime',
          'productId': 'com.acme.notes.pro.lifetime',
          'inAppPurchaseType': 'NON_CONSUMABLE',
          'state': state,
          'reviewNote': '',
          'familySharable': family,
        }),
      });
    }
  }
  if (r.method == 'PATCH') return json({'data': res('x', 'x', {})});
  if (r.method == 'POST' && p == '/v1/inAppPurchaseLocalizations') return json({'data': res('inAppPurchaseLocalizations', 'L2', {})}, 201);
  if (r.method == 'POST') return json({'data': res('x', 'x', {})}, 201);
  if (r.method == 'DELETE') return noContent();
  return null;
});

void main() {
  test('bodies match the App Store Connect schema', () {
    expect(iapUpdateBody('I1', name: 'Pro'), {
      'data': {
        'type': 'inAppPurchases',
        'id': 'I1',
        'attributes': {'name': 'Pro'},
      },
    });
    expect(iapLocalizationUpdateBody('L1', name: 'N', description: 'D')['data'], {
      'type': 'inAppPurchaseLocalizations',
      'id': 'L1',
      'attributes': {'name': 'N', 'description': 'D'},
    });
    final create = iapLocalizationCreateBody('I1', locale: 'de-DE', name: 'N', description: 'D')['data'] as Map;
    expect(create['attributes'], {'name': 'N', 'locale': 'de-DE', 'description': 'D'});
    expect((create['relationships'] as Map)['inAppPurchaseV2'], rel('inAppPurchases', 'I1'));
    expect(iapScreenshotCommitBody('S1', 'abc')['data'], {
      'type': 'inAppPurchaseAppStoreReviewScreenshots',
      'id': 'S1',
      'attributes': {'uploaded': true, 'sourceFileChecksum': 'abc'},
    });
    expect(((iapSubmissionBody('I1')['data'] as Map)['relationships'] as Map)['inAppPurchaseV2'], rel('inAppPurchases', 'I1'));
  });

  test('loads the purchase, its localizations, price, availability and screenshot', () async {
    final d = await loadIapDetails(fakeIap().client, 'I1');
    expect(d.productId, 'com.acme.notes.pro.lifetime');
    expect(d.localizations.single.str('locale'), 'en-US');
    expect(d.baseTerritory, 'USA');
    expect(d.currency, 'USD');
    expect(d.currentPrice?.customerPrice, '9.99');
    expect(d.currentPrice?.proceeds, '8.49');
    expect(d.manualPriceCount, 1);
    expect(d.available, {'USA', 'GBR'});
    expect(d.availableInNewTerritories, isTrue);
    expect(d.allTerritories, ['CHN', 'GBR', 'USA']);
    expect(d.screenshot, isNull);
  });

  test('the draft lists each change and the checklist blocks on a missing screenshot', () async {
    final d = IapDraft(await loadIapDetails(fakeIap().client, 'I1'));
    expect(d.dirty, isFalse);
    expect(d.checks.where((c) => c.level == IapCheckLevel.bad).map((c) => c.label), ['App Review screenshot missing']);

    d.name = 'Pro Forever';
    d.locs.single.description = 'Everything, forever.';
    d.territories = {'USA'};
    expect(d.changes, ['Reference name', 'en-US description', 'Availability']);
    expect(d.checks.where((c) => c.level == IapCheckLevel.warn), hasLength(3));

    d.discard();
    expect(d.dirty, isFalse);
    expect(d.name, 'Pro Lifetime');
    expect(d.territories, {'USA', 'GBR'});
  });

  test('save sends only what changed, in order, and nothing else', () async {
    final f = fakeIap();
    final d = IapDraft(await loadIapDetails(f.client, 'I1'));
    f.log.clear();
    d.name = 'Pro Forever';
    d.locs.add(
      IapLocDraft(locale: 'de-DE', savedName: '', savedDescription: '')
        ..name = 'Pro für immer'
        ..description = 'Alles freischalten.',
    );
    d.inNew = false;
    d.newPrice = Resource(
      id: 'PP2',
      type: 'inAppPurchasePricePoints',
      attributes: {'customerPrice': '12.99', 'proceeds': '11.04'},
      relationships: const {},
    );

    await IapSaver(f.client).save(d);

    expect(f.log.map((r) => '${r.method} ${r.path}'), [
      'PATCH /v2/inAppPurchases/I1',
      'POST /v1/inAppPurchaseLocalizations',
      'POST /v1/inAppPurchasePriceSchedules',
      'POST /v1/inAppPurchaseAvailabilities',
    ]);
    expect((f.log[0].body!['data'] as Map)['attributes'], {'name': 'Pro Forever'});
    final avail = f.log[3].body!['data'] as Map;
    expect((avail['attributes'] as Map)['availableInNewTerritories'], isFalse);
    expect(((avail['relationships'] as Map)['availableTerritories'] as Map)['data'], [
      {'type': 'territories', 'id': 'GBR'},
      {'type': 'territories', 'id': 'USA'},
    ]);
    expect(d.dirty, isFalse);
    expect(d.locs.firstWhere((l) => l.locale == 'de-DE').id, 'L2');
  });

  test('a failed step keeps the later changes unsaved and names the step', () async {
    final base = fakeIap();
    final f = FakeAsc(
      (r) => r.method == 'PATCH' && r.path.startsWith('/v1/inAppPurchaseLocalizations')
          ? apiError(409, 'Conflict', 'Locked')
          : base.responder(r),
    );
    final d = IapDraft(await loadIapDetails(f.client, 'I1'));
    d.name = 'Pro Forever';
    d.locs.single.name = 'Pro';
    d.inNew = false;

    await expectLater(IapSaver(f.client).save(d), throwsA(predicate((e) => '$e'.contains('en-US localization failed'))));
    expect(d.changes, ['en-US display name', 'Availability']);
  });

  testWidgets('the editor shows the purchase and marks unsaved edits', (tester) async {
    tester.view.physicalSize = const Size(1500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = fakeIap();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: IapEditor(client: f.client, iapId: 'I1', onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('com.acme.notes.pro.lifetime'), findsOneWidget);
    expect(find.text('USD 9.99'), findsOneWidget);
    expect(find.text('Available in 2 of 3 territories'), findsOneWidget);
    expect(find.text('Not available: ${'China mainland'}'), findsOneWidget);
    expect(find.text('App Review screenshot missing'), findsOneWidget);
    expect(find.text('Fix 1 issue first'), findsOneWidget);
    expect(find.textContaining('unsaved change'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Pro Lifetime').first, 'Pro Forever');
    await tester.pump();
    expect(find.text('1 unsaved change · nothing is sent to Apple until you save'), findsOneWidget);
    expect(find.text('Save changes first'), findsOneWidget);
    expect(f.log.where((r) => r.method != 'GET'), isEmpty);

    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(find.textContaining('unsaved change'), findsNothing);
  });
}
