import 'dart:typed_data';

import 'package:appstore_dashboard/api/listing.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/api/screenshots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only changed fields are sent; null and empty count as equal', () {
    final changed = changedFields(
      {'description': 'old', 'keywords': null, 'whatsNew': 'same'},
      {'description': 'new', 'keywords': '', 'whatsNew': 'same'},
    );
    expect(changed, {'description': 'new'});
  });

  test('live versions only allow promotional text', () {
    expect(isFieldEditable('promotionalText', versionEditable: false), isTrue);
    expect(isFieldEditable('description', versionEditable: false), isFalse);
    expect(isFieldEditable('description', versionEditable: true), isTrue);
    expect(isVersionEditable('PREPARE_FOR_SUBMISSION'), isTrue);
    expect(isVersionEditable('READY_FOR_SALE'), isFalse);
    expect(isVersionEditable(null), isFalse);
  });

  test('length limits are reported by field', () {
    final p = lengthProblems(versionFields, {'promotionalText': 'x' * 171, 'keywords': 'ok'});
    expect(p.single, contains('Promotional text is over 170'));
  });

  test('patch body is JSON:API shaped', () {
    expect(localizationPatchBody('appStoreVersionLocalizations', 'L1', {'whatsNew': 'Bug fixes'}), {
      'data': {
        'type': 'appStoreVersionLocalizations',
        'id': 'L1',
        'attributes': {'whatsNew': 'Bug fixes'},
      },
    });
  });

  test('screenshot labels and thumbnail template', () {
    expect(thumbnailUrl('https://x/{w}x{h}bb.{f}', 1000, 2000, width: 300), 'https://x/300x600bb.png');
    expect(thumbnailUrl(null, 1, 1), isNull);
  });

  test('device group labels', () {
    expect(placementGroupLabel('IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE'), 'iPhone Dynamic Island Large');
    expect(placementGroupLabel('IPAD_13_PROFILE'), 'iPad 13');
    expect(placementGroupLabel('IPHONE_FACE_ID_LARGE_PROFILE'), 'iPhone Face ID Large');
  });

  test('image size is read from PNG and JPEG headers', () {
    final png = Uint8List(
      32,
    )..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, 0, 0, 0x05, 0x0A, 0, 0, 0x0A, 0xEC]);
    expect(imageSize(png), (w: 1290, h: 2796));
    final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 11, 8, 0x0A, 0xEC, 0x05, 0x0A, 3, 0]);
    expect(imageSize(jpg), (w: 1290, h: 2796));
    expect(imageSize(Uint8List.fromList([1, 2, 3, 4, 5, 6])), isNull);
  });

  test('specs map exact sizes to device groups', () {
    final specs = ScreenshotSpecs.parse(
      Resource(
        id: '1',
        type: 'appAssetLibraryRefData',
        relationships: const {},
        attributes: {
          'imageSpecs': [
            {
              'specId': 'a',
              'dimensions': {'minWidth': 1290, 'maxWidth': 1290, 'minHeight': 2796, 'maxHeight': 2796},
            },
            {
              'specId': 'b',
              'dimensions': {'minWidth': 2796, 'maxWidth': 2796, 'minHeight': 1290, 'maxHeight': 1290},
            },
            {
              'specId': 'range',
              'dimensions': {'minWidth': 100, 'maxWidth': 200, 'minHeight': 100, 'maxHeight': 200},
            },
          ],
          'placementTypes': [
            {
              'placementTypeId': 'APP_PREVIEW',
              'specMappings': [
                {
                  'placementGroupId': 'X',
                  'specs': ['a'],
                },
              ],
            },
            {
              'placementTypeId': 'APP_SCREENSHOT',
              'specMappings': [
                {
                  'placementGroupId': 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE',
                  'specs': ['a', 'b', 'range'],
                },
              ],
            },
          ],
        },
      ),
    );
    expect(specs.groups, ['IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE']);
    expect(specs.accepts('IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE', 1290, 2796), isTrue);
    expect(specs.accepts('IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE', 1000, 2000), isFalse);
    expect(specs.groupFor(2796, 1290), 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE');
    expect(specs.sizesLabel('IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE'), '1290×2796');
  });
}
