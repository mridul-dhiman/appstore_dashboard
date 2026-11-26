import 'package:appstore_dashboard/api/draft_submission.dart';
import 'package:appstore_dashboard/ui/pages/draft_submission_tab.dart';
import 'package:appstore_dashboard/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// An app with a draft holding version 1.2.0 (build 42) and an event still in draft, plus a ready product page, a
/// ready in-app purchase and one completed submission. With [withDraft] false there is no draft yet.
FakeAsc fakeApp({bool withDraft = true}) => FakeAsc((r) {
  final p = r.path;
  if (r.method == 'GET') {
    if (p.startsWith('/v1/reviewSubmissions/D1/items')) {
      return json({
        'data': [
          res('reviewSubmissionItems', 'IT1', {'state': 'READY_FOR_REVIEW'}, {'appStoreVersion': rel('appStoreVersions', 'V2')}),
          res('reviewSubmissionItems', 'IT2', {'state': 'READY_FOR_REVIEW'}, {'appEvent': rel('appEvents', 'E1')}),
        ],
        'included': [
          res('appStoreVersions', 'V2', {'versionString': '1.2.0', 'appStoreState': 'PREPARE_FOR_SUBMISSION'}),
          res('appEvents', 'E1', {'referenceName': 'Winter Writing Challenge', 'eventState': 'DRAFT'}),
        ],
      });
    }
    if (p.startsWith('/v1/reviewSubmissions/R1/items')) {
      return json({
        'data': [
          res('reviewSubmissionItems', 'RI1', {'state': 'READY_FOR_REVIEW'}, {'appStoreVersion': rel('appStoreVersions', 'V1')}),
        ],
        'included': [
          res('appStoreVersions', 'V1', {'versionString': '1.1.0', 'appStoreState': 'WAITING_FOR_REVIEW'}),
        ],
      });
    }
    if (p.startsWith('/v1/reviewSubmissions/S0/items')) {
      return json({
        'data': [
          res('reviewSubmissionItems', 'SI1', {'state': 'APPROVED'}, {'appStoreVersion': rel('appStoreVersions', 'V0')}),
        ],
        'included': [
          res('appStoreVersions', 'V0', {'versionString': '1.0.0', 'appStoreState': 'READY_FOR_SALE'}),
        ],
      });
    }
    if (p.contains('/appStoreVersions/V0/build')) return json({'data': res('builds', 'B1', {'version': '1'})});
    if (p.startsWith('/v1/reviewSubmissions')) {
      return json({
        'data': [
          if (withDraft) res('reviewSubmissions', 'D1', {'platform': 'IOS', 'state': 'READY_FOR_REVIEW'}),
          res('reviewSubmissions', 'S1', {'platform': 'IOS', 'state': 'CANCELING', 'submittedDate': '2026-10-01T10:00:00Z'}),
          res('reviewSubmissions', 'R1', {'platform': 'IOS', 'state': 'WAITING_FOR_REVIEW', 'submittedDate': '2026-11-25T10:00:00Z'}),
          res('reviewSubmissions', 'S0', {'platform': 'IOS', 'state': 'COMPLETE', 'submittedDate': '2026-11-12T10:00:00Z'}, {
            'submittedByActor': rel('actors', 'A1'),
          }),
        ],
        'included': [
          res('actors', 'A1', {'actorType': 'USER', 'userFirstName': 'Sam', 'userLastName': 'Lee'}),
        ],
      });
    }
    if (p.startsWith('/v1/apps/APP/appStoreVersions')) {
      return json({
        'data': [
          res('appStoreVersions', 'V2', {'versionString': '1.2.0', 'appStoreState': 'PREPARE_FOR_SUBMISSION'}, {'build': rel('builds', 'B42')}),
          res('appStoreVersions', 'V1', {'versionString': '1.1.0', 'appStoreState': 'READY_FOR_SALE'}),
        ],
        'included': [
          res('builds', 'B42', {'version': '42', 'processingState': 'VALID'}),
        ],
      });
    }
    if (p.startsWith('/v1/apps/APP/appEvents')) {
      return json({
        'data': [
          res('appEvents', 'E1', {'referenceName': 'Winter Writing Challenge', 'eventState': 'DRAFT'}),
        ],
      });
    }
    if (p.startsWith('/v1/apps/APP/appCustomProductPages')) {
      return json({
        'data': [
          res('appCustomProductPages', 'CP1', {'name': 'Students'}, {
            'appCustomProductPageVersions': {
              'data': [
                {'type': 'appCustomProductPageVersions', 'id': 'CPV1'},
              ],
            },
          }),
        ],
        'included': [
          res('appCustomProductPageVersions', 'CPV1', {'version': '1', 'state': 'READY_FOR_REVIEW'}),
        ],
      });
    }
    if (p.startsWith('/v1/apps/APP/inAppPurchasesV2')) {
      return json({
        'data': [
          res('inAppPurchases', 'I1', {'name': 'Coins 100', 'productId': 'com.acme.coins100', 'inAppPurchaseType': 'CONSUMABLE', 'state': 'READY_TO_SUBMIT'}),
        ],
      });
    }
    if (p.startsWith('/v1/appStoreVersions/')) return json({'data': null});
  }
  if (r.method == 'POST' && p == '/v1/reviewSubmissions') return json({'data': res('reviewSubmissions', 'D9', {'state': 'READY_FOR_REVIEW'})}, 201);
  if (r.method == 'POST') return json({'data': res('x', 'x', {})}, 201);
  if (r.method == 'PATCH') return json({'data': res('x', 'x', {})});
  if (r.method == 'DELETE') return noContent();
  return null;
});

