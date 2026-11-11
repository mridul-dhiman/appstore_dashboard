import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';

import 'asc_client.dart';
import 'upload_source.dart';

export 'upload_source.dart';

/// One part of the file Apple wants PUT somewhere: a byte range, a URL and the headers to send.
class UploadOp {
  UploadOp({required this.method, required this.url, required this.offset, required this.length, required this.headers});

  final String method;
  final String url;
  final int offset;
  final int length;
  final Map<String, String> headers;

  factory UploadOp.fromJson(Map<String, dynamic> j) => UploadOp(
        method: (j['method'] as String?) ?? 'PUT',
        url: j['url'] as String,
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        length: (j['length'] as num).toInt(),
        headers: {for (final h in (j['requestHeaders'] as List? ?? const [])) (h as Map)['name'] as String: h['value'] as String},
      );
}

/// Checks the operations cover the file exactly once, with no gaps or overlaps, before a single byte is sent.
String? validateOps(List<UploadOp> ops, int fileSize) {
  if (ops.isEmpty) return 'Apple returned no upload operations.';
  final sorted = [...ops]..sort((a, b) => a.offset.compareTo(b.offset));
  var next = 0;
  for (final o in sorted) {
    if (o.offset != next) return 'Upload operations leave a gap or overlap at byte $next.';
    next = o.offset + o.length;
  }
  return next == fileSize ? null : 'Upload operations cover $next bytes but the file is $fileSize.';
}

String md5Hex(Uint8List bytes) => md5.convert(bytes).toString();


/// Test seam (same idea as the Vidyagram repo's `*FetchOverride`): swap in a mock to avoid real network.
@visibleForTesting
http.Client Function() assetHttpClientFactory = http.Client.new;

/// PUT every part of [bytes] to the URLs Apple handed out. See [putSourceParts].
Future<void> putParts(List<UploadOp> ops, Uint8List bytes, void Function(int sentBytes) onSent, {int concurrency = 4}) =>
    putSourceParts(ops, BytesSource('', bytes), onSent, concurrency: concurrency);

/// Thrown when [UploadCancel.cancel] stops an upload between parts.
class UploadCancelled implements Exception {
  @override
  String toString() => 'Upload cancelled.';
}

class UploadCancel {
  bool _cancelled = false;
  bool get cancelled => _cancelled;
  void cancel() => _cancelled = true;
  void check() {
    if (_cancelled) throw UploadCancelled();
  }
}

/// PUT every part of [source] to the URLs Apple handed out. The URLs are unauthenticated (no JWT is sent), independent of
/// each other and expire, so a few go in parallel and each is retried. Each part is read from [source] only when it is
/// sent, so at most [concurrency] parts are in memory at once.
Future<void> putSourceParts(List<UploadOp> ops, UploadSource source, void Function(int sentBytes) onSent, {int concurrency = 4, UploadCancel? cancel}) async {
  final bad = validateOps(ops, source.length);
  if (bad != null) throw AscException(bad);
  var sent = 0;
  final client = assetHttpClientFactory();
  try {
    final queue = [...ops];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        cancel?.check();
        final op = queue.removeAt(0);
        await _putPart(client, op, await source.read(op.offset, op.length));
        sent += op.length;
        onSent(sent);
      }
    }

    await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  } finally {
    client.close();
  }
}

Future<void> _putPart(http.Client c, UploadOp op, Uint8List body) async {
  Object? last;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      final req = http.Request(op.method, Uri.parse(op.url))
        ..headers.addAll(op.headers)
        ..bodyBytes = body;
      final res = await http.Response.fromStream(await c.send(req).timeout(const Duration(minutes: 5)));
      if (res.statusCode >= 200 && res.statusCode < 300) return;
      last = 'HTTP ${res.statusCode}';
    } catch (e) {
      last = e;
    }
    await Future<void>.delayed(Duration(seconds: attempt * 2));
  }
  throw AscException('Uploading bytes ${op.offset}–${op.offset + op.length} failed after 3 tries ($last).');
}
