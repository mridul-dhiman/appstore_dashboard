import 'package:appstore_dashboard/api/pricing.dart';
import 'package:appstore_dashboard/api/territories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> price(String id, String territory, String point, {String? start, String? end}) => {
  'type': 'appPrices',
  'id': id,
  'attributes': {'startDate': start, 'endDate': end},
  'relationships': {
    'territory': {
      'data': {'type': 'territories', 'id': territory},
    },
    'appPricePoint': {
      'data': {'type': 'appPricePoints', 'id': point},
    },
  },
};

Map<String, dynamic> point(String id, String customer, String proceeds) => {
  'type': 'appPricePoints',
  'id': id,
  'attributes': {'customerPrice': customer, 'proceeds': proceeds},
};

Map<String, dynamic> territory(String id, String currency) => {
  'type': 'territories',
  'id': id,
  'attributes': {'currency': currency},
};

void main() {
  test('prices come from their own endpoints with price points and territories, and a manual price wins', () async {
    final f = FakeAsc((r) {
      if (r.path.startsWith('/v1/apps/A/appPriceSchedule')) {
        return json({
          'data': [
            {
              'type': 'appPriceSchedules',
              'id': 'A',
              'attributes': {},
              'relationships': {
                'baseTerritory': {
                  'data': {'type': 'territories', 'id': 'USA'},
                },
              },
            },
          ],
        });
      }
      if (r.path.startsWith('/v1/appPriceSchedules/A/manualPrices')) {
        return json({
          'data': [price('m1', 'USA', 'p1'), price('m2', 'USA', 'p3', start: '2999-01-01'), price('m3', 'GBR', 'p4')],
          'included': [
            point('p1', '4.99', '4.24'),
            point('p3', '5.99', '5.09'),
            point('p4', '3.99', '2.79'),
            territory('USA', 'USD'),
            territory('GBR', 'GBP'),
          ],
        });
      }
      if (r.path.startsWith('/v1/appPriceSchedules/A/automaticPrices')) {
        return json({
          'data': [price('a1', 'GBR', 'p2'), price('a2', 'DEU', 'p5')],
          'included': [point('p2', '4.99', '3.49'), point('p5', '5.99', '4.20'), territory('GBR', 'GBP'), territory('DEU', 'EUR')],
        });
      }
      return null;
    });
    final p = await loadAppPriceSchedule(f.client, 'A');
    final today = DateTime(2026, 6, 1);

    expect(p.baseTerritory, 'USA');
    expect(p.priceIn('USA', today)!.customerPrice, '4.99');
    expect(p.priceIn('GBR', today)!.manual, isTrue, reason: 'the manual GBR price beats the equalised one');
    expect(p.priceIn('DEU', today)!.currency, 'EUR');
    expect(p.baseSchedule.map((x) => x.customerPrice), ['4.99', '5.99'], reason: 'current first, then the scheduled change');
    expect(p.baseSchedule.last.startsAfter(today), isTrue);
    for (final path in f.log.map((r) => r.path).where((x) => x.contains('Prices'))) {
      expect(path, contains('include=appPricePoint%2Cterritory'), reason: 'without include Apple drops the territory');
      expect(path, contains('limit=200'));
    }
  });

  test('availability reads every territory row, not the 50 an include allows', () async {
    final f = FakeAsc((r) {
      if (r.path.startsWith('/v2/appAvailabilities/A/territoryAvailabilities')) {
        return json({
          'data': [
            for (final (id, on) in [('USA', true), ('CHN', false)])
              {
                'type': 'territoryAvailabilities',
                'id': 't$id',
                'attributes': {'available': on},
                'relationships': {
                  'territory': {
                    'data': {'type': 'territories', 'id': id},
                  },
                },
              },
          ],
        });
      }
      if (r.path.startsWith('/v2/appAvailabilities/A')) {
        return json({
          'data': [
            {
              'type': 'appAvailabilities',
              'id': 'A',
              'attributes': {'availableInNewTerritories': true},
            },
          ],
        });
      }
      return null;
    });
    final a = await loadAppAvailability(f.client, 'A');
    expect(a.availableInNewTerritories, isTrue);
    expect(a.territories.map(TerritoryAvailability.territoryOf), ['USA', 'CHN']);
    expect(a.availableCount, 1);
    expect(f.log.every((r) => !r.path.contains('limit%5BterritoryAvailabilities')), isTrue);
    expect(territoryName('CHN'), 'China mainland');
    expect(territoryName('ZZZ'), 'ZZZ');
  });
}
