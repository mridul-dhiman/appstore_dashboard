import 'package:appstore_dashboard/api/listing_draft.dart';
import 'package:appstore_dashboard/ui/pages/listing_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

/// A mock App Store Connect with ONE editable version (the real account has none), serving just what the Listing tab reads.
FakeAsc editableAccount() => FakeAsc((r) {
  final p = r.path.split('?').first;
  Map<String, dynamic> res(String type, String id, Map<String, dynamic> a, [Map<String, dynamic> rel = const {}]) => {
    'type': type,
    'id': id,
    'attributes': a,
    'relationships': rel,
  };
  if (r.method != 'GET') return null; // any write in these tests would be a bug: nothing is applied
  if (p == '/v1/apps/APP/appStoreVersions') {
    return json({
      'data': [
        res('appStoreVersions', 'V1', {'versionString': '2.0.0', 'appStoreState': 'PREPARE_FOR_SUBMISSION'}),
      ],
    });
  }
  if (p == '/v1/apps/APP/appInfos') {
    return json({
      'data': [
        res('appInfos', 'I1', {'appStoreState': 'PREPARE_FOR_SUBMISSION'}),
      ],
    });
  }
  if (p == '/v1/appInfos/I1/appInfoLocalizations') {
    return json({
      'data': [
        res('appInfoLocalizations', 'IL1', {'locale': 'en-US', 'name': 'Demo', 'subtitle': 'Sub'}),
      ],
    });
  }
  if (p == '/v1/appStoreVersions/V1/appStoreVersionLocalizations') {
    return json({
      'data': [
        res('appStoreVersionLocalizations', 'L1', {
          'locale': 'en-US',
          'description': 'Old description',
          'keywords': 'a,b',
          'whatsNew': 'Old news',
        }),
      ],
    });
  }
  if (p == '/v1/appStoreVersionLocalizations/L1/placements') {
    Map<String, dynamic> placement(String id, String img) => res(
      'appAssetLibraryPlacements',
      id,
      {'placementType': 'APP_SCREENSHOT', 'placementGroup': 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE'},
      {
        'image': {
          'data': {'type': 'appAssetLibraryImages', 'id': img},
        },
      },
    );
    return json({
      'data': [placement('PA', 'A'), placement('PB', 'B')],
      'included': [
        res('appAssetLibraryImages', 'A', {'fileName': 'A.png'}),
        res('appAssetLibraryImages', 'B', {'fileName': 'B.png'}),
      ],
    });
  }
  if (p == '/v1/appAssetLibraryRefData') {
    return json({
      'data': [
        res('appAssetLibraryRefData', '1', {
          'imageSpecs': [
            {
              'specId': 's1',
              'dimensions': {'minWidth': 1290, 'maxWidth': 1290, 'minHeight': 2796, 'maxHeight': 2796},
            },
            {
              'specId': 's2',
              'dimensions': {'minWidth': 2064, 'maxWidth': 2064, 'minHeight': 2752, 'maxHeight': 2752},
            },
          ],
          'placementTypes': [
            {
              'placementTypeId': 'APP_SCREENSHOT',
              'specMappings': [
                {
                  'placementGroupId': 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE',
                  'specs': ['s1'],
                },
                {
                  'placementGroupId': 'IPAD_13_PROFILE',
                  'specs': ['s2'],
                },
              ],
            },
          ],
        }),
      ],
    });
  }
  return null;
});

Future<(FakeAsc, ListingDraft)> pumpTab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = editableAccount();
  final draft = ListingDraft(libraryId: 'APP');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListingTab(client: fake.client, appId: 'APP', draft: draft),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (fake, draft);
}

void main() {
  testWidgets('an editable version shows editable fields and screenshot controls', (tester) async {
    await pumpTab(tester);
    expect(find.text('Changes are staged locally and sent when you apply the changelist.'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('iPhone Dynamic Island Large'), findsOneWidget);
    expect(find.text('2 / 10'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsNWidgets(2));
    expect(find.byTooltip('Move right'), findsNWidgets(2));
    expect(find.text('Add a device size'), findsOneWidget);
    expect(find.textContaining('pending change'), findsNothing);
  });

  testWidgets('removing a screenshot and editing text stage changes; nothing is sent until applied', (tester) async {
    final (fake, draft) = await pumpTab(tester);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump();
    expect(find.text('1 pending change'), findsOneWidget);
    expect(find.text('Removed'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Old news'), 'Bug fixes and speed');
    await tester.pump();
    expect(draft.count, 2);
    expect(find.textContaining('2 pending changes'), findsOneWidget);
    expect(fake.log.where((r) => r.method != 'GET'), isEmpty, reason: 'staging must not write anything');
  });

  testWidgets('reordering shows a new-order change, and moving back clears it', (tester) async {
    final (_, draft) = await pumpTab(tester);
    await tester.tap(find.byTooltip('Move right').first);
    await tester.pump();
    expect(draft.changes().single.kind, ChangeKind.shotOrder);
    await tester.tap(find.byTooltip('Move left').last);
    await tester.pump();
    expect(draft.isEmpty, isTrue);
    expect(find.textContaining('pending change'), findsNothing);
  });

  testWidgets('the changelist dialog lists each change; Discard all reverts the field text', (tester) async {
    final (_, draft) = await pumpTab(tester);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.enterText(find.widgetWithText(TextField, 'Old description'), 'New description');
    await tester.pump();
    await tester.tap(find.text('Review changelist'));
    await tester.pumpAndSettle();
    expect(find.text('Changelist · 2 changes'), findsOneWidget);
    expect(find.text('en-US'), findsWidgets);
    expect(find.textContaining('remove A.png'), findsOneWidget);
    expect(find.text('Description'), findsWidgets);
    expect(find.text('Old description'), findsWidgets); // before side of the diff

    await tester.tap(find.text('Discard all').last);
    await tester.pumpAndSettle();
    expect(draft.isEmpty, isTrue);
    expect(find.widgetWithText(TextField, 'Old description'), findsOneWidget, reason: 'the field must go back to the server text');
    expect(find.textContaining('pending change'), findsNothing);
  });

  testWidgets('a long description change is shown as a line diff', (tester) async {
    await pumpTab(tester);
    final field = find.widgetWithText(TextField, 'Old description');
    await tester.enterText(field, 'Line one\nLine two\nLine three');
    await tester.pump();
    await tester.tap(find.text('Review changelist'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+3 −1 lines'), findsOneWidget);
    expect(find.textContaining('+ Line two'), findsOneWidget);
    expect(find.textContaining('- Old description'), findsOneWidget);
  });

  testWidgets('an edited field is marked Modified, shows the live text, and Revert un-stages it', (tester) async {
    final (_, draft) = await pumpTab(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Old description'), 'New description');
    await tester.pump();
    expect(find.text('Modified'), findsOneWidget);
    expect(find.text('Old description'), findsOneWidget, reason: 'the live text, struck through under the field');

    await tester.tap(find.text('Revert'));
    await tester.pump();
    expect(draft.isEmpty, isTrue);
    expect(find.text('Modified'), findsNothing);
    expect(find.widgetWithText(TextField, 'Old description'), findsOneWidget);
  });
}
