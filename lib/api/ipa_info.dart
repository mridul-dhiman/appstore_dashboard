import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

class IpaInfo {
  IpaInfo({required this.bundleId, required this.version, required this.build, this.minOs, this.displayName, this.platform = 'IOS'});
  final String bundleId;
  final String version; // CFBundleShortVersionString
  final String build; // CFBundleVersion
  final String? minOs;
  final String? displayName;

  /// App Store Connect platform the .ipa is for (`IOS`, `TV_OS`, `VISION_OS`), from Info.plist `DTPlatformName`.
  final String platform;
}

/// `DTPlatformName` → App Store Connect platform. Anything unknown is treated as iOS, the .ipa default.
String ascPlatformFor(String? dtPlatformName) => switch (dtPlatformName?.toLowerCase()) {
  'appletvos' => 'TV_OS',
  'xros' => 'VISION_OS',
  _ => 'IOS',
};

class IpaException implements Exception {
  IpaException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads `Payload/<App>.app/Info.plist` out of an .ipa (a zip) and returns the fields an upload needs.
IpaInfo readIpaInfo(Uint8List ipaBytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(ipaBytes);
  } catch (_) {
    throw IpaException('That file is not a valid .ipa (it could not be opened as a zip).');
  }
  return readIpaInfoFromArchive(archive);
}

/// The upload fields from an already opened .ipa archive.
IpaInfo readIpaInfoFromArchive(Archive archive) {
  final entry = archive.files.where((f) => f.isFile && RegExp(r'^Payload/[^/]+\.app/Info\.plist$').hasMatch(f.name)).firstOrNull;
  if (entry == null) throw IpaException('No Payload/<app>.app/Info.plist found. Is this an .ipa from an archive/export?');
  final dict = parsePlist(Uint8List.fromList(entry.content));
  String? s(String k) => dict[k]?.toString();
  final id = s('CFBundleIdentifier'), v = s('CFBundleShortVersionString'), b = s('CFBundleVersion');
  if (id == null || v == null || b == null) {
    throw IpaException('Info.plist is missing CFBundleIdentifier, CFBundleShortVersionString or CFBundleVersion.');
  }
  return IpaInfo(
    bundleId: id,
    version: v,
    build: b,
    minOs: s('MinimumOSVersion'),
    displayName: s('CFBundleDisplayName') ?? s('CFBundleName'),
    platform: ascPlatformFor(s('DTPlatformName')),
  );
}

/// Top-level dictionary of an Info.plist, binary (`bplist00`, what Xcode ships) or XML.
Map<String, dynamic> parsePlist(Uint8List data) {
  if (data.length > 8 && ascii.decode(data.sublist(0, 6), allowInvalid: true) == 'bplist') {
    final v = _Bplist(data).parse();
    if (v is Map) return v.cast<String, dynamic>();
    throw IpaException('Info.plist is not a dictionary.');
  }
  // XML: only the flat string keys we need.
  final text = utf8.decode(data, allowMalformed: true);
  final out = <String, dynamic>{};
  for (final m in RegExp(r'<key>([^<]+)</key>\s*<string>([^<]*)</string>').allMatches(text)) {
    out.putIfAbsent(m.group(1)!, () => m.group(2)!);
  }
  if (out.isEmpty) throw IpaException('Could not read Info.plist.');
  return out;
}

/// Minimal binary-plist reader: ints, reals, bools, ASCII/UTF-16 strings, data, arrays and dictionaries.
class _Bplist {
  _Bplist(this.d) : bd = ByteData.sublistView(d) {
    if (d.length < 40) throw IpaException('Info.plist is truncated.');
    final t = d.length - 32;
    offsetSize = d[t + 6];
    refSize = d[t + 7];
    numObjects = _uint(t + 8, 8);
    top = _uint(t + 16, 8);
    tableOffset = _uint(t + 24, 8);
  }

  final Uint8List d;
  final ByteData bd;
  late final int offsetSize, refSize, numObjects, top, tableOffset;

  int _uint(int at, int size) {
    var v = 0;
    for (var i = 0; i < size; i++) {
      v = (v << 8) | d[at + i];
    }
    return v;
  }

  int _offsetOf(int obj) => _uint(tableOffset + obj * offsetSize, offsetSize);

  dynamic parse() => _object(top, 0);

  /// Length for markers whose low nibble is 0xF: an int object follows.
  (int, int) _lengthAt(int pos, int nibble) {
    if (nibble != 0xF) return (nibble, pos + 1);
    final m = d[pos + 1];
    final size = 1 << (m & 0x0F);
    return (_uint(pos + 2, size), pos + 2 + size);
  }

  dynamic _object(int obj, int depth) {
    if (depth > 64 || obj >= numObjects) throw IpaException('Info.plist is malformed.');
    final pos = _offsetOf(obj);
    final marker = d[pos];
    final hi = marker >> 4, lo = marker & 0x0F;
    switch (hi) {
      case 0x0:
        return lo == 0x8
            ? false
            : lo == 0x9
            ? true
            : null;
      case 0x1:
        final size = 1 << lo;
        return size <= 8 ? _uint(pos + 1, size) : 0;
      case 0x2:
        return lo == 2 ? bd.getFloat32(pos + 1) : bd.getFloat64(pos + 1);
      case 0x4:
        final (len, start) = _lengthAt(pos, lo);
        return d.sublist(start, start + len);
      case 0x5:
        final (len, start) = _lengthAt(pos, lo);
        return ascii.decode(d.sublist(start, start + len), allowInvalid: true);
      case 0x6:
        final (len, start) = _lengthAt(pos, lo);
        final units = <int>[for (var i = 0; i < len; i++) bd.getUint16(start + i * 2)];
        return String.fromCharCodes(units);
      case 0xA:
        final (len, start) = _lengthAt(pos, lo);
        return [for (var i = 0; i < len; i++) _object(_uint(start + i * refSize, refSize), depth + 1)];
      case 0xD:
        final (len, start) = _lengthAt(pos, lo);
        final m = <String, dynamic>{};
        for (var i = 0; i < len; i++) {
          final k = _object(_uint(start + i * refSize, refSize), depth + 1);
          m['$k'] = _object(_uint(start + (len + i) * refSize, refSize), depth + 1);
        }
        return m;
      default:
        return null;
    }
  }
}
