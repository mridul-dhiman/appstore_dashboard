import 'package:appstore_dashboard/api/iap_creator.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

import 'package:http/http.dart' as http;

Resource point(String id, String price) =>
    Resource(id: id, type: 'inAppPurchasePricePoints', attributes: {'customerPrice': price}, relationships: const {});

void main() {
  final spec = IapSpec(productId: 'com.x.pro', referenceName: 'Pro', displayName: 'Pro Plan', description: 'Unlocks everything', price: 99);

  test('create body matches the v2 schema (type, attributes, app relationship)', () {
    final b = iapCreateBody('123', spec)['data'] as Map;
    expect(b['type'], 'inAppPurchases');
    expect(b['attributes'], {'name': 'Pro', 'productId': 'com.x.pro', 'inAppPurchaseType': 'NON_CONSUMABLE', 'familySharable': false});
    expect((b['relationships'] as Map)['app'], {
      'data': {'type': 'apps', 'id': '123'},
    });
  });

  test('localization body points at the IAP through inAppPurchaseV2', () {
    final b = iapLocalizationBody('iap1', spec)['data'] as Map;
    expect(b['attributes'], {'name': 'Pro Plan', 'locale': 'en-US', 'description': 'Unlocks everything'});
    expect(((b['relationships'] as Map)['inAppPurchaseV2'] as Map)['data'], {'type': 'inAppPurchases', 'id': 'iap1'});
  });

  test('price point: lowest at or above target, else highest, skipping free', () {
    final pts = [point('a', '0.00'), point('b', '49.00'), point('c', '99.00'), point('d', '149.00')];
    expect(pickPricePoint(pts, 60)!.id, 'c');
    expect(pickPricePoint(pts, 99)!.id, 'c');
    expect(pickPricePoint(pts, 500)!.id, 'd');
    expect(pickPricePoint([point('z', '0.00')], 10), isNull);
  });

  test('price schedule uses an inline price referenced by a temp id', () {
    final b = iapPriceScheduleBody('iap1', 'IND', 'pp9');
    final inc = (b['included'] as List).single as Map;
    expect(inc['id'], r'${price1}');
    expect((((b['data'] as Map)['relationships'] as Map)['manualPrices'] as Map)['data'], [
      {'type': 'inAppPurchasePrices', 'id': r'${price1}'},
    ]);
    expect(((inc['relationships'] as Map)['inAppPurchasePricePoint'] as Map)['data'], {'type': 'inAppPurchasePricePoints', 'id': 'pp9'});
  });

  test('availability lists every territory', () {
    final b = iapAvailabilityBody('iap1', ['USA', 'IND'])['data'] as Map;
    expect(((b['relationships'] as Map)['availableTerritories'] as Map)['data'], [
      {'type': 'territories', 'id': 'USA'},
      {'type': 'territories', 'id': 'IND'},
    ]);
  });

  test('validation catches Apple limits', () {
    final bad = IapSpec(productId: 'has space', referenceName: 'r', displayName: 'x' * 31, description: 'y' * 46, price: -1);
    final e = bad.validate().join(' | ');
    expect(e, contains('Product ID may only'));
    expect(e, contains('Display name is over'));
    expect(e, contains('Description is over'));
    expect(e, contains('Price must be above 0'));
    expect(spec.validate(), isEmpty);
  });

  test('CSV: quotes, commas in fields, header aliases, defaults', () {
    const csv =
        'Product ID,Name,Description,Price,Type\n'
        'com.x.a,"Plan, Gold","Says ""hi""",99,\n'
        'com.x.b,Silver,,149.5,consumable\n';
    final r = parseIapCsv(csv);
    expect(r.errors, isEmpty);
    expect(r.specs.length, 2);
    expect(r.specs[0].displayName, 'Plan, Gold');
    expect(r.specs[0].description, 'Says "hi"');
    expect(r.specs[0].type, 'NON_CONSUMABLE');
    expect(r.specs[1].description, 'Silver'); // falls back to the display name
    expect(r.specs[1].price, 149.5);
    expect(r.specs[1].type, 'CONSUMABLE');
  });

  test('CSV: bad rows are reported by line and good rows still parse', () {
    const csv =
        'product_id,display_name,price\n'
        'com.x.ok,Fine,10\n'
        'bad id,Oops,10\n'
        'com.x.ok,Dup,10\n'
        'com.x.nan,Text price,abc\n';
    final r = parseIapCsv(csv);
    expect(r.specs.map((s) => s.productId), ['com.x.ok']);
    expect(r.errors.length, 3);
    expect(r.errors.any((e) => e.startsWith('Line 3')), isTrue);
    expect(r.errors.any((e) => e.contains('Duplicate')), isTrue);
    expect(r.errors.any((e) => e.contains('not a number')), isTrue);
  });

  test('CSV: missing required columns is a single clear error', () {
    expect(parseIapCsv('a,b\n1,2\n').errors.single, contains('Missing required column'));
  });

  group('creating against a mock server (never Apple: IAPs can not be deleted)', () {
    final spec = IapSpec(
      productId: 'coins.100',
      referenceName: 'Coins 100',
      type: 'CONSUMABLE',
      displayName: '100 Coins',
      description: 'A pile',
      price: 0.99,
    );
    const opts = IapOptions(allTerritories: true);

    http.Response? server(Recorded r, {Map<String, dynamic>? existing, bool hasLoc = false, bool hasPrice = false}) {
      final p = r.path.split('?').first;
      if (r.method == 'GET' && p == '/v1/apps/A1/inAppPurchasesV2') {
        return json({
          'data': [?existing],
        });
      }
      if (r.method == 'GET' && p == '/v2/inAppPurchases/I1/inAppPurchaseLocalizations') {
        return json({
          'data': [
            if (hasLoc)
              {
                'type': 'inAppPurchaseLocalizations',
                'id': 'L1',
                'attributes': {'locale': 'en-US'},
              },
          ],
        });
      }
      if (r.method == 'GET' && p == '/v2/inAppPurchases/I1/iapPriceSchedule') {
        return hasPrice
            ? json({
                'data': {'type': 'inAppPurchasePriceSchedules', 'id': 'S1'},
              })
            : apiError(404, 'Not found', 'none');
      }
      if (r.method == 'GET' && p == '/v2/inAppPurchases/I1/inAppPurchaseAvailability') return apiError(404, 'Not found', 'none');
      if (r.method == 'GET' && p == '/v2/inAppPurchases/I1/pricePoints') {
        return json({
          'data': [
            {
              'type': 'inAppPurchasePricePoints',
              'id': 'PP1',
              'attributes': {'customerPrice': '0.99'},
            },
          ],
        });
      }
      if (r.method == 'GET' && p == '/v1/territories') {
        return json({
          'data': [
            {'type': 'territories', 'id': 'USA'},
          ],
        });
      }
      if (r.method == 'POST' && p == '/v2/inAppPurchases') {
        return json({
          'data': {'type': 'inAppPurchases', 'id': 'I1'},
        }, 201);
      }
      if (r.method == 'POST') {
        return json({
          'data': {'type': 'x', 'id': 'N'},
        }, 201);
      }
      return null;
    }

    List<String> writes(FakeAsc f) => [
      for (final r in f.log)
        if (r.method != 'GET') '${r.method} ${r.path}',
    ];

    test('a new product ID: looked up first, then created with every step', () async {
      final fake = FakeAsc((r) => server(r));
      final res = await IapCreator(fake.client, 'A1', opts).create(spec);
      expect(res.ok, isTrue, reason: res.error);
      expect(fake.log.first.path, contains('filter%5BproductId%5D=coins.100'));
      expect(writes(fake), [
        'POST /v2/inAppPurchases',
        'POST /v1/inAppPurchaseLocalizations',
        'POST /v1/inAppPurchasePriceSchedules',
        'POST /v1/inAppPurchaseAvailabilities',
      ]);
    });

    test('a product left half-made by an earlier run is finished, not created again', () async {
      final existing = {
        'type': 'inAppPurchases',
        'id': 'I1',
        'attributes': {'productId': 'coins.100', 'inAppPurchaseType': 'CONSUMABLE'},
      };
      final fake = FakeAsc((r) => server(r, existing: existing, hasLoc: true));
      final res = await IapCreator(fake.client, 'A1', opts).create(spec);
      expect(res.ok, isTrue, reason: res.error);
      expect(res.id, 'I1');
      expect(writes(fake), [
        'POST /v1/inAppPurchasePriceSchedules',
        'POST /v1/inAppPurchaseAvailabilities',
      ], reason: 'no second product, no second localization');
    });

    test('the same product ID with another type is refused before anything is written', () async {
      final existing = {
        'type': 'inAppPurchases',
        'id': 'I1',
        'attributes': {'productId': 'coins.100', 'inAppPurchaseType': 'NON_CONSUMABLE'},
      };
      final fake = FakeAsc((r) => server(r, existing: existing));
      final res = await IapCreator(fake.client, 'A1', opts).create(spec);
      expect(res.ok, isFalse);
      expect(res.error, contains('already exists'));
      expect(writes(fake), isEmpty);
    });
  });
}
