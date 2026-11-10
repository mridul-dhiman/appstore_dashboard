import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

void main() {
  test('an error keeps Apple\'s status, code and the readable message', () async {
    final fake = FakeAsc((r) => json({
          'errors': [
            {'status': '409', 'code': 'STATE_ERROR.ASSET_IN_POST_PROCESSING', 'title': 'Busy', 'detail': 'Try again shortly.'},
            {'status': '409', 'code': 'OTHER', 'title': 'Second', 'detail': 'More.'},
          ],
        }, 409));
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
    await expectLater(fake.client.page('/v1/apps'), throwsA(isA<AscException>().having((e) => e.message, 'message', contains('Key ID, Issuer ID'))));
  });
}
