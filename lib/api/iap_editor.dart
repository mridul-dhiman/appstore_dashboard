import 'dart:typed_data';

import 'asc_client.dart';
import 'asset_upload.dart';
import 'iap_creator.dart';
import 'models.dart';
import 'pricing.dart';

/// Apple's limit for the App Review note on an in-app purchase.
const iapReviewNoteMax = 4000;

/// States in which Apple does not accept edits to an in-app purchase.
const iapLockedStates = {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'PENDING_BINARY_APPROVAL', 'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE'};

/// Everything the edit page shows about one in-app purchase, as Apple has it now.
class IapDetails {
  IapDetails({
    required this.iap,
    this.localizations = const [],
    this.baseTerritory,
    this.currency,
    this.schedule = const [],
    this.manualPriceCount = 0,
    this.availabilityId,
    this.available,
    this.availableInNewTerritories = false,
    this.allTerritories = const [],
    this.screenshot,
  });

  final Resource iap;
  final List<Resource> localizations;

  /// Price schedule: the base territory, its currency and its manual prices, oldest first. Empty when no price is set.
  final String? baseTerritory;
  final String? currency;
  final List<TerritoryPrice> schedule;

  /// Territories with a price set by hand rather than Apple's equalisation.
  final int manualPriceCount;

  /// Availability. [available] is null when it was never set, which Apple treats as on sale nowhere.
  final String? availabilityId;
  final Set<String>? available;
  final bool availableInNewTerritories;
  final List<String> allTerritories;

  /// The App Review screenshot, if one is uploaded.
  final Resource? screenshot;

  String get productId => iap.str('productId') ?? '';
  String get state => iap.str('state') ?? '';
  bool get locked => iapLockedStates.contains(state);

  /// The base territory's price today, or null when no price is set.
  TerritoryPrice? get currentPrice {
    final now = DateTime.now();
    for (final p in schedule) {
      if (p.activeOn(now)) return p;
    }
    return null;
  }
}

Future<IapDetails> loadIapDetails(AscClient c, String iapId) async {
  final base = '/v2/inAppPurchases/$iapId';
  final r = await Future.wait<Object?>([
    c.page(base),
    c.page('$base/inAppPurchaseLocalizations', {'limit': '50'}),
    nullIfMissing(c.page('$base/iapPriceSchedule', {'include': 'baseTerritory', 'fields[territories]': 'currency'})),
    nullIfMissing(c.page('$base/inAppPurchaseAvailability')),
    nullIfMissing(c.page('$base/appStoreReviewScreenshot')),
    c.all('/v1/territories', {'limit': '200', 'fields[territories]': 'currency'}, 3),
  ]);
  final iap = (r[0] as ResourcePage).data.first;
  final locs = (r[1] as ResourcePage).data..sort((a, b) => (a.str('locale') ?? '').compareTo(b.str('locale') ?? ''));
  final territories = (r[5] as ResourcePage).data;

  String? baseTerritory, currency;
  var schedule = <TerritoryPrice>[];
  var manualCount = 0;
  final sched = r[2] as ResourcePage?;
  if (sched != null && sched.data.isNotEmpty) {
    baseTerritory = sched.data.first.relId('baseTerritory');
    currency =
        sched.inc('territories', baseTerritory)?.str('currency') ??
        territories.where((t) => t.id == baseTerritory).firstOrNull?.str('currency');
    final m = await c.all('/v1/inAppPurchasePriceSchedules/${sched.data.first.id}/manualPrices', {
      'include': 'inAppPurchasePricePoint,territory',
      'fields[inAppPurchasePricePoints]': 'customerPrice,proceeds',
      'fields[territories]': 'currency',
      'limit': '200',
    }, 3);
    manualCount = {for (final p in m.data) p.relId('territory')}.length;
    schedule = [
      for (final p in m.data)
        if (p.relId('territory') == baseTerritory)
          TerritoryPrice(
            territory: baseTerritory!,
            currency: currency,
            customerPrice: m.inc('inAppPurchasePricePoints', p.relId('inAppPurchasePricePoint'))?.str('customerPrice'),
            proceeds: m.inc('inAppPurchasePricePoints', p.relId('inAppPurchasePricePoint'))?.str('proceeds'),
            manual: true,
            start: p.date('startDate'),
            end: p.date('endDate'),
          ),
    ]..sort((a, b) => (a.start ?? DateTime(0)).compareTo(b.start ?? DateTime(0)));
  }

  String? availabilityId;
  Set<String>? available;
  var inNew = false;
  final avail = r[3] as ResourcePage?;
  if (avail != null && avail.data.isNotEmpty) {
    availabilityId = avail.data.first.id;
    inNew = avail.data.first.flag('availableInNewTerritories') ?? false;
    available = (await c.all('/v1/inAppPurchaseAvailabilities/$availabilityId/availableTerritories', {'limit': '200'}, 2)).data
        .map((t) => t.id)
        .toSet();
  }

  final shot = r[4] as ResourcePage?;
  return IapDetails(
    iap: iap,
    localizations: locs,
    baseTerritory: baseTerritory,
    currency: currency,
    schedule: schedule,
    manualPriceCount: manualCount,
    availabilityId: availabilityId,
    available: available,
    availableInNewTerritories: inNew,
    allTerritories: [for (final t in territories) t.id]..sort(),
    screenshot: shot == null || shot.data.isEmpty ? null : shot.data.first,
  );
}

