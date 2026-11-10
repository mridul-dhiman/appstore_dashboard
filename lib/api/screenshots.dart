import 'dart:typed_data';

import 'asc_client.dart';
import 'asset_upload.dart';
import 'models.dart';

/// Screenshots go through Apple's App Asset Library: an image is uploaded to the app's library once, then a *placement*
/// puts it on a version localization. Apple picks the device group (`placementGroup`) from the image's pixel size.
const maxScreenshotsPerSet = 10;

const screenshotPlacementType = 'APP_SCREENSHOT';
const screenshotCategory = 'APP_SCREENSHOTS_AND_PREVIEWS';

/// Library image states that mean Apple has finished processing the upload (a placement may be created).
const processedImageStates = {
  'COMPLETE',
  'PREPARE_FOR_SUBMISSION',
  'READY_FOR_REVIEW',
  'WAITING_FOR_REVIEW',
  'IN_REVIEW',
  'ACCEPTED',
  'APPROVED',
};

/// What Apple accepts for screenshots: the device groups and the exact pixel sizes each one takes.
class ScreenshotSpecs {
  ScreenshotSpecs(this.sizesByGroup);

  /// Group id (e.g. `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE`) → accepted `(width, height)` pairs.
  final Map<String, List<({int w, int h})>> sizesByGroup;

  List<String> get groups => sizesByGroup.keys.toList();

  /// The group a picture of this size belongs to, or null when no group takes it.
  String? groupFor(int w, int h) {
    for (final e in sizesByGroup.entries) {
      if (e.value.any((s) => s.w == w && s.h == h)) return e.key;
    }
    return null;
  }

  bool accepts(String group, int w, int h) => sizesByGroup[group]?.any((s) => s.w == w && s.h == h) ?? false;

  /// `1290×2796 · 1320×2868` for a hint under a group's name.
  String sizesLabel(String group) {
    final sizes = sizesByGroup[group] ?? const [];
    final portrait = sizes.where((s) => s.h > s.w).toList();
    return (portrait.isEmpty ? sizes : portrait).map((s) => '${s.w}×${s.h}').join(' · ');
  }

  /// Reads `GET /v1/appAssetLibraryRefData?filter[placementTypes]=APP_SCREENSHOT`.
  static ScreenshotSpecs parse(Resource refData) {
    final specs = <String, List<({int w, int h})>>{};
    final bySpecId = <String, List<({int w, int h})>>{};
    for (final raw in (refData.attributes['imageSpecs'] as List? ?? const [])) {
      final spec = (raw as Map).cast<String, dynamic>();
      final d = (spec['dimensions'] as Map?)?.cast<String, dynamic>();
      if (d == null) continue;
      final minW = (d['minWidth'] as num?)?.toInt(), maxW = (d['maxWidth'] as num?)?.toInt();
      final minH = (d['minHeight'] as num?)?.toInt(), maxH = (d['maxHeight'] as num?)?.toInt();
      if (minW == null || minW != maxW || minH == null || minH != maxH) continue; // only exact sizes can be checked here
      bySpecId[spec['specId'].toString()] = [(w: minW, h: minH)];
    }
    for (final raw in (refData.attributes['placementTypes'] as List? ?? const [])) {
      final type = (raw as Map).cast<String, dynamic>();
      if (type['placementTypeId'] != screenshotPlacementType) continue;
      for (final m in (type['specMappings'] as List? ?? const [])) {
        final map = (m as Map).cast<String, dynamic>();
        specs[map['placementGroupId'].toString()] = [
          for (final id in (map['specs'] as List? ?? const [])) ...?bySpecId[id.toString()],
        ];
      }
    }
    return ScreenshotSpecs(specs);
  }
}

Future<ScreenshotSpecs> loadScreenshotSpecs(AscClient client) async {
  final p = await client.page('/v1/appAssetLibraryRefData', {'filter[placementTypes]': screenshotPlacementType});
  if (p.data.isEmpty) throw AscException('Apple returned no screenshot specifications.');
  return ScreenshotSpecs.parse(p.data.first);
}

/// `IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE` → `iPhone Dynamic Island Large`, `IPAD_13_PROFILE` → `iPad 13`.
String placementGroupLabel(String? g) {
  if (g == null) return 'Screenshots';
  final words = g.replaceFirst(RegExp(r'_PROFILE$'), '').split('_');
  return words.map((w) {
    switch (w) {
      case 'IPHONE':
        return 'iPhone';
      case 'IPAD':
        return 'iPad';
      case 'TV':
        return 'Apple TV';
      case 'MAC':
        return 'Mac';
      case 'ID':
        return 'ID';
      default:
        return RegExp(r'^\d').hasMatch(w) ? w : w[0] + w.substring(1).toLowerCase();
    }
  }).join(' ');
}

