import 'dart:convert';

import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/api/storekit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

void main() {
  test('mapping of types, periods, locales and prices', () {
    expect(skType('CONSUMABLE'), 'Consumable');
    expect(skType('NON_CONSUMABLE'), 'NonConsumable');
    expect(skType('NON_RENEWING_SUBSCRIPTION'), 'NonRenewingSubscription');
    expect(skPeriod('ONE_YEAR'), 'P1Y');
    expect(skPeriod('ONE_WEEK'), 'P1W');
    expect(skLocale('en-US'), 'en_US');
    expect(skLocale(null), 'en_US');
    expect(skPrice(909), '909');
    expect(skPrice(0.99), '0.99');
    expect(skPrice(null), '0.00');
    expect(skIdentifier('6446213422'), skIdentifier('6446213422'));
    expect(skIdentifier('6446213422'), matches(RegExp(r'^[0-9A-F]{8}$')));
  });

  test('the document has Xcode\'s shape: products, non-renewing apart, subscription groups', () {
    final doc = storeKitConfig(
      appId: 'A1',
      storefront: 'IND',
      products: const [
        SkProduct(id: '2', productId: 'b.pass', referenceName: 'Pass', type: 'NON_RENEWING_SUBSCRIPTION', price: 99),
        SkProduct(
          id: '1',
          productId: 'a.plan',
          referenceName: 'Plan',
          type: 'CONSUMABLE',
          price: 1949,
          localizations: [SkLocalization('en_US', 'Plan', 'Buys the plan')],
        ),
      ],
      groups: const [
        SkGroup('G1', 'Premium', [
          SkProduct(
            id: '3',
            productId: 'c.month',
            referenceName: 'Monthly',
            type: 'AUTO_RENEWABLE',
            price: 4.99,
            period: 'ONE_MONTH',
            groupLevel: 1,
          ),
        ]),
      ],
    );
    final products = doc['products'] as List;
    expect(products.single, {
      'displayPrice': '1949',
      'familyShareable': false,
      'internalID': '1',
      'localizations': [
        {'description': 'Buys the plan', 'displayName': 'Plan', 'locale': 'en_US'},
      ],
      'productID': 'a.plan',
      'referenceName': 'Plan',
      'type': 'Consumable',
    });
    expect(((doc['nonRenewingSubscriptions'] as List).single as Map)['type'], 'NonRenewingSubscription');
    final sub = (((doc['subscriptionGroups'] as List).single as Map)['subscriptions'] as List).single as Map;
    expect(sub['recurringSubscriptionPeriod'], 'P1M');
    expect(sub['subscriptionGroupID'], 'G1');
    expect(sub['displayPrice'], '4.99');
    expect((doc['settings'] as Map)['_storefront'], 'IND');
    expect(doc['version'], {'major': 4, 'minor': 0});
    expect(jsonDecode(storeKitJson(doc)), doc); // plain JSON, as Xcode reads it
  });

  test('current price skips future and ended prices', () {
    Resource price(String id, String? start, String? end, String point) => Resource(
      id: id,
      type: 'inAppPurchasePrices',
      attributes: {'startDate': start, 'endDate': end},
      relationships: {
        'inAppPurchasePricePoint': {
          'data': {'type': 'inAppPurchasePricePoints', 'id': point},
        },
      },
    );
    Resource point(String id, String p) =>
        Resource(id: id, type: 'inAppPurchasePricePoints', attributes: {'customerPrice': p}, relationships: const {});
    final page = ResourcePage(
      data: [price('old', null, '2026-01-01', 'p1'), price('now', '2026-01-01', null, 'p2'), price('later', '2027-01-01', null, 'p3')],
      included: {
        for (final p in [point('p1', '10.0'), point('p2', '20.0'), point('p3', '30.0')]) 'inAppPurchasePricePoints/${p.id}': p,
      },
    );
    expect(currentPrice(page, 'inAppPurchasePricePoints', 'inAppPurchasePricePoint', now: DateTime(2026, 6, 1)), 20);
    expect(currentPrice(ResourcePage(data: const []), 'inAppPurchasePricePoints', 'inAppPurchasePricePoint'), isNull);
  });

  test('loading: base territory, manual price with automatic fallback, localizations', () async {
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (p == '/v1/apps/A1/inAppPurchasesV2') {
        return json({
          'data': [
            for (final id in ['I1', 'I2'])
              {
                'type': 'inAppPurchases',
                'id': id,
                'attributes': {'productId': 'com.x.$id', 'name': 'Ref $id', 'inAppPurchaseType': 'CONSUMABLE', 'familySharable': false},
                'relationships': {
                  'inAppPurchaseLocalizations': {
                    'data': [
                      {'type': 'inAppPurchaseLocalizations', 'id': 'L$id'},
                    ],
                  },
                },
              },
          ],
          'included': [
            for (final id in ['I1', 'I2'])
              {
                'type': 'inAppPurchaseLocalizations',
                'id': 'L$id',
                'attributes': {'locale': 'en-US', 'name': 'Name $id', 'description': 'Desc $id'},
              },
          ],
        });
      }
      if (p == '/v1/apps/A1/subscriptionGroups') return json({'data': []});
      if (p == '/v1/inAppPurchasePriceSchedules/I1/baseTerritory') {
        return json({
          'data': {'type': 'territories', 'id': 'IND'},
        });
      }
      Map<String, Object> priced(String point, String price) => {
        'data': [
          {
            'type': 'inAppPurchasePrices',
            'id': 'x',
            'attributes': {'startDate': null, 'endDate': null},
            'relationships': {
              'inAppPurchasePricePoint': {
                'data': {'type': 'inAppPurchasePricePoints', 'id': point},
              },
            },
          },
        ],
        'included': [
          {
            'type': 'inAppPurchasePricePoints',
            'id': point,
            'attributes': {'customerPrice': price},
          },
        ],
      };
      if (p == '/v1/inAppPurchasePriceSchedules/I1/manualPrices') return json(priced('pp1', '909.0'));
      if (p == '/v1/inAppPurchasePriceSchedules/I2/manualPrices') return json({'data': []});
      if (p == '/v1/inAppPurchasePriceSchedules/I2/automaticPrices') return json(priced('pp2', '65.0'));
      return null;
    });
    final x = await loadStoreKitExport(fake.client, 'A1');
    expect(x.storefront, 'IND');
    expect(x.products.map((p) => p.price), [909, 65]);
    expect(x.products.first.localizations.single.locale, 'en_US');
    expect(x.products.first.localizations.single.displayName, 'Name I1');
    expect(x.unpriced, 0);
    expect(fake.log.where((r) => r.path.contains('manualPrices')).every((r) => r.path.contains('filter%5Bterritory%5D=IND')), isTrue);
  });
}
