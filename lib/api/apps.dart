import 'dart:async';

import 'asc_client.dart';
import 'models.dart';

/// One app and its newest version, as read from the single Apps request. Nothing else is fetched for the list: builds,
/// icons and reviews load only once an app is opened.
class AppSummary {
  AppSummary(this.app, this.version);
  final Resource app;
  final Resource? version;

  String get id => app.id;
  String get name => app.str('name') ?? '—';
  String get bundleId => app.str('bundleId') ?? '';
  String get sku => app.str('sku') ?? '';
  String? get state => version?.str('appStoreState') ?? version?.str('appVersionState');
  String? get platform => version?.str('platform');
  String? get versionString => version?.str('versionString');
  bool get isLive => state == 'READY_FOR_SALE';
  bool get inReview => state == 'WAITING_FOR_REVIEW' || state == 'IN_REVIEW';

  /// Anything that is not an iPhone/iPad app: macOS, tvOS, visionOS.
  bool get notIos => platform != null && platform != 'IOS';
}

/// ONE request for up to 200 apps, with their versions included (a larger account follows Apple's next links, up to
/// 1,000 apps). Each app's latest version is the first one Apple lists.
Future<List<AppSummary>> loadApps(AscClient c) async {
  final page = await c.all('/v1/apps', {
    'limit': '200',
    'sort': 'name',
    'include': 'appStoreVersions',
    'fields[apps]': 'name,bundleId,sku,primaryLocale,appStoreVersions',
    'fields[appStoreVersions]': 'versionString,appStoreState,appVersionState,platform,createdDate',
  }, 5);
  return summarizeApps(page);
}

List<AppSummary> summarizeApps(ResourcePage page) => [
  for (final app in page.data)
    AppSummary(app, () {
      final ids = app.relIds('appStoreVersions');
      return ids.isEmpty ? null : page.inc('appStoreVersions', ids.first);
    }()),
];

/// Loads the list once per client and shares it with the command palette, so opening the palette costs no request.
class AppsStore {
  AppsStore(this.client);
  final AscClient client;
  Future<List<AppSummary>>? _future;

  Future<List<AppSummary>> get apps {
    return _future ??= () {
      final f = loadApps(client);
      unawaited(
        f.catchError((_) {
          _future = null; // let the next ask retry instead of replaying the failure
          return <AppSummary>[];
        }),
      );
      return f;
    }();
  }

  Future<List<AppSummary>> refresh() {
    _future = null;
    return apps;
  }
}

enum AppFilter { all, ready, review, other }

extension AppFilterInfo on AppFilter {
  String get label => switch (this) {
    AppFilter.all => 'All Apps',
    AppFilter.ready => 'Ready for Sale',
    AppFilter.review => 'In Review',
    AppFilter.other => 'Universal & macOS',
  };

  bool matches(AppSummary a) => switch (this) {
    AppFilter.all => true,
    AppFilter.ready => a.isLive,
    AppFilter.review => a.inReview,
    AppFilter.other => a.notIos,
  };
}

List<AppSummary> filterApps(List<AppSummary> apps, AppFilter filter, String query) {
  final q = query.trim().toLowerCase();
  return [
    for (final a in apps)
      if (filter.matches(a) &&
          (q.isEmpty || a.name.toLowerCase().contains(q) || a.bundleId.toLowerCase().contains(q) || a.sku.toLowerCase().contains(q)))
        a,
  ];
}
