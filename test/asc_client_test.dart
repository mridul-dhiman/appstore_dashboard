import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

void main() {
  test('an error keeps Apple\'s status, code and the readable message', () async {
    final fake = FakeAsc(
      (r) => json({
        'errors': [
          {'status': '409', 'code': 'STATE_ERROR.ASSET_IN_POST_PROCESSING', 'title': 'Busy', 'detail': 'Try again shortly.'},
          {'status': '409', 'code': 'OTHER', 'title': 'Second', 'detail': 'More.'},
        ],
      }, 409),
    );
    try {
      await fake.client.page('/v1/apps');
      fail('should have thrown');
    } on AscException catch (e) {
      expect(e.status, 409);
      expect(e.code, 'STATE_ERROR.ASSET_IN_POST_PROCESSING', reason: 'the first error\'s code');
      expect(e.message, contains('Busy: Try again shortly.'));
      expect(e.message, contains('Second: More.'));
    }
  });

  test('204 No Content is a null body, not a crash', () async {
    final fake = FakeAsc((r) => noContent());
    expect(await fake.client.patch('/v1/x/1', {'data': {}}), isNull);
    await fake.client.delete('/v1/x/1');
  });

  test('a 401 explains the key problem instead of Apple\'s terse text', () async {
    final fake = FakeAsc((r) => apiError(401, 'NOT_AUTHORIZED', 'Authentication credentials are missing or invalid.'));
    await expectLater(
      fake.client.page('/v1/apps'),
      throwsA(isA<AscException>().having((e) => e.message, 'message', contains('Key ID, Issuer ID'))),
    );
  });

  group('retries', () {
    test('a read is retried on 429 and temporary 5xx, then succeeds', () async {
      var n = 0;
      final fake = FakeAsc((r) {
        n++;
        if (n == 1) return apiError(429, 'Rate limited', 'slow down');
        if (n == 2) return apiError(503, 'Unavailable', 'later');
        return json({'data': []});
      }, maxAttempts: 4);
      final p = await fake.client.page('/v1/apps');
      expect(p.data, isEmpty);
      expect(fake.log, hasLength(3));
    });

    test('a read gives up after maxAttempts and reports the last answer', () async {
      final fake = FakeAsc((r) => apiError(503, 'Unavailable', 'still down'), maxAttempts: 3);
      await expectLater(fake.client.page('/v1/apps'), throwsA(isA<AscException>().having((e) => e.status, 'status', 503)));
      expect(fake.log, hasLength(3));
    });

    test('a write is retried on 429 only, never on 5xx (it may have happened)', () async {
      var n = 0;
      final limited = FakeAsc(
        (r) => ++n == 1
            ? apiError(429, 'Rate limited', 'x')
            : json({
                'data': {'type': 'x', 'id': '1'},
              }, 201),
        maxAttempts: 4,
      );
      await limited.client.post('/v1/things', {'data': {}});
      expect(limited.log, hasLength(2));

      final broken = FakeAsc((r) => apiError(500, 'Server error', 'x'), maxAttempts: 4);
      await expectLater(broken.client.post('/v1/things', {'data': {}}), throwsA(isA<AscException>()));
      expect(broken.log, hasLength(1));
    });

    test('a 404 or 409 is never retried', () async {
      final fake = FakeAsc((r) => apiError(404, 'Not found', 'x'), maxAttempts: 4);
      await expectLater(fake.client.page('/v1/apps/1'), throwsA(isA<AscException>()));
      expect(fake.log, hasLength(1));
    });

    test('429 explains itself', () async {
      final fake = FakeAsc((r) => apiError(429, 'Rate limited', 'x'));
      await expectLater(fake.client.page('/v1/apps'), throwsA(predicate((e) => e.toString().contains('rate-limiting'))));
    });
  });
}
