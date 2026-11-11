import 'package:flutter/foundation.dart';

import 'asc_client.dart';
import 'listing.dart';
import 'screenshots.dart';

/// Which localization a text field lives in.
enum TextTarget {
  version('appStoreVersionLocalizations'), // description, keywords, what's new …
  info('appInfoLocalizations'); // name, subtitle, privacy URL

  const TextTarget(this.resourceType);
  final String resourceType;
}

/// What a changelist line changes.
enum ChangeKind { text, shotAdd, shotDelete, shotOrder, shotSet }

/// An edited text field, held until the changelist is applied.
class DraftText {
  DraftText({
    required this.target,
    required this.locId,
    required this.locale,
    required this.field,
    required this.label,
    required this.before,
    required this.after,
  });
  final TextTarget target;
  final String locId;
  final String locale;
  final String field;
  final String label;
  final String before;
  final String after;
}

class ShotItem {
  ShotItem.existing({required String this.id, required this.name, this.url, this.bytes});
  ShotItem.added({required this.name, required Uint8List this.bytes}) : id = null, url = null;

  /// The placement id (the link between a library image and this localization). Null for a picture not uploaded yet.
  final String? id;
  final String? url;
  final String name;

  /// The picture itself, for a new one (and kept for the preview once it has been placed but not yet reloaded).
  final Uint8List? bytes;
  bool deleted = false;
  bool get isNew => id == null;
}

/// The editable state of the screenshots of one device group (e.g. 6.9" iPhone) in one locale.
class ShotSetDraft {
  ShotSetDraft({required this.exists, required this.group, required this.versionLocId, required this.locale, required this.items})
    : originalOrder = [
        for (final i in items)
          if (!i.isNew) i.id!,
      ];

  bool exists; // false = a device group added in this session that has no screenshots on Apple yet
  final String group; // Apple's placementGroup, e.g. IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE
  final String versionLocId;
  final String locale;
  final List<ShotItem> items;
  final List<String> originalOrder;

  List<ShotItem> get kept => [
    for (final i in items)
      if (!i.deleted) i,
  ];
  int get liveCount => kept.length;

  /// Existing screenshots left in a different order, or a new one placed ahead of an existing one.
  bool get needsReorder {
    final keptExisting = [
      for (final i in kept)
        if (!i.isNew) i.id!,
    ];
    final expected = [
      for (final id in originalOrder)
        if (keptExisting.contains(id)) id,
    ];
    if (!listEquals(keptExisting, expected)) return true;
    var sawNew = false;
    for (final i in kept) {
      if (i.isNew) sawNew = true;
      if (!i.isNew && sawNew) return true;
    }
    return false;
  }

  bool get changed => !exists ? items.isNotEmpty : (items.any((i) => i.deleted || i.isNew) || needsReorder);
}

/// One line in the changelist.
class Change {
  Change({required this.kind, required this.locale, required this.title, this.before, this.after, this.preview, this.detail});
  final ChangeKind kind;
  final String locale;
  final String title;
  final String? before;
  final String? after;
  final Uint8List? preview;
  final String? detail;
}

class ApplyResult {
  ApplyResult(this.title, [this.error]);
  final String title;
  final String? error;
  bool get ok => error == null;
}

/// Everything edited on the listing but not yet sent, across all locales. Nothing touches Apple until [apply].
class ListingDraft extends ChangeNotifier {
  ListingDraft({this.libraryId});

  /// The app's asset library (its id is the app id). New screenshots are uploaded into it.
  final String? libraryId;

  final _texts = <String, DraftText>{};
  final _sets = <String, ShotSetDraft>{};

  static String setKey(String versionLocId, String group) => '$versionLocId:$group';

  String? textOverride(TextTarget target, String locId, String field) => _texts['${target.name}:$locId:$field']?.after;

  void setText({
    required TextTarget target,
    required String locId,
    required String locale,
    required ListingField field,
    required String before,
    required String after,
  }) {
    final k = '${target.name}:$locId:${field.key}';
    if (after == before) {
      if (_texts.remove(k) != null) notifyListeners();
      return;
    }
    _texts[k] = DraftText(target: target, locId: locId, locale: locale, field: field.key, label: field.label, before: before, after: after);
    notifyListeners();
  }

  ShotSetDraft? shotSet(String key) => _sets[key];

  /// All screenshot groups (existing and new) for one localization, phones first.
  List<ShotSetDraft> setsFor(String versionLocId) {
    final list = _sets.values.where((s) => s.versionLocId == versionLocId).toList();
    list.sort((a, b) {
      final r = placementGroupRank(a.group).compareTo(placementGroupRank(b.group));
      return r != 0 ? r : a.group.compareTo(b.group);
    });
    return list;
  }

  /// Registers a set once; later calls return the same draft so edits survive rebuilds and locale switches.
  ShotSetDraft ensureShotSet(String key, ShotSetDraft Function() create) => _sets.putIfAbsent(key, create);

  void touch() => notifyListeners();

  void addShots(String key, List<({String name, Uint8List bytes})> files) {
    final s = _sets[key];
    if (s == null) return;
    for (final f in files) {
      if (s.liveCount >= maxScreenshotsPerSet) break;
      s.items.add(ShotItem.added(name: f.name, bytes: f.bytes));
    }
    notifyListeners();
  }

