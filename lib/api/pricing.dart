import 'asc_client.dart';
import 'models.dart';

class AppPriceInfo {
  AppPriceInfo({this.baseTerritory, this.manualPrices = const [], this.automaticPrices = const []});
  final Resource? baseTerritory;
  final List<Resource> manualPrices;
  final List<Resource> automaticPrices;
}

Future<AppPriceInfo> loadAppPriceSchedule(AscClient c, String appId) async {
  final p = await nullIfMissing(c.page('/v1/apps/$appId/appPriceSchedule', {
    'include': 'manualPrices,automaticPrices,baseTerritory',
    'fields[appPrices]': 'startDate,endDate,manual,appPriceTier',
    'limit[manualPrices]': '20',
    'limit[automaticPrices]': '20',
  }));
  if (p == null || p.data.isEmpty) return AppPriceInfo();
  final sched = p.data.first;
  return AppPriceInfo(
    baseTerritory: p.inc('territories', sched.relId('baseTerritory')),
    manualPrices: [for (final id in sched.relIds('manualPrices')) ?p.inc('appPrices', id)],
    automaticPrices: [for (final id in sched.relIds('automaticPrices')) ?p.inc('appPrices', id)],
  );
}

class TerritoryAvailability {
  TerritoryAvailability({this.territories = const [], this.availableInNewTerritories = false});
  final List<Resource> territories;
  final bool availableInNewTerritories;
}

Future<TerritoryAvailability> loadAppAvailability(AscClient c, String appId) async {
  final p = await nullIfMissing(c.page('/v2/appAvailabilities/$appId', {
    'include': 'territoryAvailabilities',
    'limit[territoryAvailabilities]': '200',
  }));
  if (p == null || p.data.isEmpty) {
    return TerritoryAvailability();
  }
  final avail = p.data.first;
  return TerritoryAvailability(
    availableInNewTerritories: avail.flag('availableInNewTerritories') ?? false,
    territories: [for (final id in avail.relIds('territoryAvailabilities')) ?p.inc('territoryAvailabilities', id)],
  );
}

/// Apple's price tiers for a territory.
Future<List<Resource>> loadAppPricePoints(AscClient c, String appId, String territoryId) async =>
    (await c.all('/v1/apps/$appId/appPricePoints', {
      'filter[territory]': territoryId,
      'limit': '200',
      'fields[appPricePoints]': 'customerPrice,proceeds,priceTier',
    }, 4))
        .data;

Map<String, dynamic> appPriceScheduleBody(String appId, String territory, String pricePointId) => {
  'data': {
    'type': 'appPriceSchedules',
    'relationships': {
      'app': {
        'data': {'type': 'apps', 'id': appId},
      },
      'manualPrices': {
        'data': [
          {'type': 'appPrices', 'id': r'${price1}'},
        ],
      },
      'baseTerritory': {
        'data': {'type': 'territories', 'id': territory},
      },
    },
  },
  'included': [
    {
      'type': 'appPrices',
      'id': r'${price1}',
      'attributes': {'startDate': null},
      'relationships': {
        'appPricePoint': {
          'data': {'type': 'appPricePoints', 'id': pricePointId},
        },
      },
    },
  ],
};

Future<void> setAppPrice(AscClient c, String appId, String territory, String pricePointId) =>
    c.post('/v1/appPriceSchedules', appPriceScheduleBody(appId, territory, pricePointId));
