import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/api/testflight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

void main() {
  test('a new external group with a limited public link', () {
    final body = groupCreateBody('APP', const GroupSettings(name: ' Beta ', publicLink: true, limit: 50), internal: false);
    expect(body['data']['attributes'], {
      'name': 'Beta',
      'isInternalGroup': false,
      'feedbackEnabled': true,
      'publicLinkEnabled': true,
      'publicLinkLimitEnabled': true,
      'publicLinkLimit': 50,
    });
    expect(body['data']['relationships']['app']['data'], {'type': 'apps', 'id': 'APP'});
  });

  test('an internal group never sends public-link fields; it can have access to all builds', () {
    final a =
        groupCreateBody('APP', const GroupSettings(name: 'Team', publicLink: true, limit: 5), internal: true)['data']['attributes'] as Map;
    expect(a.containsKey('publicLinkEnabled'), isFalse);
    expect(a['hasAccessToAllBuilds'], isTrue);
    expect(a['isInternalGroup'], isTrue);
  });

  test('updates carry only what changed', () {
    const before = GroupSettings(name: 'A');
    final same = groupUpdateBody('G', before, const GroupSettings(name: 'A'), internal: false);
    expect(groupChanged(same), isFalse);
    final renamed = groupUpdateBody('G', before, const GroupSettings(name: 'B', feedback: false), internal: false);
    expect(renamed['data']['attributes'], {'name': 'B', 'feedbackEnabled': false});
    final link = groupUpdateBody('G', before, const GroupSettings(name: 'A', publicLink: true, limit: 20), internal: false);
    expect(link['data']['attributes'], {'publicLinkEnabled': true, 'publicLinkLimitEnabled': true, 'publicLinkLimit': 20});
  });

  test('group validation', () {
    expect(groupProblems(const GroupSettings(name: ' ')), ['Give the group a name.']);
    expect(groupProblems(const GroupSettings(name: 'x', publicLink: true, limit: 0)), isNotEmpty);
    expect(groupProblems(const GroupSettings(name: 'x', publicLink: true, limit: 10000)), isEmpty);
  });

  test('adding a tester creates them in the group; an existing tester (409) is looked up and linked', () async {
    final fresh = FakeAsc(
      (r) => json({
        'data': {'type': 'betaTesters', 'id': 'T1'},
      }, 201),
    );
    expect(await addTester(fresh.client, 'G1', email: 'a@b.co', firstName: 'A'), isFalse);
    expect(fresh.log.single.body!['data']['attributes'], {'email': 'a@b.co', 'firstName': 'A'});
    expect(fresh.log.single.body!['data']['relationships']['betaGroups']['data'], [
      {'type': 'betaGroups', 'id': 'G1'},
    ]);

    final existing = FakeAsc((r) {
      if (r.method == 'POST' && r.path == '/v1/betaTesters') return apiError(409, 'Conflict', 'exists');
      if (r.method == 'GET') {
        return json({
          'data': [
            {'type': 'betaTesters', 'id': 'T9', 'attributes': {}},
          ],
        });
      }
      if (r.path == '/v1/betaGroups/G1/relationships/betaTesters') return noContent();
      return null;
    });
    expect(await addTester(existing.client, 'G1', email: 'a@b.co'), isTrue);
    expect(existing.log.map((r) => '${r.method} ${r.path}').toList(), [
      'POST /v1/betaTesters',
      'GET /v1/betaTesters?filter%5Bemail%5D=a%40b.co&limit=1',
      'POST /v1/betaGroups/G1/relationships/betaTesters',
    ]);
    expect(existing.log.last.body!['data'], [
      {'type': 'betaTesters', 'id': 'T9'},
    ]);

    await expectLater(addTester(fresh.client, 'G1', email: 'nope'), throwsA(isA<AscException>()));
  });

  test('builds and testers are linked and unlinked with linkage bodies; beta review posts the build', () async {
    final fake = FakeAsc(
      (r) => r.method == 'POST' && r.path == '/v1/betaAppReviewSubmissions'
          ? json({
              'data': {'type': 'betaAppReviewSubmissions', 'id': 'S1'},
            }, 201)
          : noContent(),
    );
    await addBuildsToGroup(fake.client, 'G', ['B1', 'B2']);
    await removeBuildsFromGroup(fake.client, 'G', ['B1']);
    await removeTestersFromGroup(fake.client, 'G', ['T1']);
    await submitForBetaReview(fake.client, 'B2');
    await deleteGroup(fake.client, 'G');
    expect(fake.log.map((r) => '${r.method} ${r.path}').toList(), [
      'POST /v1/betaGroups/G/relationships/builds',
      'DELETE /v1/betaGroups/G/relationships/builds',
      'DELETE /v1/betaGroups/G/relationships/betaTesters',
      'POST /v1/betaAppReviewSubmissions',
      'DELETE /v1/betaGroups/G',
    ]);
    expect(fake.log[0].body!['data'], [
      {'type': 'builds', 'id': 'B1'},
      {'type': 'builds', 'id': 'B2'},
    ]);
    expect(fake.log[3].body!['data']['relationships']['build']['data'], {'type': 'builds', 'id': 'B2'});
  });

  test('expiring a build sends one PATCH with expired: true', () async {
    final fake = FakeAsc(
      (r) => json({
        'data': {'type': 'builds', 'id': 'B1'},
      }),
    );
    await expireBuild(fake.client, 'B1');
    expect(fake.log.single.method, 'PATCH');
    expect(fake.log.single.path, '/v1/builds/B1');
    expect(fake.log.single.body, {
      'data': {
        'type': 'builds',
        'id': 'B1',
        'attributes': {'expired': true},
      },
    });
  });

  group('build uploads', () {
    BuildUpload up(String short, String num, String state, String uploaded, {List<String> errors = const []}) => BuildUpload(
      Resource(
        id: 'U$num',
        type: 'buildUploads',
        attributes: {
          'cfBundleShortVersionString': short,
          'cfBundleVersion': num,
          'uploadedDate': uploaded,
          'state': {
            'state': state,
            'errors': [
              for (final e in errors) {'description': e},
            ],
          },
        },
        relationships: const {},
      ),
    );
    final now = DateTime.utc(2026, 11, 10, 12);

    test('state text and warnings come straight from Apple', () {
      final u = BuildUpload(
        Resource(
          id: 'U',
          type: 'buildUploads',
          relationships: const {},
          attributes: {
            'cfBundleShortVersionString': '1.0',
            'cfBundleVersion': '9',
            'state': {
              'state': 'PROCESSING',
              'errors': [],
              'warnings': [
                {'code': '90683', 'description': 'Missing purpose string'},
              ],
            },
          },
        ),
      );
      expect(u.stateLabel, 'Processing');
      expect(u.warnings, ['Missing purpose string']);
      expect(betaStateLabel('MISSING_EXPORT_COMPLIANCE'), 'Missing export compliance');
      expect(betaStateLabel('SOMETHING_NEW'), 'Something new');
      expect(betaStateLabel(null), '');
    });

    test('a processing upload is listed because /v1/builds does not have it yet', () {
      final u = up('2.0.0', '2', 'PROCESSING', '2026-11-10T11:00:00Z');
      expect(pendingUploads([u], {buildKey('2.0.0', '1')}, now: now), [u]);
      expect(u.processing, isTrue);
      expect(u.label, '2.0.0 (2)');
    });

    test('an upload that already became a build is not repeated, and the same build number under another version is not confused', () {
      final done = up('2.0.0', '1', 'COMPLETE', '2026-11-10T11:50:00Z');
      expect(pendingUploads([done], {buildKey('2.0.0', '1')}, now: now), isEmpty);
      final sameNumber = up('2.1.0', '1', 'PROCESSING', '2026-11-10T11:50:00Z');
      expect(pendingUploads([sameNumber], {buildKey('2.0.0', '1')}, now: now), [sameNumber]);
    });

    test('finished uploads only linger for an hour; failures for a week', () {
      expect(
        pendingUploads([up('1.0', '3', 'COMPLETE', '2026-11-10T11:30:00Z')], {}, now: now),
        hasLength(1),
        reason: 'Apple lags before the build appears',
      );
      expect(pendingUploads([up('1.0', '3', 'COMPLETE', '2026-11-10T09:00:00Z')], {}, now: now), isEmpty);
      final failed = up('1.0', '4', 'FAILED', '2026-11-05T09:00:00Z', errors: ['Invalid binary']);
      expect(pendingUploads([failed], {}, now: now), [failed]);
      expect(failed.errors, ['Invalid binary']);
      expect(pendingUploads([up('1.0', '5', 'FAILED', '2026-10-01T09:00:00Z')], {}, now: now), isEmpty);
    });
  });

  test('the app icon comes from the newest build\'s icon token, in one small request', () async {
    final fake = FakeAsc(
      (r) => json({
        'data': [
          {
            'type': 'builds',
            'id': 'B1',
            'attributes': {
              'iconAssetToken': {'templateUrl': 'https://is1-ssl.mzstatic.com/x/icon.png/{w}x{h}bb.{f}', 'width': 152, 'height': 152},
            },
          },
        ],
      }),
    );
    expect(await loadAppIconUrl(fake.client, 'A1'), 'https://is1-ssl.mzstatic.com/x/icon.png/128x128bb.png');
    expect(fake.log.single.path, contains('fields%5Bbuilds%5D=iconAssetToken'));
    expect(fake.log.single.path, contains('limit=1'));
    expect(await loadAppIconUrl(FakeAsc((r) => json({'data': []})).client, 'A1'), isNull);
  });
}
