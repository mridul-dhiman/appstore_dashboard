import 'dart:typed_data';

import '../api/ipa_info.dart';
import '../api/upload_source.dart';

const fileSourcesSupported = false;

class FileSource implements UploadSource {
  FileSource(String path, {required this.name}) {
    throw UnsupportedError('Reading files by path needs the desktop app.');
  }
  @override
  final String name;
  @override
  int get length => 0;
  @override
  Future<Uint8List> read(int offset, int length) => throw UnsupportedError('desktop only');
  @override
  Future<String> md5Hex() => throw UnsupportedError('desktop only');
}

Future<IpaInfo> readIpaInfoFromFile(String path) => throw UnsupportedError('desktop only');
