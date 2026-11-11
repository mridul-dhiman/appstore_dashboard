import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// One saved client: the three parts of an App Store Connect API key, plus a display name.
class Credentials {
  const Credentials({
    required this.keyId,
    required this.issuerId,
    required this.privateKeyPem,
    this.name = '',
    this.vendorNumber = '',
  });

  final String keyId;
  final String issuerId;
  final String privateKeyPem;

  /// What the switcher shows. Defaults to the first app's name when connecting.
  final String name;

  /// Only needed for Sales & Trends. Not part of the key; found in App Store Connect → Payments and Financial Reports.
  final String vendorNumber;

  /// A client is identified by its issuer + key, so re-adding the same key replaces it instead of duplicating it.
  String get id => '$issuerId:$keyId';

  String get label => name.isNotEmpty ? name : 'Key $keyId';

  Credentials copyWith({String? name, String? vendorNumber}) => Credentials(
        keyId: keyId,
        issuerId: issuerId,
        privateKeyPem: privateKeyPem,
        name: name ?? this.name,
        vendorNumber: vendorNumber ?? this.vendorNumber,
      );

  Map<String, dynamic> toJson() =>
      {'keyId': keyId, 'issuerId': issuerId, 'privateKeyPem': privateKeyPem, 'name': name, 'vendorNumber': vendorNumber};

  factory Credentials.fromJson(Map<String, dynamic> j) => Credentials(
        keyId: j['keyId'] as String,
        issuerId: j['issuerId'] as String,
        privateKeyPem: j['privateKeyPem'] as String,
        name: (j['name'] as String?) ?? '',
        vendorNumber: (j['vendorNumber'] as String?) ?? '',
      );
}

/// Rebuilds a clean PEM from whatever was pasted: any whitespace or line-wrapping mix-up is repaired by re-wrapping the
/// base64 body. Returns the input trimmed if it has no BEGIN/END markers.
String normalizePem(String raw) {
  final m = RegExp(r'-----BEGIN ([A-Z ]+)-----([\s\S]*?)-----END \1-----').firstMatch(raw);
  if (m == null) return raw.trim();
  final body = m.group(2)!.replaceAll(RegExp(r'\s+'), '');
  final lines = [for (var i = 0; i < body.length; i += 64) body.substring(i, math.min(i + 64, body.length))];
  return '-----BEGIN ${m.group(1)}-----\n${lines.join('\n')}\n-----END ${m.group(1)}-----\n';
}

class AscException implements Exception {
  AscException(this.message, {this.status, this.code});

  final String message;
  final int? status;

  /// Apple's machine-readable code of the first error, e.g. `STATE_ERROR.ASSET_IN_POST_PROCESSING`.
  final String? code;

  @override
  String toString() => message;
}

/// The network failed before Apple answered. Reads retry it.
class _Unreachable extends AscException {
  _Unreachable(super.message);
}

