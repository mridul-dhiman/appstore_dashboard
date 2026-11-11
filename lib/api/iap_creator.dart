import 'asc_client.dart';
import 'models.dart';

/// Apple's limits for IAP metadata.
const iapNameMax = 30; // customer-facing display name
const iapDescriptionMax = 45;
const iapReferenceMax = 64; // internal reference name

const iapTypes = {'CONSUMABLE': 'Consumable', 'NON_CONSUMABLE': 'Non-consumable', 'NON_RENEWING_SUBSCRIPTION': 'Non-renewing subscription'};

/// One in-app purchase to create.
class IapSpec {
  IapSpec({
    required this.productId,
    required this.referenceName,
    this.type = 'NON_CONSUMABLE',
    required this.displayName,
    required this.description,
    this.locale = 'en-US',
    this.price,
    this.reviewNote = '',
    this.familySharable = false,
  });

  final String productId;
  final String referenceName;
  final String type;
  final String displayName;
  final String description;
  final String locale;

  /// Target price in the base territory's currency. The lowest Apple price point at or above it is used. Null = no price.
  final double? price;
  final String reviewNote;
  final bool familySharable;

  /// Problems that would make Apple reject it, found before any request is made.
  List<String> validate() {
    final e = <String>[];
    if (productId.trim().isEmpty) {
      e.add('Product ID is required.');
    } else if (!RegExp(r'^[A-Za-z0-9._]+$').hasMatch(productId)) {
      e.add('Product ID may only contain letters, digits, "." and "_".');
    }
    if (referenceName.trim().isEmpty) e.add('Reference name is required.');
    if (referenceName.length > iapReferenceMax) e.add('Reference name is over $iapReferenceMax characters.');
    if (!iapTypes.containsKey(type)) e.add('Type must be one of ${iapTypes.keys.join(', ')}.');
    if (displayName.trim().isEmpty) e.add('Display name is required.');
    if (displayName.length > iapNameMax) e.add('Display name is over $iapNameMax characters (${displayName.length}).');
    if (description.length > iapDescriptionMax) e.add('Description is over $iapDescriptionMax characters (${description.length}).');
    if (price != null && price! <= 0) e.add('Price must be above 0.');
    return e;
  }
}

class IapOptions {
  const IapOptions({this.baseTerritory = 'USA', this.allTerritories = true});

  /// Three-letter territory code the `price` is expressed in (USA, IND, GBR …).
  final String baseTerritory;

  /// Make each IAP available in every territory (a new IAP is not sellable until availability is set).
  final bool allTerritories;
}

// ---- Request bodies (shapes checked against Apple's OpenAPI spec) -------------------------------------------------

Map<String, dynamic> iapCreateBody(String appId, IapSpec s) => {
  'data': {
    'type': 'inAppPurchases',
    'attributes': {
      'name': s.referenceName,
      'productId': s.productId,
      'inAppPurchaseType': s.type,
      'familySharable': s.familySharable,
      if (s.reviewNote.trim().isNotEmpty) 'reviewNote': s.reviewNote.trim(),
    },
    'relationships': {
      'app': {
        'data': {'type': 'apps', 'id': appId},
      },
    },
  },
};

Map<String, dynamic> iapLocalizationBody(String iapId, IapSpec s) => {
  'data': {
    'type': 'inAppPurchaseLocalizations',
    'attributes': {'name': s.displayName, 'locale': s.locale, 'description': s.description},
    'relationships': {
      'inAppPurchaseV2': {
        'data': {'type': 'inAppPurchases', 'id': iapId},
      },
    },
  },
};

