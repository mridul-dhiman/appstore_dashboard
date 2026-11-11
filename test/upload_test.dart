import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:appstore_dashboard/api/build_uploader.dart';
import 'package:appstore_dashboard/api/ipa_info.dart';
import 'package:flutter_test/flutter_test.dart';

// A real binary plist (bplist00) produced by plutil from known values, so the reader is checked against Apple's format.
const _fixture = 'YnBsaXN0MDDYAQIDBAUGBwgJCgsMDRAREl8QGkNGQnVuZGxlU2hvcnRWZXJzaW9uU3RyaW5nXxASQ0ZCdW5kbGVJZGVudGlmaWVyXxATQ0ZCdW5kbGVEaXNwbGF5TmFtZV8QEkxTUmVxdWlyZXNJUGhvbmVPU15VSURldmljZUZhbWlseVRMb25nXxAPQ0ZCdW5kbGVWZXJzaW9uXxAQTWluaW11bU9TVmVyc2lvblUyLjUuMV8QEGNvbS5leGFtcGxlLmRlbW9mAEQA6QBtAG8AICcTCaIODxABEAJfEER4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eFI4OFQxNi42AAgAGQA2AEsAYQB2AIUAigCcAK8AtQDIANUA1gDZANsA3QEkAScAAAAAAAACAQAAAAAAAAATAAAAAAAAAAAAAAAAAAABLA==';

void main() {
  test('binary Info.plist: strings, UTF-16, bools, arrays, long strings', () {
    final d = parsePlist(base64Decode(_fixture));
    expect(d['CFBundleIdentifier'], 'com.example.demo');
    expect(d['CFBundleShortVersionString'], '2.5.1');
    expect(d['CFBundleVersion'], '88');
    expect(d['MinimumOSVersion'], '16.6');
    expect(d['CFBundleDisplayName'], 'Démo ✓');
    expect(d['LSRequiresIPhoneOS'], true);
    expect(d['UIDeviceFamily'], [1, 2]);
    expect((d['Long'] as String).length, 68);
  });

  test('XML Info.plist falls back to the flat string keys', () {
    const xml = '<?xml version="1.0"?><plist><dict><key>CFBundleVersion</key><string>7</string><key>CFBundleShortVersionString</key><string>1.0</string></dict></plist>';
    final d = parsePlist(Uint8List.fromList(utf8.encode(xml)));
    expect(d['CFBundleVersion'], '7');
  });

  test('a non-zip file is a clear error, not a crash', () {
    expect(() => readIpaInfo(Uint8List.fromList([1, 2, 3, 4])), throwsA(isA<IpaException>()));
  });

  test('request bodies match the buildUploads / buildUploadFiles schemas', () {
    expect(buildUploadBody(appId: 'A1', version: '4.9.0', build: '373'), {
      'data': {
        'type': 'buildUploads',
        'attributes': {'cfBundleShortVersionString': '4.9.0', 'cfBundleVersion': '373', 'platform': 'IOS'},
        'relationships': {'app': {'data': {'type': 'apps', 'id': 'A1'}}},
      },
    });
    final f = buildUploadFileBody(uploadId: 'U1', fileName: 'x.ipa', fileSize: 10)['data'] as Map;
    expect(f['attributes'], {'fileName': 'x.ipa', 'fileSize': 10, 'uti': 'com.apple.ipa', 'assetType': 'ASSET'});
    expect(((f['relationships'] as Map)['buildUpload'] as Map)['data'], {'type': 'buildUploads', 'id': 'U1'});
    final c = commitBody(fileId: 'F1', md5Hex: 'abc')['data'] as Map;
    expect(c['id'], 'F1');
    expect(c['attributes'], {'uploaded': true, 'sourceFileChecksums': {'file': {'hash': 'abc', 'algorithm': 'MD5'}}});
  });

  test('MD5 is the standard digest', () {
    expect(md5Hex(Uint8List.fromList(utf8.encode('abc'))), '900150983cd24fb0d6963f7d28e17f72');
  });

  test('upload operations parse headers and are validated for exact coverage', () {
    final op = UploadOp.fromJson({'method': 'PUT', 'url': 'https://x/1', 'length': 6, 'offset': 0, 'requestHeaders': [{'name': 'Content-Type', 'value': 'application/octet-stream'}]});
    expect(op.headers, {'Content-Type': 'application/octet-stream'});
    UploadOp o(int off, int len) => UploadOp(method: 'PUT', url: 'u', offset: off, length: len, headers: const {});
    expect(validateOps([o(0, 6), o(6, 4)], 10), isNull);
    expect(validateOps([o(6, 4), o(0, 6)], 10), isNull); // order does not matter
    expect(validateOps([o(0, 5), o(6, 4)], 10), contains('gap'));
    expect(validateOps([o(0, 6), o(6, 3)], 10), contains('cover 9 bytes'));
    expect(validateOps(const [], 10), contains('no upload operations'));
  });

  test('the upload platform comes from DTPlatformName, not a hard-coded iOS', () {
    expect(ascPlatformFor('iphoneos'), 'IOS');
    expect(ascPlatformFor('appletvos'), 'TV_OS');
    expect(ascPlatformFor('xros'), 'VISION_OS');
    expect(ascPlatformFor(null), 'IOS');
    final tv = Archive()
      ..addFile(ArchiveFile.string('Payload/X.app/Info.plist',
          '<plist><dict><key>CFBundleIdentifier</key><string>a</string><key>CFBundleShortVersionString</key><string>1</string>'
          '<key>CFBundleVersion</key><string>2</string><key>DTPlatformName</key><string>appletvos</string></dict></plist>'));
    expect(readIpaInfo(Uint8List.fromList(ZipEncoder().encode(tv))).platform, 'TV_OS');
  });
}