/// [f]'s value, or null when Apple answers 404 (the thing does not exist). Any other failure is rethrown, so a network
/// blip or a permissions problem is never mistaken for "there is none".
Future<T?> nullIfMissing<T>(Future<T> f) async {
  try {
    return await f;
  } on AscException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

/// Talks to the App Store Connect API, signing its own short-lived JWT from the API key.
///
/// [baseUrl] is Apple's host on desktop. In a browser Apple's API sends no CORS headers, so the web build points this
/// at the bundled proxy (`server/server.js`) instead, which forwards the request untouched.
class AscClient {
  AscClient(this.credentials, {required this.baseUrl, http.Client? client, this.maxAttempts = 4, this.retryDelay = const Duration(seconds: 1)})
      : _http = client ?? http.Client(),
        _injected = client != null,
        _shared = false;

  AscClient._detached(AscClient from)
      : credentials = from.credentials,
        baseUrl = from.baseUrl,
        maxAttempts = from.maxAttempts,
        retryDelay = from.retryDelay,
        _http = from._injected ? from._http : http.Client(),
        _injected = from._injected,
        _shared = from._injected;

  /// A client with the same key that lives on its own: closing this one (when the client is renamed or locked) does
  /// not stop a long job such as a build upload that holds the copy.
  AscClient detached() => AscClient._detached(this);

  final bool _injected;
  final bool _shared; // the HTTP client belongs to another AscClient; do not close it

  static const appleHost = 'https://api.appstoreconnect.apple.com';

  final Credentials credentials;
  final String baseUrl;
  final http.Client _http;

  /// How many times a request may be sent. Reads are retried on rate limiting (429), Apple's temporary server errors
  /// (500, 502, 503, 504) and dropped connections; writes only on 429, which Apple sends before doing anything, so a
  /// write is never sent twice.
  final int maxAttempts;

  /// First wait between attempts; doubles each time. A `Retry-After` header from Apple wins when it is given.
  final Duration retryDelay;

  static const _retryableReads = {429, 500, 502, 503, 504};

  String? _jwt;
  DateTime? _jwtExpiry;

  String _token() {
    final now = DateTime.now();
    if (_jwt != null && _jwtExpiry!.isAfter(now.add(const Duration(minutes: 1)))) return _jwt!;
    final jwt = JWT(
      {'iss': credentials.issuerId, 'aud': 'appstoreconnect-v1'},
      header: {'kid': credentials.keyId, 'typ': 'JWT'},
    );
    _jwt = jwt.sign(ECPrivateKey(credentials.privateKeyPem), algorithm: JWTAlgorithm.ES256, expiresIn: const Duration(minutes: 15));
    _jwtExpiry = now.add(const Duration(minutes: 15));
    return _jwt!;
  }

  Uri _uri(String pathOrUrl, Map<String, String>? query) {
    if (pathOrUrl.startsWith('http')) {
      // `links.next` always points at Apple; keep it going through the same base URL.
      final u = Uri.parse(pathOrUrl);
      return Uri.parse(baseUrl + u.path).replace(query: u.query);
    }
    return Uri.parse(baseUrl + pathOrUrl).replace(queryParameters: query);
  }

  Future<http.Response> _send(Uri uri, {String method = 'GET', Object? body, Map<String, String>? headers}) async {
    final read = method == 'GET';
    for (var attempt = 1;; attempt++) {
      final last = attempt >= maxAttempts;
      final http.Response r;
      try {
        r = await _sendOnce(uri, method: method, body: body, headers: headers);
      } on _Unreachable {
        if (!read || last) rethrow;
        await Future<void>.delayed(retryDelay * (1 << (attempt - 1)));
        continue;
      }
      final retry = read ? _retryableReads.contains(r.statusCode) : r.statusCode == 429;
      if (!retry || last) return r;
      final after = int.tryParse(r.headers['retry-after'] ?? '');
      await Future<void>.delayed(after != null ? Duration(seconds: after.clamp(0, 60)) : retryDelay * (1 << (attempt - 1)));
    }
  }

  Future<http.Response> _sendOnce(Uri uri, {String method = 'GET', Object? body, Map<String, String>? headers}) async {
    try {
      final req = http.Request(method, uri)
        ..headers['Authorization'] = 'Bearer ${_token()}'
        ..headers.addAll(headers ?? const {});
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      return await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
    } on AscException {
      rethrow;
    } on FormatException catch (_) {
      throw AscException('The private key could not be read. Paste the full contents of the .p8 file, including the BEGIN/END lines.');
    } on ArgumentError catch (_) {
      throw AscException('The private key could not be read. Paste the full contents of the .p8 file, including the BEGIN/END lines.');
    } catch (e) {
      if (e is JWTException) throw AscException('Could not sign the request: ${e.message}');
      throw _Unreachable('Could not reach App Store Connect. Check your connection. ($e)');
    }
  }

  Never _fail(http.Response r) {
    String message = 'Request failed (${r.statusCode}).';
    String? code;
    try {
      final errors = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['errors'] as List?;
      if (errors != null && errors.isNotEmpty) {
        code = (errors.first as Map)['code']?.toString();
        message = errors.take(4).map((e) {
          final m = e as Map;
          return '${m['title'] ?? 'Error'}${m['detail'] != null ? ': ${m['detail']}' : ''}';
        }).join('\n');
      }
    } catch (_) {}
    if (r.statusCode == 429) {
      message = 'App Store Connect is rate-limiting this key (429). Wait a minute and try again.';
    } else if (r.statusCode == 401) {
      message = 'Apple rejected the key (401). Check the Key ID, Issuer ID and .p8 file belong together and the key is not revoked.';
    } else if (r.statusCode == 403) {
      message = 'This key is not allowed to do that. $message';
    }
    throw AscException(message, status: r.statusCode, code: code);
  }

  /// GET one page. [pathOrUrl] is a path like `/v1/apps` or a full `links.next` URL.
  Future<ResourcePage> page(String pathOrUrl, [Map<String, String>? query]) async {
    final r = await _send(_uri(pathOrUrl, query));
    if (r.statusCode != 200) _fail(r);
    return ResourcePage.fromJson((jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>());
  }

  /// GET up to [maxPages] pages and merge them.
  Future<ResourcePage> all(String path, [Map<String, String>? query, int maxPages = 4]) async {
    var current = await page(path, query);
    final data = [...current.data];
    final included = {...current.included};
    var pages = 1;
    while (current.next != null && pages < maxPages) {
      current = await page(current.next!);
      data.addAll(current.data);
      included.addAll(current.included);
      pages++;
    }
    return ResourcePage(data: data, included: included, next: current.next, total: current.total);
  }

  /// POST / PATCH / DELETE with a JSON:API body. Returns the parsed response, or null for 204 No Content.
  Future<ResourcePage?> write(String method, String path, [Map<String, dynamic>? body]) async {
    final r = await _send(_uri(path, null), method: method, body: body);
    if (r.statusCode == 204 || (r.statusCode < 300 && r.bodyBytes.isEmpty)) return null;
    if (r.statusCode >= 300) _fail(r);
    return ResourcePage.fromJson((jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, dynamic>());
  }

  Future<ResourcePage> post(String path, Map<String, dynamic> body) async => (await write('POST', path, body))!;
  /// Null when Apple answers 204 No Content (e.g. replacing a relationship such as a screenshot order).
  Future<ResourcePage?> patch(String path, Map<String, dynamic> body) => write('PATCH', path, body);
  Future<void> delete(String path) => write('DELETE', path);

  /// Sales & Trends reports come back as a gzipped TSV. Returns null when there is no report for that day (404).
  Future<String?> report(Map<String, String> query) async {
    final r = await _send(_uri('/v1/salesReports', query), headers: {'Accept': 'application/a-gzip'});
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _fail(r);
    final Uint8List bytes = r.bodyBytes;
    final gz = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
    return utf8.decode(gz ? GZipDecoder().decodeBytes(bytes) : bytes);
  }

  void close() {
    if (!_shared) _http.close();
  }
}
