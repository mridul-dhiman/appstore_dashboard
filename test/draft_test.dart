import 'dart:convert';
import 'dart:typed_data';

import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:appstore_dashboard/api/asset_upload.dart';
import 'package:appstore_dashboard/api/listing.dart';
import 'package:appstore_dashboard/api/listing_draft.dart';
import 'package:appstore_dashboard/api/screenshots.dart';
import 'package:appstore_dashboard/api/text_diff.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_asc.dart';

const descField = ListingField('description', 'Description');
const newsField = ListingField('whatsNew', "What's new");

ShotSetDraft existingSet() => ShotSetDraft(
  exists: true,
  group: 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE',
  versionLocId: 'L1',
  locale: 'en-US',
  items: [
    for (final id in ['A', 'B', 'C']) ShotItem.existing(id: 'P$id', name: '$id.png'),
  ],
);

void main() {
  group('text edits', () {
    test('editing back to the original removes the change', () {
      final d = ListingDraft();
      d.setText(target: TextTarget.version, locId: 'L1', locale: 'en-US', field: descField, before: 'old', after: 'new');
      expect(d.count, 1);
      d.setText(target: TextTarget.version, locId: 'L1', locale: 'en-US', field: descField, before: 'old', after: 'old');
      expect(d.isEmpty, isTrue);
    });

    test('apply sends ONE patch per localization containing only the edited fields, then empties the draft', () async {
      final fake = FakeAsc(
        (r) => r.method == 'PATCH'
            ? json({
                'data': {'type': 'x', 'id': 'L1'},
              })
            : null,
      );
      final d = ListingDraft();
      d.setText(target: TextTarget.version, locId: 'L1', locale: 'en-US', field: descField, before: 'old', after: 'new text');
      d.setText(target: TextTarget.version, locId: 'L1', locale: 'en-US', field: newsField, before: '', after: 'Bug fixes');
      final results = await d.apply(fake.client);
      expect(fake.log.single.toString(), 'PATCH /v1/appStoreVersionLocalizations/L1');
      expect(fake.log.single.body, {
        'data': {
          'type': 'appStoreVersionLocalizations',
          'id': 'L1',
          'attributes': {'description': 'new text', 'whatsNew': 'Bug fixes'},
        },
      });
      expect(results.single.ok, isTrue);
      expect(d.isEmpty, isTrue);
    });

    test('app-info edits go to appInfoLocalizations', () async {
      final fake = FakeAsc(
        (r) => json({
          'data': {'type': 'x', 'id': 'I1'},
        }),
      );
      final d = ListingDraft()
        ..setText(
          target: TextTarget.info,
          locId: 'I1',
          locale: 'en-US',
          field: const ListingField('subtitle', 'Subtitle'),
          before: '',
          after: 'Learn faster',
        );
      await d.apply(fake.client);
      expect(fake.log.single.path, '/v1/appInfoLocalizations/I1');
      expect(fake.log.single.body!['data']['attributes'], {'subtitle': 'Learn faster'});
    });

    test('one failing locale does not block the others, and the failed edit stays in the draft', () async {
      final fake = FakeAsc(
        (r) => r.path.endsWith('/L2')
            ? apiError(409, 'Conflict', 'Version is not editable')
            : json({
                'data': {'type': 'x', 'id': 'L1'},
              }),
      );
      final d = ListingDraft()
        ..setText(target: TextTarget.version, locId: 'L1', locale: 'en-US', field: descField, before: 'a', after: 'b')
        ..setText(target: TextTarget.version, locId: 'L2', locale: 'hi', field: descField, before: 'a', after: 'c');
      final results = await d.apply(fake.client);
      expect(results.where((r) => r.ok).length, 1);
      final bad = results.firstWhere((r) => !r.ok);
      expect(bad.error, contains('Version is not editable'));
      expect(d.count, 1);
      expect(d.changes().single.locale, 'hi');
    });
  });

  group('screenshot sets', () {
    late List<String> puts;
    setUp(() {
      puts = [];
      assetHttpClientFactory = () => MockClient((req) async {
        puts.add('${req.method} ${req.url} ${req.bodyBytes.length}B ${req.headers['Content-Type']}');
        return http.Response('', 200);
      });
    });
    tearDown(() => assetHttpClientFactory = http.Client.new);

    http.Response? asc(Recorded r) {
      if (r.method == 'DELETE') return noContent();
      if (r.method == 'POST' && r.path == '/v1/appAssetLibraryImages') {
        final size = r.body!['data']['attributes']['fileSize'];
        return json({
          'data': {
            'type': 'appAssetLibraryImages',
            'id': 'IMG1',
            'attributes': {
              'state': 'AWAITING_UPLOAD',
              'uploadOperations': [
                {
                  'method': 'PUT',
                  'url': 'https://upload.test/part1',
                  'offset': 0,
                  'length': size,
                  'requestHeaders': [
                    {'name': 'Content-Type', 'value': 'image/png'},
                  ],
                },
              ],
            },
          },
        }, 201);
      }
      if (r.method == 'PATCH' && r.path == '/v1/appAssetLibraryImages/IMG1') {
        return json({
          'data': {'type': 'appAssetLibraryImages', 'id': 'IMG1'},
        });
      }
      if (r.method == 'GET' && r.path == '/v1/appAssetLibraryImages/IMG1') {
        return json({
          'data': {
            'type': 'appAssetLibraryImages',
            'id': 'IMG1',
            'attributes': {'state': 'PREPARE_FOR_SUBMISSION'},
          },
        });
      }
      if (r.method == 'POST' && r.path == '/v1/appAssetLibraryPlacements') {
        return json({
          'data': {'type': 'appAssetLibraryPlacements', 'id': 'PLC1'},
        }, 201);
      }
      if (r.method == 'POST' && r.path == '/v1/appAssetLibraryPlacementOrderingRequests') {
        return json({
          'data': {'type': 'appAssetLibraryPlacementOrderingRequests', 'id': 'ORD1'},
        }, 201);
      }
      return null;
    }

    const key = 'L1:IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE';

    test('delete one, add one, reorder: exact request sequence and bodies', () async {
      final fake = FakeAsc(asc);
      final png = Uint8List.fromList(List.generate(2048, (i) => i % 251));
      final d = ListingDraft(libraryId: 'APP');
      final set = d.ensureShotSet(key, existingSet);
      d.toggleDelete(key, 1); // delete B
      d.addShots(key, [(name: 'new.png', bytes: png)]);
      d.move(key, 3, -3); // new first
      expect(set.needsReorder, isTrue);

      final results = await d.apply(fake.client);
      expect(results.single.ok, isTrue, reason: results.single.error);

      expect(fake.log.map((r) => '${r.method} ${r.path}').toList(), [
        'DELETE /v1/appAssetLibraryPlacements/PB',
        'POST /v1/appAssetLibraryImages',
        'PATCH /v1/appAssetLibraryImages/IMG1',
        'GET /v1/appAssetLibraryImages/IMG1',
        'POST /v1/appAssetLibraryPlacements',
        'POST /v1/appAssetLibraryPlacementOrderingRequests',
      ]);
      expect(fake.log[1].body, {
        'data': {
          'type': 'appAssetLibraryImages',
          'attributes': {'category': 'APP_SCREENSHOTS_AND_PREVIEWS', 'fileName': 'new.png', 'fileSize': 2048, 'referenceName': 'new.png'},
          'relationships': {
            'assetLibrary': {
              'data': {'type': 'appAssetLibraries', 'id': 'APP'},
            },
          },
        },
      });
      expect(puts.single, 'PUT https://upload.test/part1 2048B image/png');
      expect(fake.log[2].body!['data']['attributes'], {'uploaded': true}, reason: 'the library takes no checksum');
      expect(fake.log[4].body, {
        'data': {
          'type': 'appAssetLibraryPlacements',
          'attributes': {'placementType': 'APP_SCREENSHOT'},
          'relationships': {
            'image': {
              'data': {'type': 'appAssetLibraryImages', 'id': 'IMG1'},
            },
            'appStoreVersionLocalization': {
              'data': {'type': 'appStoreVersionLocalizations', 'id': 'L1'},
            },
          },
        },
      });
      final order = fake.log.last.body!['data'];
      expect(order['attributes'], {'placementGroup': 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE'});
      expect((order['relationships']['orderedPlacements']['data'] as List).map((e) => e['id']).toList(), ['PLC1', 'PA', 'PC']);
      expect(order['relationships']['appStoreVersionLocalization']['data']['id'], 'L1');
      expect(d.isEmpty, isTrue);
    });

    test('a new device group needs no creation call: its first screenshot is just uploaded and placed', () async {
      final fake = FakeAsc(asc);
      final d = ListingDraft(libraryId: 'APP');
      d.ensureShotSet(
        'L1:IPAD_13_PROFILE',
        () => ShotSetDraft(exists: false, group: 'IPAD_13_PROFILE', versionLocId: 'L1', locale: 'en-US', items: []),
      );
      d.addShots('L1:IPAD_13_PROFILE', [(name: 'a.png', bytes: Uint8List(10))]);
      final results = await d.apply(fake.client);
      expect(results.single.ok, isTrue, reason: results.single.error);
      expect(fake.log.map((r) => '${r.method} ${r.path}').toList(), [
        'POST /v1/appAssetLibraryImages',
        'PATCH /v1/appAssetLibraryImages/IMG1',
        'GET /v1/appAssetLibraryImages/IMG1',
        'POST /v1/appAssetLibraryPlacements',
      ]);
    });

    test('a placement Apple says is still post-processing is retried, any other error is not', () async {
      var tries = 0;
      final fake = FakeAsc((r) {
        if (r.method == 'POST' && r.path == '/v1/appAssetLibraryPlacements') {
          tries++;
          if (tries < 3) {
            return json({
              'errors': [
                {'status': '409', 'code': 'STATE_ERROR.ASSET_IN_POST_PROCESSING', 'title': 'Busy', 'detail': 'later'},
              ],
            }, 409);
          }
        }
        return asc(r);
      });
      expect(await createPlacement(fake.client, 'IMG1', 'L1', retryEvery: Duration.zero), 'PLC1');
      expect(tries, 3);

      final bad = FakeAsc(
        (r) => json({
          'errors': [
            {'status': '409', 'code': 'STATE_ERROR.EXPERIMENT_IN_PROGRESS', 'title': 'Test running', 'detail': 'no'},
          ],
        }, 409),
      );
      await expectLater(createPlacement(bad.client, 'IMG1', 'L1', retryEvery: Duration.zero), throwsA(isA<AscException>()));
      expect(bad.log.length, 1);
    });

    test('Apple rejecting the processed image is reported with its reason', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'GET' && r.path == '/v1/appAssetLibraryImages/IMG1') {
          return json({
            'data': {
              'type': 'appAssetLibraryImages',
              'id': 'IMG1',
              'attributes': {
                'state': 'FAILED',
                'stateDetails': [
                  {'code': 'IMAGE_BAD_SIZE', 'description': 'Wrong dimensions'},
                ],
              },
            },
          });
        }
        return asc(r);
      });
      final d = ListingDraft(libraryId: 'APP');
      d.ensureShotSet(key, existingSet);
      d.addShots(key, [(name: 'bad.png', bytes: Uint8List(10))]);
      final results = await d.apply(fake.client);
      expect(results.single.ok, isFalse);
      expect(results.single.error, contains('Wrong dimensions'));
      expect(fake.log.any((r) => r.path == '/v1/appAssetLibraryPlacements'), isFalse, reason: 'a rejected image must never be placed');
    });

    test('the part uploader refuses operations that do not cover the file, before sending a byte', () async {
      final fake = FakeAsc((r) {
        if (r.method == 'POST') {
          return json({
            'data': {
              'type': 'appAssetLibraryImages',
              'id': 'IMG1',
              'attributes': {
                'uploadOperations': [
                  {'method': 'PUT', 'url': 'https://upload.test/p', 'offset': 0, 'length': 5},
                ],
              },
            },
          }, 201);
        }
        return null;
      });
      final d = ListingDraft(libraryId: 'APP');
      d.ensureShotSet(key, existingSet);
      d.addShots(key, [(name: 'x.png', bytes: Uint8List(10))]);
      final results = await d.apply(fake.client);
      expect(results.single.error, contains('cover 5 bytes'));
      expect(puts, isEmpty);
    });

    test('a set that fails halfway stays in the draft, and Apply again only sends what is left', () async {
      var images = 0;
      var failSecond = true;
      final fake = FakeAsc((r) {
        if (r.method == 'POST' && r.path == '/v1/appAssetLibraryImages') {
          images++;
          if (images == 2 && failSecond) return apiError(500, 'Server error', 'try later');
        }
        return asc(r);
      });
      final d = ListingDraft(libraryId: 'APP');
      final set = d.ensureShotSet(key, existingSet);
      d.toggleDelete(key, 1); // delete B
      d.addShots(key, [(name: 'one.png', bytes: Uint8List(10)), (name: 'two.png', bytes: Uint8List(20))]);

      final first = await d.apply(fake.client);
      expect(first.single.ok, isFalse);
      expect(d.isEmpty, isFalse, reason: 'the failed set is kept, with its pictures');
      expect(identical(d.shotSet(key), set), isTrue);
      expect(set.items.map((i) => i.name).toList(), [
        'A.png',
        'C.png',
        'one.png',
        'two.png',
      ], reason: 'B is gone for good; one.png is placed');
      expect(set.items[2].isNew, isFalse);
      expect(set.items[3].isNew, isTrue);

      failSecond = false;
      fake.log.clear();
      final second = await d.apply(fake.client);
      expect(second.single.ok, isTrue, reason: second.single.error);
      expect(fake.log.map((r) => '${r.method} ${r.path}').toList(), [
        'POST /v1/appAssetLibraryImages',
        'PATCH /v1/appAssetLibraryImages/IMG1',
        'GET /v1/appAssetLibraryImages/IMG1',
        'POST /v1/appAssetLibraryPlacements',
        'POST /v1/appAssetLibraryPlacementOrderingRequests',
      ], reason: 'no second DELETE of B and no re-upload of one.png');
      expect(d.isEmpty, isTrue);
    });

    test('without a known library, new screenshots fail up front instead of half-applying', () async {
      final fake = FakeAsc(asc);
      final d = ListingDraft();
      d.ensureShotSet(key, existingSet);
      d.toggleDelete(key, 0);
      d.addShots(key, [(name: 'x.png', bytes: Uint8List(10))]);
      final results = await d.apply(fake.client);
      expect(results.single.ok, isFalse);
      expect(fake.log, isEmpty, reason: 'the delete must not run when the upload cannot');
    });
  });

  group('screenshot ordering rules', () {
    test('untouched set is not a change; deleting is; restoring undoes it', () {
      final d = ListingDraft();
      final s = d.ensureShotSet('k', existingSet);
      expect(s.changed, isFalse);
      d.toggleDelete('k', 0);
      expect(s.changed, isTrue);
      d.toggleDelete('k', 0);
      expect(s.changed, isFalse);
    });

    test('moving then moving back is not a change; a new shot at the end needs no reorder', () {
      final d = ListingDraft();
      final s = d.ensureShotSet('k', existingSet);
      d.move('k', 0, 1);
      expect(s.needsReorder, isTrue);
      d.move('k', 1, -1);
      expect(s.needsReorder, isFalse);
      d.addShots('k', [(name: 'n.png', bytes: Uint8List(1))]);
      expect(s.needsReorder, isFalse);
      expect(s.changed, isTrue);
    });

    test('a set holds at most 10 screenshots', () {
      final d = ListingDraft();
      final s = d.ensureShotSet('k', existingSet);
      d.addShots('k', [for (var i = 0; i < 15; i++) (name: '$i.png', bytes: Uint8List(1))]);
      expect(s.liveCount, 10);
    });
  });

  group('diff', () {
    test('line diff marks added and removed lines', () {
      final d = diffLines('one\ntwo\nthree', 'one\nTWO\nthree\nfour');
      expect(d.map((l) => '${l.op}${l.text}').toList(), [' one', '-two', '+TWO', ' three', '+four']);
      expect(diffStats(d), (added: 2, removed: 1));
    });

    test('empty to text and text to empty', () {
      expect(diffLines('', 'a\nb').every((l) => l.op == '+'), isTrue);
      expect(diffLines('a', '').single.op, '-');
      expect(diffLines('same', 'same').single.op, ' ');
    });

    test('very long input falls back to a full replace instead of stalling', () {
      final big = List.generate(500, (i) => 'line $i').join('\n');
      final d = diffLines(big, '$big\nx');
      expect(d.length, 1001);
    });
  });

  test('changelist labels every kind of change', () {
    final d = ListingDraft();
    d.setText(target: TextTarget.version, locId: 'L1', locale: 'en-US', field: descField, before: 'a', after: 'b');
    final s = d.ensureShotSet('k', existingSet);
    d.toggleDelete('k', 2);
    d.addShots('k', [(name: 'n.png', bytes: Uint8List(2048))]);
    d.move('k', 0, 1);
    expect(d.changes().map((c) => c.kind).toSet(), {ChangeKind.text, ChangeKind.shotDelete, ChangeKind.shotAdd, ChangeKind.shotOrder});
    expect(s.liveCount, 3);
    expect(jsonEncode(d.changes().map((c) => c.title).toList()), contains('Remove C.png'.replaceAll('Remove', 'remove')));
  });
}
