import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/api/submission.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Resource res(String type, String id, [Map<String, dynamic> attrs = const {}, Map<String, dynamic> rels = const {}]) =>
    Resource(id: id, type: type, attributes: attrs, relationships: rels);

Resource version({String state = 'PREPARE_FOR_SUBMISSION', String? releaseType = 'MANUAL'}) =>
    res('appStoreVersions', 'V1', {'versionString': '4.9.0', 'appStoreState': state, 'releaseType': releaseType});
Resource build({String processing = 'VALID', bool expired = false, Object? encryption = false}) =>
    res('builds', 'B1', {'version': '373', 'processingState': processing, 'expired': expired, 'usesNonExemptEncryption': encryption});
Resource loc({String locale = 'en-US', String desc = 'd', String kw = 'k', String support = 'https://x', String news = 'n'}) => res(
  'appStoreVersionLocalizations',
  'L-$locale',
  {'locale': locale, 'description': desc, 'keywords': kw, 'supportUrl': support, 'whatsNew': news},
);
Resource review({
  String first = 'A',
  String last = 'B',
  String phone = '1',
  String email = 'a@b.c',
  bool demo = false,
  String demoName = '',
  String demoPass = '',
}) => res('appStoreReviewDetails', 'R1', {
  'contactFirstName': first,
  'contactLastName': last,
  'contactPhone': phone,
  'contactEmail': email,
  'demoAccountRequired': demo,
  'demoAccountName': demoName,
  'demoAccountPassword': demoPass,
});

PreflightData good() =>
    PreflightData(version: version(), build: build(), localizations: [loc()], screenshotsByLoc: {'L-en-US': 3}, reviewDetail: review());
List<Check> fails(PreflightData d) => evaluatePreflight(d).where((c) => c.level == CheckLevel.fail).toList();