/// Apple's price points for the purchase in one territory, cheapest first, free ones left out.
Future<List<Resource>> loadIapPricePoints(AscClient c, String iapId, String territory) async {
  final p = await c.all('/v2/inAppPurchases/$iapId/pricePoints', {
    'filter[territory]': territory,
    'limit': '200',
    'fields[inAppPurchasePricePoints]': 'customerPrice,proceeds',
  }, 12);
  double price(Resource r) => double.tryParse(r.str('customerPrice') ?? '') ?? 0;
  return [
    for (final r in p.data)
      if (price(r) > 0) r,
  ]..sort((a, b) => price(a).compareTo(price(b)));
}

// ---- Request bodies -----------------------------------------------------------------------------------------------

Map<String, dynamic> iapUpdateBody(String iapId, {String? name, String? reviewNote, bool? familySharable}) => {
  'data': {
    'type': 'inAppPurchases',
    'id': iapId,
    'attributes': {'name': ?name, 'reviewNote': ?reviewNote, 'familySharable': ?familySharable},
  },
};

Map<String, dynamic> iapLocalizationUpdateBody(String locId, {required String name, required String description}) => {
  'data': {
    'type': 'inAppPurchaseLocalizations',
    'id': locId,
    'attributes': {'name': name, 'description': description},
  },
};

Map<String, dynamic> iapLocalizationCreateBody(String iapId, {required String locale, required String name, required String description}) => {
  'data': {
    'type': 'inAppPurchaseLocalizations',
    'attributes': {'name': name, 'locale': locale, 'description': description},
    'relationships': {
      'inAppPurchaseV2': {
        'data': {'type': 'inAppPurchases', 'id': iapId},
      },
    },
  },
};

Map<String, dynamic> iapScreenshotReserveBody(String iapId, {required String fileName, required int fileSize}) => {
  'data': {
    'type': 'inAppPurchaseAppStoreReviewScreenshots',
    'attributes': {'fileName': fileName, 'fileSize': fileSize},
    'relationships': {
      'inAppPurchaseV2': {
        'data': {'type': 'inAppPurchases', 'id': iapId},
      },
    },
  },
};

Map<String, dynamic> iapScreenshotCommitBody(String shotId, String md5) => {
  'data': {
    'type': 'inAppPurchaseAppStoreReviewScreenshots',
    'id': shotId,
    'attributes': {'uploaded': true, 'sourceFileChecksum': md5},
  },
};

Map<String, dynamic> iapSubmissionBody(String iapId) => {
  'data': {
    'type': 'inAppPurchaseSubmissions',
    'relationships': {
      'inAppPurchaseV2': {
        'data': {'type': 'inAppPurchases', 'id': iapId},
      },
    },
  },
};

// ---- Edits --------------------------------------------------------------------------------------------------------

/// One localization as edited. [id] is null for a locale added here and not saved yet.
class IapLocDraft {
  IapLocDraft({this.id, required this.locale, required this.savedName, required this.savedDescription, this.state})
    : name = savedName,
      description = savedDescription;

  String? id;
  final String locale;
  final String? state;
  String savedName, savedDescription;
  String name, description;

  bool get isNew => id == null;
  bool get modified => isNew || name != savedName || description != savedDescription;
}

