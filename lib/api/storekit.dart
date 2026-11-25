import 'dart:convert';

import 'asc_client.dart';
import 'models.dart';

// An Xcode StoreKit Configuration File (.storekit) built from the app's in-app purchases and subscriptions, so purchases
// can be tested in the simulator and in Xcode without App Store Connect or a sandbox account. Prices are those of one
// storefront. The file is a plain local one (not "synced"), so it can be edited in Xcode.

class SkLocalization {
  const SkLocalization(this.locale, this.displayName, this.description);
  final String locale; // en_US, as Xcode writes it (App Store Connect says en-US)
  final String displayName;
  final String description;

  Map<String, Object?> toJson() => {'description': description, 'displayName': displayName, 'locale': locale};
}

class SkProduct {
  const SkProduct({
    required this.id,
    required this.productId,
    required this.referenceName,
    required this.type,
    this.familySharable = false,
    this.price,
    this.localizations = const [],
    this.period,
    this.groupLevel,
  });

  final String id; // App Store Connect id, kept as Xcode's internalID
  final String productId;
  final String referenceName;
  final String type; // App Store Connect type: CONSUMABLE, NON_CONSUMABLE, NON_RENEWING_SUBSCRIPTION, or AUTO_RENEWABLE
  final bool familySharable;
  final double? price; // in the storefront's currency; null when no price is set there
  final List<SkLocalization> localizations;
  final String? period; // subscriptions: ONE_MONTH …
  final int? groupLevel; // subscriptions: rank within the group, 1 = highest
}

class SkGroup {
  const SkGroup(this.id, this.name, this.subscriptions);
  final String id;
  final String name;
  final List<SkProduct> subscriptions;
}

/// Xcode's product type for an App Store Connect one.
String skType(String type) => switch (type) {
  'CONSUMABLE' => 'Consumable',
  'NON_RENEWING_SUBSCRIPTION' => 'NonRenewingSubscription',
  'AUTO_RENEWABLE' => 'RecurringSubscription',
  _ => 'NonConsumable',
};

/// ISO 8601 duration for an App Store Connect subscription period.
String skPeriod(String? period) => switch (period) {
  'ONE_WEEK' => 'P1W',
  'TWO_MONTHS' => 'P2M',
  'THREE_MONTHS' => 'P3M',
  'SIX_MONTHS' => 'P6M',
  'ONE_YEAR' => 'P1Y',
  _ => 'P1M',
};

String skLocale(String? locale) => (locale == null || locale.isEmpty ? 'en-US' : locale).replaceAll('-', '_');

/// Xcode writes prices as plain decimals ("0.99", "1949"). No price is written as 0.
String skPrice(double? p) {
  if (p == null) return '0.00';
  return p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2);
}

/// Stable 8-character file identifier for an app, so exporting the same app twice gives the same file.
String skIdentifier(String appId) {
  var h = 0x811c9dc5;
  for (final c in utf8.encode(appId)) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).toUpperCase().padLeft(8, '0');
}

Map<String, Object?> _product(SkProduct p) => {
  'displayPrice': skPrice(p.price),
  'familyShareable': p.familySharable,
  'internalID': p.id,
  'localizations': [for (final l in p.localizations) l.toJson()],
  'productID': p.productId,
  'referenceName': p.referenceName,
  'type': skType(p.type),
};

Map<String, Object?> _subscription(SkProduct s, String groupId) => {
  'adHocOffers': const [],
  'codeOffers': const [],
  'displayPrice': skPrice(s.price),
  'familyShareable': s.familySharable,
  'groupNumber': s.groupLevel ?? 1,
  'internalID': s.id,
  'introductoryOffer': null,
  'localizations': [for (final l in s.localizations) l.toJson()],
  'productID': s.productId,
  'recurringSubscriptionPeriod': skPeriod(s.period),
  'referenceName': s.referenceName,
  'subscriptionGroupID': groupId,
  'type': 'RecurringSubscription',
  'winbackOffers': const [],
};

/// The .storekit document. [storefront] is a three-letter territory code (IND, USA …), as Xcode stores it.
Map<String, Object?> storeKitConfig({
  required String appId,
  required String storefront,
  required List<SkProduct> products,
  List<SkGroup> groups = const [],
  String locale = 'en_US',
}) {
  final byId = [...products]..sort((a, b) => a.productId.compareTo(b.productId));
  return {
    'identifier': skIdentifier(appId),
    'nonRenewingSubscriptions': [
      for (final p in byId)
        if (p.type == 'NON_RENEWING_SUBSCRIPTION') _product(p),
    ],
    'products': [
      for (final p in byId)
        if (p.type != 'NON_RENEWING_SUBSCRIPTION') _product(p),
    ],
    'settings': {'_failTransactionsEnabled': false, '_locale': locale, '_storefront': storefront},
    'subscriptionGroups': [
      for (final g in groups)
        {
          'id': g.id,
          'localizations': const [],
          'name': g.name,
          'subscriptions': [for (final s in g.subscriptions) _subscription(s, g.id)],
        },
    ],
    'version': {'major': 4, 'minor': 0},
  };
}

String storeKitJson(Map<String, Object?> config) => '${const JsonEncoder.withIndent('  ').convert(config)}\n';

// ---- Loading from App Store Connect ----