/// Lowest price point at or above [target] (round UP to the next tier), else the highest one. Free (0) points are skipped.
Resource? pickPricePoint(List<Resource> points, double target) {
  final priced = [
    for (final p in points)
      if ((double.tryParse(p.str('customerPrice') ?? '') ?? 0) > 0) (p, double.parse(p.str('customerPrice')!)),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  if (priced.isEmpty) return null;
  return priced.firstWhere((x) => x.$2 >= target, orElse: () => priced.last).$1;
}

Map<String, dynamic> iapPriceScheduleBody(String iapId, String territory, String pricePointId) => {
  'data': {
    'type': 'inAppPurchasePriceSchedules',
    'relationships': {
      'inAppPurchase': {
        'data': {'type': 'inAppPurchases', 'id': iapId},
      },
      'manualPrices': {
        'data': [
          {'type': 'inAppPurchasePrices', 'id': r'${price1}'},
        ],
      },
      'baseTerritory': {
        'data': {'type': 'territories', 'id': territory},
      },
    },
  },
  'included': [
    {
      'type': 'inAppPurchasePrices',
      'id': r'${price1}',
      'attributes': {'startDate': null},
      'relationships': {
        'inAppPurchaseV2': {
          'data': {'type': 'inAppPurchases', 'id': iapId},
        },
        'inAppPurchasePricePoint': {
          'data': {'type': 'inAppPurchasePricePoints', 'id': pricePointId},
        },
      },
    },
  ],
};

Map<String, dynamic> iapAvailabilityBody(String iapId, List<String> territoryIds) => {
  'data': {
    'type': 'inAppPurchaseAvailabilities',
    'attributes': {'availableInNewTerritories': true},
    'relationships': {
      'inAppPurchase': {
        'data': {'type': 'inAppPurchases', 'id': iapId},
      },
      'availableTerritories': {
        'data': [
          for (final t in territoryIds) {'type': 'territories', 'id': t},
        ],
      },
    },
  },
};

// ---- Running it ---------------------------------------------------------------------------------------------------

class IapResult {
  IapResult(this.spec);
  final IapSpec spec;
  String? id;
  final done = <String>[]; // steps that succeeded
  String? error; // first failure; later steps are skipped

  bool get ok => error == null;
  bool get partial => error != null && id != null;
}

class IapCreator {
  IapCreator(this.client, this.appId, this.options);
  final AscClient client;
  final String appId;
  final IapOptions options;

  List<String>? _territories;

  Future<List<String>> _allTerritories() async {
    return _territories ??= (await client.all('/v1/territories', {
      'limit': '200',
      'fields[territories]': 'currency',
    }, 5)).data.map((t) => t.id).toList();
  }

  /// The existing in-app purchase with [productId] in this app, or null.
  Future<Resource?> findExisting(String productId) async {
    final p = await client.page('/v1/apps/$appId/inAppPurchasesV2', {'filter[productId]': productId, 'limit': '1'});
    return p.data.isEmpty ? null : p.data.first;
  }

  /// Creates one IAP: create → localization → price → availability. Stops at the first failing step and records it, so a
  /// bulk run carries on with the next item and the person can see exactly what was left unfinished.
  ///
  /// In-app purchases can never be deleted, so nothing is created twice: if the product ID already exists (for example
  /// from an earlier run that failed halfway) it is reused, and only the steps it is still missing are done.
  Future<IapResult> create(IapSpec spec) async {
    final r = IapResult(spec);
    String step = 'lookup';
    try {
      final existing = await findExisting(spec.productId);
      if (existing != null) {
        if (existing.str('inAppPurchaseType') != spec.type) {
          throw AscException(
            'Product ID ${spec.productId} already exists as ${iapTypes[existing.str('inAppPurchaseType')] ?? existing.str('inAppPurchaseType')}, '
            'not ${iapTypes[spec.type]}. Product IDs can not be reused for another type.',
          );
        }
        r.id = existing.id;
        r.done.add('existing');
      } else {
        step = 'create';
        final created = await client.post('/v2/inAppPurchases', iapCreateBody(appId, spec));
        r.id = created.data.first.id;
        r.done.add('created');
      }

      step = 'localization';
      final locs = existing == null
          ? const <Resource>[]
          : (await client.page('/v2/inAppPurchases/${r.id}/inAppPurchaseLocalizations', {'limit': '50'})).data;
      if (locs.any((l) => l.str('locale') == spec.locale)) {
        r.done.add('localization (already there)');
      } else {
        await client.post('/v1/inAppPurchaseLocalizations', iapLocalizationBody(r.id!, spec));
        r.done.add('localization');
      }

      if (spec.price != null) {
        step = 'price';
        if (existing != null && await _has('/v2/inAppPurchases/${r.id}/iapPriceSchedule')) {
          r.done.add('price (already set)');
        } else {
          final points = await client.all('/v2/inAppPurchases/${r.id}/pricePoints', {
            'filter[territory]': options.baseTerritory,
            'limit': '200',
            'fields[inAppPurchasePricePoints]': 'customerPrice',
          }, 12);
          final best = pickPricePoint(points.data, spec.price!);
          if (best == null) throw AscException('No price points returned for ${options.baseTerritory}.');
          await client.post('/v1/inAppPurchasePriceSchedules', iapPriceScheduleBody(r.id!, options.baseTerritory, best.id));
          r.done.add('price ${best.str('customerPrice')}');
        }
      }

      if (options.allTerritories) {
        step = 'availability';
        if (existing != null && await _has('/v2/inAppPurchases/${r.id}/inAppPurchaseAvailability')) {
          r.done.add('availability (already set)');
        } else {
          await client.post('/v1/inAppPurchaseAvailabilities', iapAvailabilityBody(r.id!, await _allTerritories()));
          r.done.add('availability');
        }
      }
    } on AscException catch (e) {
      r.error = 'Failed at $step: ${e.message}';
    } catch (e) {
      r.error = 'Failed at $step: $e';
    }
    return r;
  }

  /// Whether a to-one relationship such as the price schedule is set. Apple answers 404 or an empty `data` when not.
  Future<bool> _has(String path) async {
    final p = await nullIfMissing(client.page(path));
    return p != null && p.data.isNotEmpty;
  }
}

// ---- Bulk input ---------------------------------------------------------------------------------------------------

/// Splits CSV text into rows, handling quoted fields, doubled quotes and commas/newlines inside quotes.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  final t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < t.length && t[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n') {
      row.add(field.toString());
      field.clear();
      if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  row.add(field.toString());
  if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
  return rows;
}

