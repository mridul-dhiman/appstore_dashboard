import 'package:appstore_dashboard/api/listing_draft.dart';
import 'package:appstore_dashboard/ui/pages/submit_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> a, [Map<String, dynamic> rel = const {}]) => {
  'type': type,
  'id': id,
  'attributes': a,
  'relationships': rel,
};

/// A rejected version with build 7 attached and build 8 waiting. Only reads are answered: any write fails the test.
FakeAsc rejectedApp() => FakeAsc((r) {
  if (r.method != 'GET') return null;
  final p = r.path.split('?').first;
  if (p == '/v1/apps/APP/appStoreVersions') {
    return json({
      'data': [
        res('appStoreVersions', 'V1', {'versionString': '2.1.0', 'appStoreState': 'REJECTED', 'releaseType': 'MANUAL', 'platform': 'IOS'}),
      ],
    });
  }
  if (p == '/v1/appStoreVersions/V1/build') {
    return json({
      'data': res('builds', 'B7', {'version': '7', 'processingState': 'VALID', 'expired': false, 'usesNonExemptEncryption': false}),
    });
  }
  if (p == '/v1/builds') {
    return json({
      'data': [
        res('builds', 'B8', {'version': '8', 'processingState': 'VALID', 'expired': false}),
        res('builds', 'B7', {'version': '7', 'processingState': 'VALID', 'expired': false}),
      ],
    });
  }
  if (p == '/v1/reviewSubmissions') {
    return json({
      'data': [
        res('reviewSubmissions', 'S1', {'state': 'UNRESOLVED_ISSUES'}),
      ],
    });
  }
  if (p == '/v1/reviewSubmissions/S1/items') {
    return json({
      'data': [
        res(
          'reviewSubmissionItems',
          'I1',
          {'state': 'REJECTED'},
          {
            'appStoreVersion': {
              'data': {'type': 'appStoreVersions', 'id': 'V1'},
            },
          },
        ),
      ],
    });
  }
  return json({'data': []});
});

void main() {
  testWidgets('a rejected version shows the rejection, offers reply and resubmit, and the build can be changed', (tester) async {
    tester.view.physicalSize = const Size(1300, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = rejectedApp();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmitTab(
            client: fake.client,
            appId: 'APP',
            draft: ListingDraft(libraryId: 'APP'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rejected by App Review'), findsWidgets);
    expect(find.text('Reply in review notes…'), findsOneWidget);
    expect(find.text('Resubmit for review'), findsOneWidget);
    expect(find.text('Resubmit 2.1.0 for review'), findsOneWidget);
    expect(find.text('Already submitted'), findsNothing);

    expect(find.text('Build 7'), findsOneWidget);
    await tester.tap(find.text('Change build'));
    await tester.pumpAndSettle();
    expect(find.text('Change the build'), findsOneWidget);
    expect(find.text('Build 8'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget, reason: 'the attached build is marked, not offered again');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reply in review notes…'));
    await tester.pumpAndSettle();
    expect(find.text('Save and resubmit…'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.log.where((r) => r.method != 'GET'), isEmpty, reason: 'looking around writes nothing');
  });
}