/// Order device groups the way people think of them: phones, then tablets, then the rest.
int placementGroupRank(String g) {
  if (g.startsWith('IPHONE')) return 0;
  if (g.startsWith('IPAD')) return 1;
  if (g.startsWith('MAC')) return 2;
  return 3;
}

/// Pixel size of a PNG or JPEG, read from the file header. Null when the bytes are neither.
({int w, int h})? imageSize(Uint8List b) {
  if (b.length > 24 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    int be(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    return (w: be(16), h: be(20));
  }
  if (b.length > 4 && b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) || marker == 0xFF) {
        i += marker == 0xFF ? 1 : 2;
        continue;
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
      if (isSof) return (h: (b[i + 5] << 8) | b[i + 6], w: (b[i + 7] << 8) | b[i + 8]);
      i += 2 + len;
    }
  }
  return null;
}

Map<String, dynamic> imageReservationBody(String libraryId, String fileName, int fileSize) => {
      'data': {
        'type': 'appAssetLibraryImages',
        'attributes': {'category': screenshotCategory, 'fileName': fileName, 'fileSize': fileSize, 'referenceName': fileName},
        'relationships': {
          'assetLibrary': {'data': {'type': 'appAssetLibraries', 'id': libraryId}},
        },
      },
    };

/// Unlike builds and the classic screenshot endpoints, the library takes no checksum when you confirm the upload.
Map<String, dynamic> imageCommitBody(String id) => {
      'data': {
        'type': 'appAssetLibraryImages',
        'id': id,
        'attributes': {'uploaded': true},
      },
    };

/// Puts an uploaded image on a version localization. No `placementGroup`: Apple derives it from the pixel size.
Map<String, dynamic> placementBody(String imageId, String versionLocId) => {
      'data': {
        'type': 'appAssetLibraryPlacements',
        'attributes': {'placementType': screenshotPlacementType},
        'relationships': {
          'image': {'data': {'type': 'appAssetLibraryImages', 'id': imageId}},
          'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': versionLocId}},
        },
      },
    };

/// The full, ordered list of placement ids for one device group. Replaces the current order.
Map<String, dynamic> placementOrderBody(String group, String versionLocId, List<String> placementIds) => {
      'data': {
        'type': 'appAssetLibraryPlacementOrderingRequests',
        'attributes': {'placementGroup': group},
        'relationships': {
          'orderedPlacements': {
            'data': [for (final id in placementIds) {'type': 'appAssetLibraryPlacements', 'id': id}],
          },
          'appStoreVersionLocalization': {'data': {'type': 'appStoreVersionLocalizations', 'id': versionLocId}},
        },
      },
    };

bool isAllowedScreenshotName(String name) => RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(name);

/// Reserve, upload, confirm and wait for Apple to process one image. Returns the library image id.
Future<String> uploadLibraryImage(
  AscClient client,
  String libraryId,
  String fileName,
  Uint8List bytes, {
  Duration pollEvery = const Duration(seconds: 2),
  Duration giveUpAfter = const Duration(minutes: 3),
}) async {
  final created = (await client.post('/v1/appAssetLibraryImages', imageReservationBody(libraryId, fileName, bytes.length))).data.first;
  final ops = [for (final o in (created.attributes['uploadOperations'] as List? ?? const [])) UploadOp.fromJson((o as Map).cast<String, dynamic>())];
  await putParts(ops, bytes, (_) {});
  await client.patch('/v1/appAssetLibraryImages/${created.id}', imageCommitBody(created.id));

  final deadline = DateTime.now().add(giveUpAfter);
  while (true) {
    final cur = (await client.page('/v1/appAssetLibraryImages/${created.id}')).data.first;
    final state = cur.str('state');
    if (processedImageStates.contains(state)) return created.id;
    if (state == 'FAILED') {
      final details = ((cur.attributes['stateDetails'] as List?) ?? const []).map((e) => (e as Map)['description'] ?? e['code']).join('; ');
      throw AscException('Apple rejected $fileName: ${details.isEmpty ? 'processing failed' : details}');
    }
    if (DateTime.now().isAfter(deadline)) throw AscException('$fileName is still processing after ${giveUpAfter.inMinutes} minutes.');
    await Future<void>.delayed(pollEvery);
  }
}

/// Places [imageId] on the localization and returns the placement id. Apple can still be post-processing an image that
/// reports as processed, so that one error is retried a few times.
Future<String> createPlacement(AscClient client, String imageId, String versionLocId, {Duration retryEvery = const Duration(seconds: 5)}) async {
  for (var attempt = 1;; attempt++) {
    try {
      return (await client.post('/v1/appAssetLibraryPlacements', placementBody(imageId, versionLocId))).data.first.id;
    } on AscException catch (e) {
      final stillProcessing = (e.code ?? '').contains('ASSET_IN_POST_PROCESSING');
      if (!stillProcessing || attempt >= 6) rethrow;
      await Future<void>.delayed(retryEvery);
    }
  }
}