/// What an export produced, for the file and for telling the user what is in it.
class StoreKitExport {
  StoreKitExport(this.storefront, this.products, this.groups);
  final String storefront;
  final List<SkProduct> products;
  final List<SkGroup> groups;

  int get count => products.length + groups.fold(0, (n, g) => n + g.subscriptions.length);
  int get unpriced => [...products, for (final g in groups) ...g.subscriptions].where((p) => p.price == null).length;
}

/// The price in force today among [prices] (each with optional startDate / endDate), via its included price point.
double? currentPrice(ResourcePage prices, String pointType, String pointRel, {DateTime? now}) {
  final today = now ?? DateTime.now();
  Resource? best;
  DateTime? bestStart;
  for (final p in prices.data) {
    final start = p.date('startDate');
    final end = p.date('endDate');
    if (start != null && start.isAfter(today)) continue;
    if (end != null && !end.isAfter(today)) continue;
    if (best == null || (start != null && (bestStart == null || start.isAfter(bestStart)))) {
      best = p;
      bestStart = start;
    }
  }
  final point = prices.inc(pointType, best?.relId(pointRel));
  return double.tryParse(point?.str('customerPrice') ?? '');
}

List<SkLocalization> _locs(Iterable<Resource> locs) => [
  for (final l in locs) SkLocalization(skLocale(l.str('locale')), l.str('name') ?? '', l.str('description') ?? ''),
];

/// Runs [jobs] a few at a time, so dozens of products do not fire dozens of requests at once.
Future<List<T>> _pooled<T>(List<Future<T> Function()> jobs, {int concurrency = 4}) async {
  final out = List<T?>.filled(jobs.length, null);
  var next = 0;
  Future<void> worker() async {
    while (next < jobs.length) {
      final i = next++;
      out[i] = await jobs[i]();
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);
  return out.cast<T>();
}

/// Loads everything a .storekit file needs. Without a [storefront], the first product's base territory is used (where
/// its price was set), falling back to USA.
Future<StoreKitExport> loadStoreKitExport(AscClient c, String appId, {String? storefront}) async {
  final iaps = await c.all('/v1/apps/$appId/inAppPurchasesV2', {
    'limit': '200',
    'include': 'inAppPurchaseLocalizations',
    'limit[inAppPurchaseLocalizations]': '50',
  }, 2);
  final groups = await c.all('/v1/apps/$appId/subscriptionGroups', {'limit': '50', 'include': 'subscriptions'}, 1);

  var front = storefront;
  if (front == null && iaps.data.isNotEmpty) {
    final base = await nullIfMissing(c.page('/v1/inAppPurchasePriceSchedules/${iaps.data.first.id}/baseTerritory'));
    front = base?.data.firstOrNull?.id;
  }
  front ??= 'USA';
  final territory = front;

  Future<double?> iapPrice(String id) async {
    Future<double?> from(String kind) async {
      final page = await nullIfMissing(
        c.all('/v1/inAppPurchasePriceSchedules/$id/$kind', {
          'filter[territory]': territory,
          'include': 'inAppPurchasePricePoint',
          'fields[inAppPurchasePricePoints]': 'customerPrice',
          'limit': '50',
        }, 1),
      );
      return page == null ? null : currentPrice(page, 'inAppPurchasePricePoints', 'inAppPurchasePricePoint');
    }

    return await from('manualPrices') ?? await from('automaticPrices');
  }

  final products = await _pooled([
    for (final i in iaps.data)
      () async => SkProduct(
        id: i.id,
        productId: i.str('productId') ?? '',
        referenceName: i.str('name') ?? '',
        type: i.str('inAppPurchaseType') ?? 'NON_CONSUMABLE',
        familySharable: i.flag('familySharable') ?? false,
        price: await iapPrice(i.id),
        localizations: _locs(
          i.relIds('inAppPurchaseLocalizations').map((id) => iaps.inc('inAppPurchaseLocalizations', id)).whereType<Resource>(),
        ),
      ),
  ]);

  final skGroups = <SkGroup>[];
  for (final g in groups.data) {
    final subs = g.relIds('subscriptions').map((id) => groups.inc('subscriptions', id)).whereType<Resource>().toList();
    final built = await _pooled([
      for (final s in subs)
        () async {
          final r = await Future.wait([
            c.all('/v1/subscriptions/${s.id}/subscriptionLocalizations', {'limit': '50'}, 1),
            c.all('/v1/subscriptions/${s.id}/prices', {
              'filter[territory]': territory,
              'include': 'subscriptionPricePoint',
              'fields[subscriptionPricePoints]': 'customerPrice',
              'limit': '50',
            }, 1),
          ]);
          return SkProduct(
            id: s.id,
            productId: s.str('productId') ?? '',
            referenceName: s.str('name') ?? '',
            type: 'AUTO_RENEWABLE',
            familySharable: s.flag('familySharable') ?? false,
            price: currentPrice(r[1], 'subscriptionPricePoints', 'subscriptionPricePoint'),
            localizations: _locs(r[0].data),
            period: s.str('subscriptionPeriod'),
            groupLevel: s.integer('groupLevel'),
          );
        },
    ]);
    built.sort((a, b) => (a.groupLevel ?? 0).compareTo(b.groupLevel ?? 0));
    skGroups.add(SkGroup(g.id, g.str('referenceName') ?? 'Subscriptions', built));
  }
  return StoreKitExport(territory, products, skGroups);
}
