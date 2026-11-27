import 'package:appstore_dashboard/api/listing_draft.dart';
import 'package:appstore_dashboard/api/submission.dart';
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

  testWidgets('a version with App Review says so calmly: no failed check, no submit button, and the header hears the new state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? newest;
    // Apple can still read the version back as prepare-for-submission right after submitting.
    final fake = FakeAsc((r) {
      if (r.method != 'GET') return null;
      final p = r.path.split('?').first;
      if (p == '/v1/apps/APP/appStoreVersions') {
        return json({
          'data': [
            res('appStoreVersions', 'V1', {'versionString': '2.1.0', 'appStoreState': 'PREPARE_FOR_SUBMISSION', 'platform': 'IOS'}),
          ],
        });
      }
      if (p == '/v1/reviewSubmissions') {
        return json({
          'data': [
            res('reviewSubmissions', 'S1', {'state': 'WAITING_FOR_REVIEW'}),
          ],
        });
      }
      if (p == '/v1/reviewSubmissions/S1/items') {
        return json({
          'data': [
            res(
              'reviewSubmissionItems',
              'I1',
              {'state': 'READY_FOR_REVIEW'},
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
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmitTab(
            client: fake.client,
            appId: 'APP',
            draft: ListingDraft(libraryId: 'APP'),
            onNewestVersion: (v) => newest = v.str('versionString'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('In the review queue'), findsOneWidget);
    expect(find.textContaining('With App Review'), findsOneWidget);
    expect(find.text('Already submitted'), findsNothing);
    expect(find.text('Version can be submitted'), findsNothing, reason: 'the stale prepare-for-submission state is not repeated');
    expect(find.text('Submit 2.1.0 for review'), findsNothing);
    expect(find.textContaining('to fix first'), findsNothing);
    expect(newest, '2.1.0');
  });

  test('release request body and where a version stands after review', () {
    expect(releaseRequestBody('V1'), {
      'data': {
        'type': 'appStoreVersionReleaseRequests',
        'relationships': {
          'appStoreVersion': {
            'data': {'type': 'appStoreVersions', 'id': 'V1'},
          },
        },
      },
    });
    expect(releaseStageOf('PENDING_DEVELOPER_RELEASE'), ReleaseStage.waitingForYou);
    expect(releaseStageOf('PENDING_APPLE_RELEASE'), ReleaseStage.scheduled);
    expect(releaseStageOf('PROCESSING_FOR_APP_STORE'), ReleaseStage.releasing);
    expect(releaseStageOf('READY_FOR_SALE'), ReleaseStage.live);
    expect(releaseStageOf('WAITING_FOR_REVIEW'), ReleaseStage.notApproved);
    expect(releaseStageOf(null), ReleaseStage.notApproved);
  });

  testWidgets('an approved version offers Release instead of the checklist, and releases only after confirming', (tester) async {
    tester.view.physicalSize = const Size(1300, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (r.method == 'POST' && p == '/v1/appStoreVersionReleaseRequests') {
        return json({'data': res('appStoreVersionReleaseRequests', 'RR1', {})}, 201);
      }
      if (r.method != 'GET') return null;
      if (p == '/v1/apps/APP/appStoreVersions') {
        return json({
          'data': [
            res('appStoreVersions', 'V1', {'versionString': '1.1.17', 'appStoreState': 'PENDING_DEVELOPER_RELEASE', 'platform': 'IOS'}),
          ],
        });
      }
      return json({'data': []});
    });
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

    expect(find.text('Approved · ready to release'), findsOneWidget);
    expect(find.text('Release 1.1.17'), findsOneWidget);
    expect(find.text('Submit 1.1.17 for review'), findsNothing);
    expect(find.textContaining('to fix first'), findsNothing);
    expect(find.text('Phased Release'), findsOneWidget);

    // Backing out sends nothing.
    await tester.tap(find.text('Release 1.1.17'));
    await tester.pumpAndSettle();
    expect(find.text('Release 1.1.17 to the App Store?'), findsOneWidget);
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(fake.log.where((r) => r.method != 'GET'), isEmpty);

    await tester.tap(find.text('Release 1.1.17'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Release'));
    await tester.pumpAndSettle();
    final writes = fake.log.where((r) => r.method != 'GET').toList();
    expect(writes.map((r) => '${r.method} ${r.path}'), ['POST /v1/appStoreVersionReleaseRequests']);
    expect(((writes.single.body!['data'] as Map)['relationships'] as Map)['appStoreVersion'], {
      'data': {'type': 'appStoreVersions', 'id': 'V1'},
    });

    // Apple still reads the version back as pending developer release: no second Release button.
    expect(find.text('Release requested'), findsOneWidget);
    expect(find.text('Release 1.1.17'), findsNothing);
  });
}
