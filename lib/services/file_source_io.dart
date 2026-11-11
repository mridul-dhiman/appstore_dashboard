import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';

import '../api/ipa_info.dart';
import '../api/upload_source.dart';

const fileSourcesSupported = true;

/// An .ipa on disk. Parts are read one range at a time, so a 2 GB build never sits in memory.
class FileSource implements UploadSource {
  FileSource(this.path, {required this.name}) : length = File(path).lengthSync();
  final String path;
  @override
  final String name;
  @override
  final int length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final f = await File(path).open();
    try {
      await f.setPosition(offset);
      return await f.read(length);
    } finally {
      await f.close();
    }
  }

  /// Streams the file through MD5 on a background isolate, so the window keeps responding.
  @override
  Future<String> md5Hex() {
    final p = path;
    return Isolate.run(() async => (await md5.bind(File(p).openRead()).first).toString());
  }
}

/// Reads only the zip directory and the Info.plist entry, on a background isolate.
Future<IpaInfo> readIpaInfoFromFile(String path) => Isolate.run(() {
  final input = InputFileStream(path);
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
    } catch (_) {
      throw IpaException('That file is not a valid .ipa (it could not be opened as a zip).');
    }
    return readIpaInfoFromArchive(archive);
  } finally {
    input.closeSync();
  }
});