  /// Existing screenshots are marked deleted (and can be restored); new ones are simply dropped.
  void toggleDelete(String key, int index) {
    final s = _sets[key];
    if (s == null) return;
    final item = s.items[index];
    if (item.isNew) {
      s.items.removeAt(index);
    } else {
      item.deleted = !item.deleted;
    }
    notifyListeners();
  }

  void move(String key, int index, int delta) {
    final s = _sets[key];
    if (s == null) return;
    final to = index + delta;
    if (to < 0 || to >= s.items.length) return;
    final item = s.items.removeAt(index);
    s.items.insert(to, item);
    notifyListeners();
  }

  void discard() {
    _texts.clear();
    _sets.clear();
    notifyListeners();
  }

  List<Change> changes() {
    final out = <Change>[];
    for (final t in _texts.values) {
      out.add(Change(kind: ChangeKind.text, locale: t.locale, title: t.label, before: t.before, after: t.after));
    }
    for (final s in _sets.values.where((s) => s.changed)) {
      final label = placementGroupLabel(s.group);
      if (!s.exists) {
        out.add(
          Change(kind: ChangeKind.shotSet, locale: s.locale, title: '$label: new device group', detail: '${s.items.length} screenshot(s)'),
        );
      }
      for (final i in s.items.where((i) => i.deleted)) {
        out.add(Change(kind: ChangeKind.shotDelete, locale: s.locale, title: '$label: remove ${i.name}', detail: i.name));
      }
      for (final i in s.items.where((i) => i.isNew && !i.deleted)) {
        out.add(
          Change(
            kind: ChangeKind.shotAdd,
            locale: s.locale,
            title: '$label: add ${i.name}',
            preview: i.bytes,
            detail: '${(i.bytes!.length / 1024).round()} KB',
          ),
        );
      }
      if (s.exists && s.needsReorder) out.add(Change(kind: ChangeKind.shotOrder, locale: s.locale, title: '$label: new order'));
    }
    out.sort((a, b) => a.locale.compareTo(b.locale));
    return out;
  }

  int get count => changes().length;
  bool get isEmpty => count == 0;

  /// Sends every change: text first, then screenshots. Failures are collected, not thrown, so one bad item does not
  /// hide the rest. Whatever succeeded leaves the draft; whatever failed stays, so Apply again picks up where it stopped
  /// (a screenshot set records each delete and upload as it lands, so nothing is sent twice).
  Future<List<ApplyResult>> apply(AscClient client, {void Function(String step)? onStep}) async {
    final results = <ApplyResult>[];

    final byLoc = <String, List<DraftText>>{};
    for (final t in _texts.values) {
      (byLoc['${t.target.name}:${t.locId}'] ??= []).add(t);
    }
    for (final group in byLoc.values) {
      final first = group.first;
      final title = '${first.locale} · ${group.map((t) => t.label).join(', ')}';
      onStep?.call(title);
      try {
        final type = first.target.resourceType;
        await client.patch('/v1/$type/${first.locId}', localizationPatchBody(type, first.locId, {for (final t in group) t.field: t.after}));
        for (final t in group) {
          _texts.remove('${t.target.name}:${t.locId}:${t.field}');
        }
        results.add(ApplyResult(title));
      } on AscException catch (e) {
        results.add(ApplyResult(title, e.message));
      }
    }

    for (final s in _sets.values.where((s) => s.changed).toList()) {
      final title = '${s.locale} · ${placementGroupLabel(s.group)} screenshots';
      onStep?.call(title);
      try {
        await _applySet(client, s);
        _sets.removeWhere((_, v) => identical(v, s));
        results.add(ApplyResult(title));
      } on AscException catch (e) {
        results.add(ApplyResult(title, e.message));
      }
    }
    notifyListeners();
    return results;
  }

  Future<void> _applySet(AscClient client, ShotSetDraft s) async {
    final libraryId = this.libraryId;
    if (libraryId == null && s.items.any((i) => i.isNew && !i.deleted)) {
      throw AscException('The app\'s asset library is unknown, so new screenshots cannot be uploaded.');
    }
    // Removing a placement takes the screenshot off this version; the image itself stays in the app's library.
    // Each step is written back into the draft as soon as Apple accepts it, so a failure later on can be retried.
    for (final i in s.items.where((i) => i.deleted && !i.isNew).toList()) {
      await client.delete('/v1/appAssetLibraryPlacements/${i.id}');
      s.items.remove(i);
      s.originalOrder.remove(i.id);
    }
    for (var n = 0; n < s.items.length; n++) {
      final i = s.items[n];
      if (!i.isNew || i.deleted) continue;
      final imageId = await uploadLibraryImage(client, libraryId!, i.name, i.bytes!);
      final placementId = await createPlacement(client, imageId, s.versionLocId);
      s.items[n] = ShotItem.existing(id: placementId, name: i.name, bytes: i.bytes);
      s.exists = true;
      _placedThisSession.add(placementId);
    }
    final finalIds = [for (final i in s.kept) i.id!];
    final placedNew = finalIds.any(_placedThisSession.contains);
    if (finalIds.length > 1 && (s.needsReorder || placedNew)) {
      await client.post('/v1/appAssetLibraryPlacementOrderingRequests', placementOrderBody(s.group, s.versionLocId, finalIds));
    }
  }

  /// Placements this draft created. A set holding one still needs its order sent, even on a retry.
  final _placedThisSession = <String>{};
}