void main() {
  test('item bodies point at the submission and the right relationship', () {
    final b = draftItemBody('D1', DraftItemKind.productPage, 'CPV1')['data'] as Map;
    expect(b['type'], 'reviewSubmissionItems');
    expect((b['relationships'] as Map)['reviewSubmission'], rel('reviewSubmissions', 'D1'));
    expect((b['relationships'] as Map)['appCustomProductPageVersion'], rel('appCustomProductPageVersions', 'CPV1'));
    expect(((draftItemBody('D1', DraftItemKind.event, 'E1')['data'] as Map)['relationships'] as Map)['appEvent'], rel('appEvents', 'E1'));
    expect(() => draftItemBody('D1', DraftItemKind.inAppPurchase, 'I1'), throwsArgumentError);
  });

  test('the overview reads the draft, what can be added and the history', () async {
    final d = await loadDraftOverview(fakeApp().client, 'APP');
    expect(d.draft?.id, 'D1');
    expect(d.items.map((i) => i.title), ['App Store Version · 1.2.0', 'In-App Event · Winter Writing Challenge']);
    expect(d.items.first.detail, 'Build 42');
    expect(d.items.first.ready, isTrue);
    expect(d.blocked.single.problem, 'Draft — complete it first');
    // Already in the draft: not offered again. The product page and the in-app purchase are.
    expect(d.addable.map((e) => '${e.kind.name}:${e.targetId}'), ['productPage:CPV1', 'inAppPurchase:I1']);
    // With App Review: loaded with its items. History: newest first, items loaded later.
    expect(d.open.single.id, 'R1');
    expect(d.open.single.items!.single.title, 'App Store Version · 1.1.0');
    expect(d.unresolved, isNull);
    expect(d.history.map((s) => s.id), ['S0', 'S1']);
    expect(d.history.first.by, 'Sam Lee');
    expect(d.history.first.items, isNull);
    expect(d.versionCount, 2);
  });

  test('without a draft, the ready version is offered and nothing is in the list', () async {
    final d = await loadDraftOverview(fakeApp(withDraft: false).client, 'APP');
    expect(d.draft, isNull);
    expect(d.items, isEmpty);
    expect(d.addable.first.kind, DraftItemKind.version);
    expect(d.addable.where((e) => e.kind == DraftItemKind.event).single.ready, isFalse);
  });

  test('actions send one request each, to the right place', () async {
    final f = fakeApp();
    final a = DraftActions(f.client, 'APP');
    final d = await loadDraftOverview(f.client, 'APP');
    f.log.clear();
    expect(await a.create('IOS'), 'D9');
    await a.add('D1', d.addable.first);
    await a.remove(d.items.last);
    await a.submit('D1');
    await a.cancel('D1');
    expect(f.log.map((r) => '${r.method} ${r.path}'), [
      'POST /v1/reviewSubmissions',
      'POST /v1/reviewSubmissionItems',
      'DELETE /v1/reviewSubmissionItems/IT2',
      'PATCH /v1/reviewSubmissions/D1',
      'PATCH /v1/reviewSubmissions/D1',
    ]);
    expect((f.log[3].body!['data'] as Map)['attributes'], {'submitted': true});
    expect((f.log[4].body!['data'] as Map)['attributes'], {'canceled': true});
  });

  testWidgets('the tab lists the items, blocks submitting while one needs attention, and sends nothing by itself', (tester) async {
    tester.view.physicalSize = const Size(1500, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = fakeApp();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: DraftSubmissionTab(client: f.client, appId: 'APP')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Draft submission · iOS'), findsOneWidget);
    expect(find.text('App Store Version · 1.2.0'), findsOneWidget);
    expect(find.text('In-App Event · Winter Writing Challenge'), findsOneWidget);
    expect(find.text('Fix or remove 1 item first'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.ancestor(of: find.text('Submit to App Review'), matching: find.byWidgetPredicate((w) => w is FilledButton))).onPressed, isNull);
    expect(find.textContaining('Students', findRichText: true), findsOneWidget);
    expect(find.text('With App Review'), findsOneWidget);
    expect(find.text('Submission history'), findsOneWidget);
    expect(find.textContaining('Version 1.1.0'), findsOneWidget);
    expect(find.text('App Store Version · 1.0.0'), findsNothing);

    // Opening a past submission loads what was in it.
    await tester.tap(find.textContaining('Submitted Nov 12, 2026'));
    await tester.pumpAndSettle();
    expect(find.text('App Store Version · 1.0.0'), findsOneWidget);
    expect(find.text('Build 1'), findsOneWidget);
    expect(f.log.where((r) => r.method != 'GET'), isEmpty);

    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('Add 1 selected'), findsOneWidget);
    expect(f.log.where((r) => r.method != 'GET'), isEmpty);
  });
}