void main() {
  group('preflight', () {
    test('a complete version passes with no failures', () {
      final checks = evaluatePreflight(good());
      expect(canSubmit(checks), isTrue);
      expect(fails(good()), isEmpty);
    });

    test('a live (ready for sale) version cannot be submitted and points at creating a new one', () {
      final d = PreflightData(
        version: version(state: 'READY_FOR_SALE'),
        build: build(),
        localizations: [loc()],
        screenshotsByLoc: {'L-en-US': 1},
        reviewDetail: review(),
      );
      final f = fails(d);
      expect(f.single.title, 'Version is not submittable');
      expect(f.single.fix, CheckFix.version);
      expect(canSubmit(evaluatePreflight(d)), isFalse);
    });

    test('no build, expired build, unprocessed build each fail and offer the build fix', () {
      for (final b in [null, build(expired: true), build(processing: 'PROCESSING')]) {
        final d = PreflightData(
          version: version(),
          build: b,
          localizations: [loc()],
          screenshotsByLoc: {'L-en-US': 1},
          reviewDetail: review(),
        );
        final f = fails(d);
        expect(f, isNotEmpty);
        expect(f.first.fix, CheckFix.build);
      }
    });

    test('export compliance unanswered fails; answered passes', () {
      final bad = PreflightData(
        version: version(),
        build: build(encryption: null),
        localizations: [loc()],
        screenshotsByLoc: {'L-en-US': 1},
        reviewDetail: review(),
      );
      expect(fails(bad).single.fix, CheckFix.compliance);
    });

    test('each locale needs description, keywords, support URL and (for updates) what\'s new, plus a screenshot', () {
      final d = PreflightData(
        version: version(),
        build: build(),
        localizations: [
          loc(),
          loc(locale: 'hi', desc: '', kw: ' ', news: ''),
        ],
        screenshotsByLoc: {'L-en-US': 2, 'L-hi': 0},
        reviewDetail: review(),
      );
      final f = fails(d).map((c) => c.title).toList();
      expect(f, contains(allOf(startsWith('hi is missing'), contains('description'), contains('keywords'), contains("what's new"))));
      expect(f, contains('hi has no screenshots'));
      expect(f.any((t) => t.startsWith('en-US')), isFalse);
    });

    test("what's new is not required on a first version", () {
      final d = PreflightData(
        version: version(),
        build: build(),
        localizations: [loc(news: '')],
        screenshotsByLoc: {'L-en-US': 1},
        reviewDetail: review(),
        hasPriorVersion: false,
      );
      expect(fails(d), isEmpty);
    });

    test('review details: missing, partial, and demo account rules', () {
      PreflightData withReview(Resource? r) =>
          PreflightData(version: version(), build: build(), localizations: [loc()], screenshotsByLoc: {'L-en-US': 1}, reviewDetail: r);
      expect(fails(withReview(null)).single.fix, CheckFix.review);
      expect(fails(withReview(review(phone: ''))).single.title, contains('phone'));
      expect(fails(withReview(review(demo: true))).single.title, allOf(contains('demo account name'), contains('demo account password')));
      expect(fails(withReview(review(demo: true, demoName: 'u', demoPass: 'p'))), isEmpty);
    });

    test('a version already in a review submission cannot be submitted again; a draft does not block', () {
      final inReview = ActiveSubmission(res('reviewSubmissions', 'S1', {'state': 'IN_REVIEW'}), ['V1']);
      final draft = ActiveSubmission(res('reviewSubmissions', 'S2', {'state': 'READY_FOR_REVIEW'}), ['V1']);
      final base = good();
      PreflightData with_(List<ActiveSubmission> s) => PreflightData(
        version: base.version,
        build: base.build,
        localizations: base.localizations,
        screenshotsByLoc: base.screenshotsByLoc,
        reviewDetail: base.reviewDetail,
        submissions: s,
      );
      expect(fails(with_([inReview])).single.title, 'Already submitted');
      expect(fails(with_([draft])), isEmpty);
    });

    test('release option unset is a warning, not a blocker', () {
      final d = PreflightData(
        version: version(releaseType: null),
        build: build(),
        localizations: [loc()],
        screenshotsByLoc: {'L-en-US': 1},
        reviewDetail: review(),
      );
      expect(canSubmit(evaluatePreflight(d)), isTrue);
      expect(evaluatePreflight(d).any((c) => c.level == CheckLevel.warn && c.fix == CheckFix.release), isTrue);
    });
  });

  group('request bodies', () {
    test('new version', () {
      expect(versionCreateBody(appId: 'A1', versionString: '4.9.0', buildId: 'B1'), {
        'data': {
          'type': 'appStoreVersions',
          'attributes': {'versionString': '4.9.0', 'platform': 'IOS', 'releaseType': 'MANUAL'},
          'relationships': {
            'app': {
              'data': {'type': 'apps', 'id': 'A1'},
            },
            'build': {
              'data': {'type': 'builds', 'id': 'B1'},
            },
          },
        },
      });
      expect(((versionCreateBody(appId: 'A1', versionString: '1')['data'] as Map)['relationships'] as Map).containsKey('build'), isFalse);
    });

    test('release type only sends a date when scheduled', () {
      expect(
        ((releaseTypeBody('V1', 'MANUAL', earliest: DateTime.utc(2027))['data'] as Map)['attributes'] as Map).containsKey(
          'earliestReleaseDate',
        ),
        isFalse,
      );
      expect(
        ((releaseTypeBody('V1', 'SCHEDULED', earliest: DateTime.utc(2027, 1, 2))['data'] as Map)['attributes']
            as Map)['earliestReleaseDate'],
        '2027-01-02T00:00:00.000Z',
      );
    });

    test('review detail: create links the version, update carries the id and no relationship', () {
      final c = reviewDetailBody(versionId: 'V1', fields: {'contactEmail': 'a@b.c'}, demoAccountRequired: false)['data'] as Map;
      expect(c.containsKey('id'), isFalse);
      expect((c['relationships'] as Map)['appStoreVersion'], {
        'data': {'type': 'appStoreVersions', 'id': 'V1'},
      });
      final u =
          reviewDetailBody(existingId: 'R1', versionId: 'V1', fields: {'contactEmail': 'a@b.c'}, demoAccountRequired: true)['data'] as Map;
      expect(u['id'], 'R1');
      expect(u.containsKey('relationships'), isFalse);
      expect((u['attributes'] as Map)['demoAccountRequired'], true);
    });
  });

  group('flow against a mock server', () {
    Map<String, dynamic> list(List<Map<String, dynamic>> data) => {'data': data};

    test('submit with no draft: create submission, add the version, submit, read back the state', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) return json(list([]));
        if (r.method == 'POST' && r.path == '/v1/reviewSubmissions') {
          return json({
            'data': {
              'type': 'reviewSubmissions',
              'id': 'S9',
              'attributes': {'state': 'READY_FOR_REVIEW'},
            },
          }, 201);
        }
        if (r.method == 'POST' && r.path == '/v1/reviewSubmissionItems') {
          return json({
            'data': {'type': 'reviewSubmissionItems', 'id': 'I1'},
          }, 201);
        }
        if (r.method == 'PATCH' && r.path == '/v1/reviewSubmissions/S9') {
          return json({
            'data': {
              'type': 'reviewSubmissions',
              'id': 'S9',
              'attributes': {'state': 'WAITING_FOR_REVIEW'},
            },
          });
        }
        if (r.method == 'GET' && r.path == '/v1/reviewSubmissions/S9') {
          return json({
            'data': {
              'type': 'reviewSubmissions',
              'id': 'S9',
              'attributes': {'state': 'WAITING_FOR_REVIEW'},
            },
          });
        }
        return null;
      });
      final out = await SubmissionFlow(fake.client, 'A1').submit('V1');
      expect(out.state, 'WAITING_FOR_REVIEW');
      expect(fake.log.map((r) => '${r.method} ${r.path.split('?').first}').toList(), [
        'GET /v1/reviewSubmissions',
        'POST /v1/reviewSubmissions',
        'POST /v1/reviewSubmissionItems',
        'PATCH /v1/reviewSubmissions/S9',
        'GET /v1/reviewSubmissions/S9',
      ]);
      expect(fake.log[0].path, contains('filter%5Bapp%5D=A1'));
      expect(fake.log[0].path, contains('filter%5Bstate%5D=READY_FOR_REVIEW'));
      expect(fake.log[1].body!['data']['attributes'], {'platform': 'IOS'});
      expect(fake.log[2].body!['data']['relationships']['appStoreVersion']['data']['id'], 'V1');
      expect(fake.log[3].body!['data'], {
        'type': 'reviewSubmissions',
        'id': 'S9',
        'attributes': {'submitted': true},
      });
    });

    test('submit reuses the app\'s draft and does not re-add a version it already contains', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) {
          return json(
            list([
              {
                'type': 'reviewSubmissions',
                'id': 'D1',
                'attributes': {'state': 'READY_FOR_REVIEW'},
              },
            ]),
          );
        }
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions/D1/items')) {
          return json(
            list([
              {
                'type': 'reviewSubmissionItems',
                'id': 'I1',
                'relationships': {
                  'appStoreVersion': {
                    'data': {'type': 'appStoreVersions', 'id': 'V1'},
                  },
                },
              },
            ]),
          );
        }
        if (r.method == 'PATCH') {
          return json({
            'data': {'type': 'reviewSubmissions', 'id': 'D1'},
          });
        }
        if (r.method == 'GET' && r.path == '/v1/reviewSubmissions/D1') {
          return json({
            'data': {
              'type': 'reviewSubmissions',
              'id': 'D1',
              'attributes': {'state': 'WAITING_FOR_REVIEW'},
            },
          });
        }
        return null;
      });
      await SubmissionFlow(fake.client, 'A1').submit('V1');
      expect(fake.log.any((r) => r.method == 'POST'), isFalse);
      expect(fake.log.where((r) => r.method == 'PATCH').single.path, '/v1/reviewSubmissions/D1');
    });

    test('an empty draft gets this version added before submitting', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) {
          return json(
            list([
              {
                'type': 'reviewSubmissions',
                'id': 'D1',
                'attributes': {'state': 'READY_FOR_REVIEW'},
              },
            ]),
          );
        }
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions/D1/items')) return json(list([]));
        if (r.method == 'POST' && r.path == '/v1/reviewSubmissionItems') {
          return json({
            'data': {'type': 'reviewSubmissionItems', 'id': 'I2'},
          }, 201);
        }
        if (r.method == 'PATCH') {
          return json({
            'data': {'type': 'reviewSubmissions', 'id': 'D1'},
          });
        }
        if (r.method == 'GET') {
          return json({
            'data': {
              'type': 'reviewSubmissions',
              'id': 'D1',
              'attributes': {'state': 'WAITING_FOR_REVIEW'},
            },
          });
        }
        return null;
      });
      await SubmissionFlow(fake.client, 'A1').submit('V1');
      expect(fake.log.where((r) => r.method == 'POST').single.path, '/v1/reviewSubmissionItems');
    });

    test('preflight: a failed lookup is an error, not a missing build or missing review details; a 404 is "none"', () async {
      final version = res('appStoreVersions', 'V1', {'versionString': '2.0', 'appStoreState': 'PREPARE_FOR_SUBMISSION'});
      FakeAsc server({required int buildStatus}) => FakeAsc((r) {
        if (r.path.startsWith('/v1/appStoreVersions/V1/build')) {
          return buildStatus == 200 ? json({'data': null}) : apiError(buildStatus, 'Error', 'boom');
        }
        if (r.path.startsWith('/v1/appStoreVersions/V1/appStoreReviewDetail')) return apiError(404, 'Not found', 'none');
        if (r.path.startsWith('/v1/appStoreVersions/V1/appStoreVersionLocalizations')) return json(list([]));
        if (r.path.startsWith('/v1/reviewSubmissions')) return json(list([]));
        return null;
      });
      await expectLater(loadPreflight(server(buildStatus: 503).client, 'A1', version, hasPriorVersion: true), throwsA(isA<AscException>()));
      final ok = await loadPreflight(server(buildStatus: 200).client, 'A1', version, hasPriorVersion: true);
      expect(ok.build, isNull);
      expect(ok.reviewDetail, isNull, reason: '404 means there is none yet');
    });

    test('an unreadable draft is not treated as empty', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) {
          return json(
            list([
              {
                'type': 'reviewSubmissions',
                'id': 'D1',
                'attributes': {'state': 'READY_FOR_REVIEW'},
              },
            ]),
          );
        }
        if (r.path.startsWith('/v1/reviewSubmissions/D1/items')) return apiError(500, 'Server error', 'later');
        return null;
      });
      await expectLater(SubmissionFlow(fake.client, 'A1').submit('V1'), throwsA(isA<AscException>()));
      expect(fake.log.any((r) => r.method != 'GET'), isFalse);
    });

    test('a draft that already holds other items is refused, and nothing is added or submitted', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) {
          return json(
            list([
              {
                'type': 'reviewSubmissions',
                'id': 'D1',
                'attributes': {'state': 'READY_FOR_REVIEW'},
              },
            ]),
          );
        }
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions/D1/items')) {
          return json(
            list([
              {
                'type': 'reviewSubmissionItems',
                'id': 'I1',
                'relationships': {
                  'appStoreVersion': {
                    'data': {'type': 'appStoreVersions', 'id': 'V1'},
                  },
                },
              },
              {
                'type': 'reviewSubmissionItems',
                'id': 'I2',
                'relationships': {
                  'appEvent': {
                    'data': {'type': 'appEvents', 'id': 'E1'},
                  },
                },
              },
            ]),
          );
        }
        return null;
      });
      await expectLater(SubmissionFlow(fake.client, 'A1').submit('V1'), throwsA(predicate((e) => e.toString().contains('1 other item'))));
      expect(fake.log.any((r) => r.method != 'GET'), isFalse);
    });

    test('a macOS version is submitted as macOS: the draft lookup and a new submission use its platform', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) return json(list([]));
        if (r.method == 'POST' && r.path == '/v1/reviewSubmissions') {
          return json({
            'data': {'type': 'reviewSubmissions', 'id': 'S9'},
          }, 201);
        }
        if (r.method == 'POST') {
          return json({
            'data': {'type': 'reviewSubmissionItems', 'id': 'I1'},
          }, 201);
        }
        if (r.method == 'PATCH') {
          return json({
            'data': {'type': 'reviewSubmissions', 'id': 'S9'},
          });
        }
        if (r.method == 'GET') {
          return json({
            'data': {
              'type': 'reviewSubmissions',
              'id': 'S9',
              'attributes': {'state': 'WAITING_FOR_REVIEW'},
            },
          });
        }
        return null;
      });
      await SubmissionFlow(fake.client, 'A1').submit('V1', platform: 'MAC_OS');
      expect(fake.log.first.path, contains('filter%5Bplatform%5D=MAC_OS'));
      expect(fake.log[1].body!['data']['attributes'], {'platform': 'MAC_OS'});
    });

    test('an Apple refusal at submit time surfaces as an error and nothing else is sent', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path.startsWith('/v1/reviewSubmissions?')) return json(list([]));
        if (r.method == 'POST' && r.path == '/v1/reviewSubmissions') {
          return json({
            'data': {'type': 'reviewSubmissions', 'id': 'S9'},
          }, 201);
        }
        if (r.method == 'POST' && r.path == '/v1/reviewSubmissionItems') return apiError(409, 'ENTITY_ERROR', 'You must provide a build');
        return null;
      });
      await expectLater(
        SubmissionFlow(fake.client, 'A1').submit('V1'),
        throwsA(predicate((e) => e.toString().contains('You must provide a build'))),
      );
      expect(fake.log.any((r) => r.method == 'PATCH'), isFalse);
    });

    test('attach build, export compliance, release type, review detail and cancel hit the documented endpoints', () async {
      final fake = FakeAsc(
        (r) => r.method == 'POST'
            ? json({
                'data': {'type': 'x', 'id': 'N'},
              }, 201)
            : noContentOrOk(r),
      );
      final f = SubmissionFlow(fake.client, 'A1');
      await f.attachBuild('V1', 'B1');
      await f.setExportCompliance('B1', false);
      await f.setReleaseType('V1', 'AFTER_APPROVAL');
      await f.saveReviewDetail('V1', fields: {'contactEmail': 'a@b.c'}, demoAccountRequired: false);
      await f.saveReviewDetail('V1', existingId: 'R1', fields: {'contactEmail': 'x@y.z'}, demoAccountRequired: false);
      await f.cancel('S1');
      expect(fake.log.map((r) => '${r.method} ${r.path}').toList(), [
        'PATCH /v1/appStoreVersions/V1/relationships/build',
        'PATCH /v1/builds/B1',
        'PATCH /v1/appStoreVersions/V1',
        'POST /v1/appStoreReviewDetails',
        'PATCH /v1/appStoreReviewDetails/R1',
        'PATCH /v1/reviewSubmissions/S1',
      ]);
      expect(fake.log[0].body, {
        'data': {'type': 'builds', 'id': 'B1'},
      });
      expect(fake.log[1].body!['data']['attributes'], {'usesNonExemptEncryption': false});
      expect(fake.log.last.body!['data']['attributes'], {'canceled': true});
    });
  });

  group('rejection', () {
    Map<String, dynamic> sub(String id, String state) => {
      'type': 'reviewSubmissions',
      'id': id,
      'attributes': {'state': state},
    };
    Map<String, dynamic> item(String id, String state, String versionId) => {
      'type': 'reviewSubmissionItems',
      'id': id,
      'attributes': {'state': state},
      'relationships': {
        'appStoreVersion': {
          'data': {'type': 'appStoreVersions', 'id': versionId},
        },
      },
    };

    PreflightData withSubs(List<ActiveSubmission> s) {
      final base = good();
      return PreflightData(
        version: version(state: 'REJECTED'),
        build: base.build,
        localizations: base.localizations,
        screenshotsByLoc: base.screenshotsByLoc,
        reviewDetail: base.reviewDetail,
        submissions: s,
      );
    }

    test('a rejected version is not "already submitted": it can be resubmitted, and offers a reply', () {
      final mine = ActiveSubmission(res('reviewSubmissions', 'S1', {'state': 'UNRESOLVED_ISSUES'}), ['V1']);
      final checks = evaluatePreflight(withSubs([mine]));
      expect(canSubmit(checks), isTrue);
      expect(checks.singleWhere((c) => c.title == 'Rejected by App Review').fix, CheckFix.reply);
    });

    test("another version's unresolved submission blocks submitting this one", () {
      final other = ActiveSubmission(res('reviewSubmissions', 'S1', {'state': 'UNRESOLVED_ISSUES'}), ['V0']);
      expect(fails(withSubs([other])).single.title, 'Another submission has unresolved issues');
    });

    test('resubmit marks the rejected items resolved, then submits the same submission; nothing new is created', () async {
      final fake = FakeAsc((r) {
        final p = r.path.split('?').first;
        if (r.method == 'GET' && p == '/v1/reviewSubmissions') {
          return json({
            'data': [sub('S1', 'UNRESOLVED_ISSUES')],
          });
        }
        if (r.method == 'GET' && p == '/v1/reviewSubmissions/S1/items') {
          return json({
            'data': [item('I1', 'REJECTED', 'V1'), item('I2', 'ACCEPTED', 'V1')],
          });
        }
        if (r.method == 'PATCH') {
          return json({
            'data': {'type': 'x', 'id': 'ok'},
          });
        }
        if (r.method == 'GET' && p == '/v1/reviewSubmissions/S1') return json({'data': sub('S1', 'WAITING_FOR_REVIEW')});
        return null;
      });
      final out = await SubmissionFlow(fake.client, 'A1').submit('V1');
      expect(out.resubmitted, isTrue);
      expect(out.state, 'WAITING_FOR_REVIEW');
      expect(fake.log[0].path, contains('UNRESOLVED_ISSUES'));
      final writes = fake.log.where((r) => r.method != 'GET').toList();
      expect(writes.map((r) => '${r.method} ${r.path}'), ['PATCH /v1/reviewSubmissionItems/I1', 'PATCH /v1/reviewSubmissions/S1']);
      expect(writes[0].body!['data'], {
        'type': 'reviewSubmissionItems',
        'id': 'I1',
        'attributes': {'resolved': true},
      });
      expect(writes[1].body!['data']['attributes'], {'submitted': true});
    });

    test("another version's unresolved submission is refused before anything is written", () async {
      final fake = FakeAsc((r) {
        final p = r.path.split('?').first;
        if (p == '/v1/reviewSubmissions') {
          return json({
            'data': [sub('S1', 'UNRESOLVED_ISSUES')],
          });
        }
        if (p == '/v1/reviewSubmissions/S1/items') {
          return json({
            'data': [item('I1', 'REJECTED', 'V0')],
          });
        }
        return null;
      });
      await expectLater(SubmissionFlow(fake.client, 'A1').submit('V1'), throwsA(isA<AscException>()));
      expect(fake.log.where((r) => r.method != 'GET'), isEmpty);
    });

    // Seen live: right after `submitted: true` Apple still read back UNRESOLVED_ISSUES, so the app said the resubmit
    // had not worked when it had.
    FakeAsc lagging(List<String> readBacks) {
      var n = 0;
      return FakeAsc((r) {
        final p = r.path.split('?').first;
        if (r.method == 'GET' && p == '/v1/reviewSubmissions') {
          return json({
            'data': [sub('S1', 'UNRESOLVED_ISSUES')],
          });
        }
        if (r.method == 'GET' && p == '/v1/reviewSubmissions/S1/items') {
          return json({
            'data': [item('I1', 'REJECTED', 'V1')],
          });
        }
        if (r.method == 'PATCH') {
          return json({
            'data': {'type': 'x', 'id': 'ok'},
          });
        }
        if (r.method == 'GET' && p == '/v1/reviewSubmissions/S1') {
          return json({'data': sub('S1', readBacks[n < readBacks.length ? n++ : readBacks.length - 1])});
        }
        return null;
      });
    }

    test('a stale read-back right after resubmitting is waited out, not reported', () async {
      final fake = lagging(['UNRESOLVED_ISSUES', 'UNRESOLVED_ISSUES', 'WAITING_FOR_REVIEW']);
      final out = await SubmissionFlow(fake.client, 'A1', settleDelay: Duration.zero).submit('V1');
      expect(out.state, 'WAITING_FOR_REVIEW');
      expect(fake.log.where((r) => r.method == 'GET' && r.path == '/v1/reviewSubmissions/S1'), hasLength(3));
    });

    test('if Apple never catches up, the state is unknown rather than "unresolved issues"', () async {
      final fake = lagging(['UNRESOLVED_ISSUES']);
      final out = await SubmissionFlow(fake.client, 'A1', settleDelay: Duration.zero).submit('V1');
      expect(out.resubmitted, isTrue);
      expect(out.state, isNull);
      expect(fake.log.where((r) => r.method == 'PATCH'), hasLength(2), reason: 'polling never sends the submit again');
    });

    test('a reply is added under a dated heading to the existing notes, and only the notes are sent', () async {
      final fake = FakeAsc((r) => r.method == 'PATCH' ? json({'data': res('appStoreReviewDetails', 'R1').attributes}) : null);
      final detail = res('appStoreReviewDetails', 'R1', {'notes': 'Demo login is in the app.', 'contactPhone': '1'});
      await SubmissionFlow(fake.client, 'A1').replyInNotes('V1', detail, '  We removed the feature.  ');
      final w = fake.log.single;
      expect(w.path, '/v1/appStoreReviewDetails/R1');
      final attrs = w.body!['data']['attributes'] as Map;
      expect(attrs.keys.toSet(), {'notes', 'demoAccountRequired'}, reason: 'contact details are left as they are');
      expect(
        attrs['notes'],
        matches(RegExp(r'^Demo login is in the app\.\n\nReply to App Review \(\d{4}-\d{2}-\d{2}\):\nWe removed the feature\.$')),
      );
    });

    test('a reply that would push the notes past 4000 characters is refused locally', () async {
      final fake = FakeAsc((r) => null);
      await expectLater(
        SubmissionFlow(fake.client, 'A1').replyInNotes('V1', res('appStoreReviewDetails', 'R1', {'notes': 'x' * 3990}), 'too long'),
        throwsA(isA<AscException>()),
      );
      expect(fake.log, isEmpty);
    });
  });
}

// Relationship PATCHes answer 204; the others echo an object.
dynamic noContentOrOk(Recorded r) => r.path.contains('/relationships/')
    ? noContent()
    : json({
        'data': {'type': 'x', 'id': 'ok'},
      });