/// A screenshot picked on this page, uploaded on save.
class PickedShot {
  PickedShot(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

enum IapCheckLevel { ok, warn, bad }

class IapCheck {
  const IapCheck(this.label, this.level);
  final String label;
  final IapCheckLevel level;
}

/// The page's edits on top of [IapDetails]. Nothing reaches Apple until [IapSaver.save]; each step that succeeds becomes
/// the new baseline, so after a failure only what is still unsaved stays marked.
class IapDraft {
  IapDraft(this.details)
    : savedName = details.iap.str('name') ?? '',
      savedNote = details.iap.str('reviewNote') ?? '',
      savedFamily = details.iap.flag('familySharable') ?? false,
      savedPrice = details.currentPrice,
      savedInNew = details.availableInNewTerritories,
      savedTerritories = details.available,
      locs = [
        for (final l in details.localizations)
          IapLocDraft(
            id: l.id,
            locale: l.str('locale') ?? '',
            savedName: l.str('name') ?? '',
            savedDescription: l.str('description') ?? '',
            state: l.str('state'),
          ),
      ] {
    name = savedName;
    note = savedNote;
    family = savedFamily;
    inNew = savedInNew;
    territories = savedTerritories == null ? null : {...savedTerritories!};
  }

  final IapDetails details;

  String savedName, savedNote;
  bool savedFamily;
  late String name, note;
  late bool family;

  final List<IapLocDraft> locs;

  /// Saved localizations removed here, deleted on save.
  final removedLocs = <IapLocDraft>[];

  TerritoryPrice? savedPrice;

  /// A new price point picked here (id, customer price, proceeds).
  Resource? newPrice;

  bool savedInNew;
  late bool inNew;
  Set<String>? savedTerritories;
  Set<String>? territories;

  PickedShot? shot;

  bool get generalChanged => name != savedName || note != savedNote || family != savedFamily;
  bool get availabilityChanged =>
      inNew != savedInNew ||
      (territories != null && (savedTerritories == null || !_sameSet(territories!, savedTerritories!)));

  static bool _sameSet(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);

  /// What saving would send, one line per change, in the order it is sent.
  List<String> get changes => [
    if (name != savedName) 'Reference name',
    if (family != savedFamily) 'Family Sharing on',
    if (note != savedNote) 'Review notes',
    for (final l in removedLocs) 'Remove ${l.locale} localization',
    for (final l in locs)
      if (l.isNew)
        'Add ${l.locale} localization'
      else if (l.modified)
        '${l.locale} ${[if (l.name != l.savedName) 'display name', if (l.description != l.savedDescription) 'description'].join(' and ')}',
    if (newPrice != null) 'Price ${details.currency ?? ''} ${newPrice!.str('customerPrice')}'.replaceAll('  ', ' '),
    if (availabilityChanged) 'Availability',
    if (shot != null) 'App Review screenshot',
  ];

  bool get dirty => changes.isNotEmpty;

  /// Ready-for-review checklist. Anything [IapCheckLevel.bad] blocks submitting; [IapCheckLevel.warn] is an unsaved change.
  List<IapCheck> get checks {
    final c = <IapCheck>[];
    c.add(name.trim().isEmpty || name.length > iapReferenceMax
        ? const IapCheck('Reference name missing or too long', IapCheckLevel.bad)
        : const IapCheck('Reference name', IapCheckLevel.ok));
    c.add(savedPrice != null || newPrice != null ? const IapCheck('Price set', IapCheckLevel.ok) : const IapCheck('No price set', IapCheckLevel.bad));
    final count = territories?.length ?? 0;
    c.add(count > 0 ? const IapCheck('Available in at least one territory', IapCheckLevel.ok) : const IapCheck('Not available anywhere', IapCheckLevel.bad));
    if (locs.isEmpty) c.add(const IapCheck('No localization', IapCheckLevel.bad));
    for (final l in locs) {
      final bad = l.name.trim().isEmpty || l.name.length > iapNameMax || l.description.length > iapDescriptionMax;
      c.add(IapCheck(bad ? '${l.locale} display name or description invalid' : '${l.locale} localization', bad ? IapCheckLevel.bad : IapCheckLevel.ok));
    }
    if (details.screenshot == null && shot == null) c.add(const IapCheck('App Review screenshot missing', IapCheckLevel.bad));
    if (note.length > iapReviewNoteMax) c.add(const IapCheck('Review notes too long', IapCheckLevel.bad));
    for (final ch in changes) {
      c.add(IapCheck('$ch changed (unsaved)', IapCheckLevel.warn));
    }
    return c;
  }

  int get issueCount => checks.where((c) => c.level == IapCheckLevel.bad).length;

  void discard() {
    name = savedName;
    note = savedNote;
    family = savedFamily;
    locs.removeWhere((l) => l.isNew);
    locs.addAll(removedLocs);
    locs.sort((a, b) => a.locale.compareTo(b.locale));
    removedLocs.clear();
    for (final l in locs) {
      l.name = l.savedName;
      l.description = l.savedDescription;
    }
    newPrice = null;
    inNew = savedInNew;
    territories = savedTerritories == null ? null : {...savedTerritories!};
    shot = null;
  }
}

/// Sends an [IapDraft] to Apple one step at a time, marking each step saved as it succeeds.
class IapSaver {
  IapSaver(this.client);
  final AscClient client;

  /// Saves every change in [d]. Throws [AscException] naming the step that failed; the steps before it stay saved.
  Future<void> save(IapDraft d, {void Function(String step)? onStep}) async {
    final id = d.details.iap.id;
    Future<void> step(String label, Future<void> Function() run) async {
      onStep?.call(label);
      try {
        await run();
      } on AscException catch (e) {
        throw AscException('$label failed: ${e.message}');
      }
    }

    if (d.generalChanged) {
      await step('General', () async {
        await client.patch(
          '/v2/inAppPurchases/$id',
          iapUpdateBody(
            id,
            name: d.name != d.savedName ? d.name.trim() : null,
            reviewNote: d.note != d.savedNote ? d.note : null,
            familySharable: d.family != d.savedFamily ? d.family : null,
          ),
        );
        d.savedName = d.name = d.name.trim();
        d.savedNote = d.note;
        d.savedFamily = d.family;
      });
    }
    for (final l in [...d.removedLocs]) {
      await step('Remove ${l.locale}', () async {
        await client.delete('/v1/inAppPurchaseLocalizations/${l.id}');
        d.removedLocs.remove(l);
      });
    }
    for (final l in d.locs.where((l) => l.modified)) {
      await step('${l.locale} localization', () async {
        if (l.isNew) {
          final r = await client.post(
            '/v1/inAppPurchaseLocalizations',
            iapLocalizationCreateBody(id, locale: l.locale, name: l.name.trim(), description: l.description.trim()),
          );
          l.id = r.data.first.id;
        } else {
          await client.patch(
            '/v1/inAppPurchaseLocalizations/${l.id}',
            iapLocalizationUpdateBody(l.id!, name: l.name.trim(), description: l.description.trim()),
          );
        }
        l.savedName = l.name = l.name.trim();
        l.savedDescription = l.description = l.description.trim();
      });
    }
    if (d.newPrice case final p?) {
      await step('Price', () async {
        final territory = d.details.baseTerritory ?? 'USA';
        await client.post('/v1/inAppPurchasePriceSchedules', iapPriceScheduleBody(id, territory, p.id));
        d.savedPrice = TerritoryPrice(
          territory: territory,
          currency: d.details.currency,
          customerPrice: p.str('customerPrice'),
          proceeds: p.str('proceeds'),
          manual: true,
        );
        d.newPrice = null;
      });
    }
    if (d.availabilityChanged) {
      await step('Availability', () async {
        final t = d.territories ?? const <String>{};
        await client.post('/v1/inAppPurchaseAvailabilities', iapAvailabilityBody(id, t.toList()..sort(), availableInNewTerritories: d.inNew));
        d.savedTerritories = {...t};
        d.savedInNew = d.inNew;
      });
    }
    if (d.shot case final s?) {
      await step('App Review screenshot', () async {
        if (d.details.screenshot case final old?) {
          await client.delete('/v1/inAppPurchaseAppStoreReviewScreenshots/${old.id}');
        }
        final reserved = (await client.post(
          '/v1/inAppPurchaseAppStoreReviewScreenshots',
          iapScreenshotReserveBody(id, fileName: s.name, fileSize: s.bytes.length),
        )).data.first;
        final ops = [
          for (final o in (reserved.attributes['uploadOperations'] as List? ?? const []))
            UploadOp.fromJson((o as Map).cast<String, dynamic>()),
        ];
        await putParts(ops, s.bytes, (_) {});
        await client.patch('/v1/inAppPurchaseAppStoreReviewScreenshots/${reserved.id}', iapScreenshotCommitBody(reserved.id, md5Hex(s.bytes)));
        d.shot = null;
      });
    }
  }

  /// Submits the purchase for review on its own. Apple requires a first in-app purchase to go with an app version.
  Future<void> submit(String iapId) => client.post('/v1/inAppPurchaseSubmissions', iapSubmissionBody(iapId));

  /// Deletes the purchase. Its product ID can never be used again.
  Future<void> delete(String iapId) => client.delete('/v2/inAppPurchases/$iapId');
}
