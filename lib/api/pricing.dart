import 'asc_client.dart';
import 'models.dart';

/// One price: what customers in [territory] pay from [start] until [end] (null = open-ended).
class TerritoryPrice {
  TerritoryPrice({required this.territory, this.currency, this.customerPrice, this.proceeds, required this.manual, this.start, this.end});
  final String territory;
  final String? currency;
  final String? customerPrice;
  final String? proceeds;

  /// Set by the developer, as opposed to Apple's automatic equalisation from the base price.
  final bool manual;
  final DateTime? start;
  final DateTime? end;

  bool activeOn(DateTime day) => (start == null || !start!.isAfter(day)) && (end == null || end!.isAfter(day));
  bool startsAfter(DateTime day) => start != null && start!.isAfter(day);
}

class AppPriceInfo {
  AppPriceInfo({this.baseTerritory, this.manualPrices = const [], this.automaticPrices = const []});
  final String? baseTerritory;
  final List<TerritoryPrice> manualPrices;
  final List<TerritoryPrice> automaticPrices;

  /// The base territory's manual prices, oldest first: the price now and any scheduled change.
  List<TerritoryPrice> get baseSchedule {
    final l = [for (final p in manualPrices) if (p.territory == baseTerritory) p];
    l.sort((a, b) => (a.start ?? DateTime(0)).compareTo(b.start ?? DateTime(0)));
    return l;
  }

  /// The price customers in [territory] pay on [day]: a manual price wins over Apple's equalised one.
  TerritoryPrice? priceIn(String territory, DateTime day) {
    for (final list in [manualPrices, automaticPrices]) {
      for (final p in list) {
        if (p.territory == territory && p.activeOn(day)) return p;
      }
    }
    return null;
  }
}

DateTime? _date(String? s) => s == null ? null : DateTime.tryParse(s);

Future<List<TerritoryPrice>> _prices(AscClient c, String scheduleId, String kind) async {
  final p = await c.all('/v1/appPriceSchedules/$scheduleId/$kind', {
    'include': 'appPricePoint,territory',
    'fields[appPricePoints]': 'customerPrice,proceeds',
    'fields[territories]': 'currency',
    'limit': '200',
  }, 3);
  return [
    for (final r in p.data)
      if (r.relId('territory') case final territory?)
        TerritoryPrice(
          territory: territory,
          currency: p.inc('territories', territory)?.str('currency'),
          customerPrice: p.inc('appPricePoints', r.relId('appPricePoint'))?.str('customerPrice'),
          proceeds: p.inc('appPricePoints', r.relId('appPricePoint'))?.str('proceeds'),
          manual: kind == 'manualPrices',
          start: _date(r.str('startDate')),
          end: _date(r.str('endDate')),
        ),
  ];
}

/// The app's price schedule. Apple's automatic prices are one per territory (about 175), so both lists are read from
/// their own endpoints rather than as an include, which Apple caps.
Future<AppPriceInfo> loadAppPriceSchedule(AscClient c, String appId) async {
  final p = await nullIfMissing(c.page('/v1/apps/$appId/appPriceSchedule', {'include': 'baseTerritory'}));
  if (p == null || p.data.isEmpty) return AppPriceInfo();
  final id = p.data.first.id;
  final r = await Future.wait([_prices(c, id, 'manualPrices'), _prices(c, id, 'automaticPrices')]);
  return AppPriceInfo(baseTerritory: p.data.first.relId('baseTerritory'), manualPrices: r[0], automaticPrices: r[1]);
}

class TerritoryAvailability {
  TerritoryAvailability({this.territories = const [], this.availableInNewTerritories = false});

  /// Every territory row, available or not; see [isAvailable].
  final List<Resource> territories;
  final bool availableInNewTerritories;

  static String territoryOf(Resource row) => row.relId('territory') ?? row.id;
  static bool isAvailable(Resource row) => row.flag('available') ?? false;

  int get availableCount => territories.where(isAvailable).length;
}

/// Where the app is on sale. Apple caps an included list at 50, so the full list (about 175) is read from its own
/// endpoint; `include=territory` is needed or Apple leaves out which territory each row is.
Future<TerritoryAvailability> loadAppAvailability(AscClient c, String appId) async {
  final p = await nullIfMissing(c.page('/v2/appAvailabilities/$appId'));
  if (p == null || p.data.isEmpty) return TerritoryAvailability();
  final rows = await c.all('/v2/appAvailabilities/$appId/territoryAvailabilities', {'include': 'territory', 'limit': '200'}, 2);
  return TerritoryAvailability(availableInNewTerritories: p.data.first.flag('availableInNewTerritories') ?? false, territories: rows.data);
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
