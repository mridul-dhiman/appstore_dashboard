import 'dart:convert';

import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A throwaway P-256 key generated only for tests; it has never been registered with Apple.
const testKeyPem = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg8KxpUaagfC9zLdYP
mYLSwEk8UcrZGWk0QYF4Tj/k9l6hRANCAATDM98vEzWNzM83U95rqGmwvQDBLAsh
HyTThNNAvhmVeewrhuUGJYCOWmm6I9qgk8g8FJVLDT7fwoRgr1CDHEUF
-----END PRIVATE KEY-----
''';

class Recorded {
  Recorded(this.method, this.path, this.body);
  final String method;
  final String path; // path + query
  final Map<String, dynamic>? body;
  @override
  String toString() => '$method $path';
}

typedef Responder = http.Response? Function(Recorded r);

/// An [AscClient] wired to a mock HTTP client: nothing leaves the process. [responder] answers by method/path; anything it
/// returns null for gets a 500 so an unexpected request fails the test loudly.
class FakeAsc {
  FakeAsc(this.responder) {
    client = AscClient(
      const Credentials(keyId: 'TESTKEY123', issuerId: '00000000-0000-0000-0000-000000000000', privateKeyPem: testKeyPem),
      baseUrl: 'https://asc.test',
      client: MockClient((req) async {
        Map<String, dynamic>? body;
        if (req.body.isNotEmpty) body = (jsonDecode(req.body) as Map).cast<String, dynamic>();
        final rec = Recorded(req.method, req.url.path + (req.url.hasQuery ? '?${req.url.query}' : ''), body);
        log.add(rec);
        return responder(rec) ?? http.Response(jsonEncode({'errors': [{'title': 'Unexpected', 'detail': rec.toString()}]}), 500);
      }),
    );
  }

  final Responder responder;
  final log = <Recorded>[];
  late final AscClient client;
}

http.Response json(Object body, [int status = 200]) => http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
http.Response noContent() => http.Response('', 204);
http.Response apiError(int status, String title, String detail) => json({'errors': [{'status': '$status', 'title': title, 'detail': detail}]}, status);
