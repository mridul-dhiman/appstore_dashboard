import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Something to upload in parts without holding it all in memory: a file on disk on desktop, or plain bytes.
abstract class UploadSource {
  String get name;
  int get length;

  /// The bytes in `[offset, offset + length)`. Only that range is read.
  Future<Uint8List> read(int offset, int length);

  /// MD5 of the whole thing, as lowercase hex. Computed off the UI thread where the platform allows.
  Future<String> md5Hex();
}

class BytesSource implements UploadSource {
  BytesSource(this.name, this.bytes);
  @override
  final String name;
  final Uint8List bytes;

  @override
  int get length => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async => Uint8List.sublistView(bytes, offset, offset + length);

  @override
  Future<String> md5Hex() async => md5.convert(bytes).toString();
}