String? _normType(String raw) {
  final t = raw.trim().toUpperCase().replaceAll(RegExp(r'[\s-]+'), '_');
  if (t.isEmpty) return 'NON_CONSUMABLE';
  if (iapTypes.containsKey(t)) return t;
  if (t == 'NONRENEWING' || t == 'NON_RENEWING') return 'NON_RENEWING_SUBSCRIPTION';
  return null;
}

class BulkParse {
  BulkParse(this.specs, this.errors);
  final List<IapSpec> specs;
  final List<String> errors; // line-numbered
}

/// Header row required. Columns (any order, case-insensitive): product_id, reference_name, display_name, description, price,
/// and optional type, locale, review_note, family_sharable. `name` is accepted for display_name.
BulkParse parseIapCsv(String text) {
  final rows = parseCsv(text);
  if (rows.isEmpty) return BulkParse([], ['The file is empty.']);
  final header = [for (final h in rows.first) h.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_')];
  int col(List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final iProduct = col(['product_id', 'productid']);
  final iRef = col(['reference_name', 'reference', 'ref_name']);
  final iName = col(['display_name', 'name', 'title']);
  final iDesc = col(['description', 'desc']);
  final iPrice = col(['price']);
  final iType = col(['type', 'inapppurchasetype']);
  final iLocale = col(['locale']);
  final iNote = col(['review_note', 'reviewnote']);
  final iFamily = col(['family_sharable', 'familysharable']);

  final missing = [if (iProduct < 0) 'product_id', if (iName < 0) 'display_name'];
  if (missing.isNotEmpty) return BulkParse([], ['Missing required column(s): ${missing.join(', ')}. First row must be a header.']);

  final specs = <IapSpec>[];
  final errors = <String>[];
  final seen = <String>{};
  for (var n = 1; n < rows.length; n++) {
    final r = rows[n];
    String at(int i) => i >= 0 && i < r.length ? r[i].trim() : '';
    final type = _normType(at(iType));
    final priceText = at(iPrice);
    final price = priceText.isEmpty ? null : double.tryParse(priceText.replaceAll(RegExp(r'[^0-9.]'), ''));
    final display = at(iName);
    final spec = IapSpec(
      productId: at(iProduct),
      referenceName: at(iRef).isNotEmpty ? at(iRef) : display,
      type: type ?? at(iType),
      displayName: display,
      description: at(iDesc).isNotEmpty ? at(iDesc) : display,
      locale: at(iLocale).isNotEmpty ? at(iLocale) : 'en-US',
      price: price,
      reviewNote: at(iNote),
      familySharable: ['true', 'yes', '1'].contains(at(iFamily).toLowerCase()),
    );
    final problems = spec.validate();
    if (priceText.isNotEmpty && price == null) problems.add('Price "$priceText" is not a number.');
    if (!seen.add(spec.productId) && spec.productId.isNotEmpty) problems.add('Duplicate product ID in this file.');
    if (problems.isEmpty) {
      specs.add(spec);
    } else {
      errors.add('Line ${n + 1} (${spec.productId.isEmpty ? 'no product ID' : spec.productId}): ${problems.join(' ')}');
    }
  }
  return BulkParse(specs, errors);
}
