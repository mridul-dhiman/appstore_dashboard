import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appstore_dashboard/api/build_uploader.dart';
import 'package:appstore_dashboard/api/ipa_info.dart';
import 'package:appstore_dashboard/services/file_source.dart';
import 'package:appstore_dashboard/state/upload_jobs.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_asc.dart';

/// Records which byte ranges were read, to prove parts are read one at a time.
class CountingSource extends BytesSource {
  CountingSource(super.name, super.bytes);
  final reads = <(int, int)>[];
  @override
  Future<Uint8List> read(int offset, int length) {
    reads.add((offset, length));
    return super.read(offset, length);
  }
}

http.Response? asc(Recorded r, {String state = 'COMPLETE'}) {
  if (r.method == 'POST' && r.path == '/v1/buildUploads') return json({'data': {'type': 'buildUploads', 'id': 'U1'}}, 201);
  if (r.method == 'POST' && r.path == '/v1/buildUploadFiles') {
    return json({
      'data': {
        'type': 'buildUploadFiles',
        'id': 'F1',
        'attributes': {
          'uploadOperations': [
            {'method': 'PUT', 'url': 'https://up.test/1', 'offset': 0, 'length': 6, 'requestHeaders': []},
            {'method': 'PUT', 'url': 'https://up.test/2', 'offset': 6, 'length': 4, 'requestHeaders': []},
          ],
        },
      },
    }, 201);
  }
  if (r.method == 'PATCH') return json({'data': {'type': 'buildUploadFiles', 'id': 'F1'}});
  if (r.method == 'GET' && r.path == '/v1/buildUploads/U1') return json({'data': {'type': 'buildUploads', 'id': 'U1', 'attributes': {'state': {'state': state}}}});
  return null;
}

final info = IpaInfo(bundleId: 'com.x', version: '1.0', build: '7');

void main() {
  late List<String> puts;
  setUp(() {
    puts = [];
    assetHttpClientFactory = () => MockClient((req) async {
          puts.add('${req.url} ${req.bodyBytes.length}');
          return http.Response('', 200);
        });
  });
  tearDown(() => assetHttpClientFactory = http.Client.new);

  test('parts are read from the source one range at a time, and the MD5 is of the whole file', () async {
    final fake = FakeAsc(asc);
    final source = CountingSource('a.ipa', Uint8List.fromList(List.generate(10, (i) => i)));
    final job = UploadJob(appId: 'A1', info: info, source: source);
    await job.run(fake.client);
    expect(job.failure, isNull);
    expect(job.finished, isTrue);
    expect(source.reads..sort((a, b) => a.$1.compareTo(b.$1)), [(0, 6), (6, 4)]);
    expect(puts.toSet(), {'https://up.test/1 6', 'https://up.test/2 4'});
    final commit = fake.log.firstWhere((r) => r.method == 'PATCH');
    expect(commit.body!['data']['attributes']['sourceFileChecksums']['file']['hash'], md5Hex(source.bytes));
  });

  test('stopping before the commit sends no commit; the job reports it was stopped', () async {
    final gate = Completer<void>();
    final fake = FakeAsc(asc);
    assetHttpClientFactory = () => MockClient((req) async {
          await gate.future;
          return http.Response('', 200);
        });
    final job = UploadJob(appId: 'A1', info: info, source: BytesSource('a.ipa', Uint8List(10)));
    final running = job.run(fake.client);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    job.cancel();
    gate.complete();
    await running;
    expect(job.cancelled, isTrue);
    expect(job.committed, isFalse);
    expect(fake.log.where((r) => r.method == 'PATCH'), isEmpty, reason: 'nothing committed after stopping');
  });

  test('only one upload per app runs at a time, and the job stays findable when done', () async {
    final fake = FakeAsc(asc);
    final jobs = UploadJobs();
    final job = jobs.start(UploadJob(appId: 'A1', info: info, source: BytesSource('a.ipa', Uint8List(10))), fake.client)!;
    expect(jobs.start(UploadJob(appId: 'A1', info: info, source: BytesSource('b.ipa', Uint8List(10))), fake.client), isNull,
        reason: 'one upload per app at a time');
    final done = Completer<void>();
    job.addListener(() {
      if (!job.running && !done.isCompleted) done.complete();
    });
    await done.future;
    expect(job.failure, isNull);
    expect(jobs.forApp('A1'), same(job));
  });

  test('a file on disk is read in ranges, hashed in the background, and its Info.plist found without loading it whole', () async {
    final dir = Directory.systemTemp.createTempSync('ipa');
    addTearDown(() => dir.deleteSync(recursive: true));
    final plist = '<plist><dict><key>CFBundleIdentifier</key><string>com.x</string><key>CFBundleShortVersionString</key>'
        '<string>2.0</string><key>CFBundleVersion</key><string>9</string></dict></plist>';
    final archive = Archive()..addFile(ArchiveFile.string('Payload/X.app/Info.plist', plist));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final file = File('${dir.path}/x.ipa')..writeAsBytesSync(bytes);

    final read = await readIpaInfoFromFile(file.path);
    expect((read.bundleId, read.version, read.build), ('com.x', '2.0', '9'));

    final source = FileSource(file.path, name: 'x.ipa');
    expect(source.length, bytes.length);
    expect(await source.read(3, 5), bytes.sublist(3, 8));
    expect(await source.md5Hex(), md5Hex(bytes));

    final junk = File('${dir.path}/junk.ipa')..writeAsStringSync('not a zip');
    await expectLater(readIpaInfoFromFile(junk.path), throwsA(isA<IpaException>()));
  });

  test('slow processing at Apple ends as "still processing", not as a failure', () async {
    final fake = FakeAsc((r) => asc(r, state: 'PROCESSING'));
    final job = UploadJob(appId: 'A1', info: info, source: BytesSource('a.ipa', Uint8List(10)));
    await job.run(fake.client, pollEvery: Duration.zero, giveUpAfter: Duration.zero);
    expect(job.failure, isNull);
    expect(job.progress!.phase, UploadPhase.stillProcessing);
    expect(job.running, isFalse);
  });

  group('part retries', () {
    setUp(() => partRetryBackoff = Duration.zero);
    tearDown(() => partRetryBackoff = const Duration(seconds: 2));
    final ops = [UploadOp(method: 'PUT', url: 'https://up.test/1', offset: 0, length: 4, headers: const {})];

    test('a 403 (expired link) fails at once, without retrying', () async {
      var n = 0;
      assetHttpClientFactory = () => MockClient((req) async {
            n++;
            return http.Response('', 403);
          });
      await expectLater(putParts(ops, Uint8List(4), (_) {}), throwsA(predicate((e) => e.toString().contains('expired'))));
      expect(n, 1);
    });

    test('a 503 is retried and can then succeed', () async {
      var n = 0;
      assetHttpClientFactory = () => MockClient((req) async => http.Response('', ++n < 3 ? 503 : 200));
      await putParts(ops, Uint8List(4), (_) {});
      expect(n, 3);
    });
  });
}
