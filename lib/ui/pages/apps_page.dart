import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../services/prefs.dart';
import '../theme.dart';
import '../widgets.dart';

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
      f.catchError((_) {
        _future = null; // let the next ask retry instead of replaying the failure
        return <AppSummary>[];
      });
      return f;
    }();
  }

  Future<List<AppSummary>> refresh() {
    _future = null;
    return apps;
  }
}

enum AppFilter { all, ready, review, other }

extension on AppFilter {
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

class AppsPage extends StatefulWidget {
  const AppsPage({super.key, required this.store, required this.onOpen, this.prefs});
  final AppsStore store;

  /// Remembers grid or list between launches.
  final Prefs? prefs;
  final void Function(AppSummary app) onOpen;

  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  final _reload = ReloadController();
  final _search = TextEditingController();
  AppFilter _filter = AppFilter.all;
  late bool _grid = widget.prefs?.appsGrid ?? true;
  bool _first = true;

  @override
  void dispose() {
    _reload.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<List<AppSummary>> _load() {
    if (_first) {
      _first = false;
      return widget.store.apps;
    }
    return widget.store.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Column(
      children: [
        PageHeader(
          title: 'Applications',
          subtitle: 'Everything this key can see',
          reload: _reload,
          actions: [
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt, size: 14, color: k.accentInk),
                  const SizedBox(width: 4),
                  Text(
                    '1 API request',
                    style: TextStyle(color: k.accentInk, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.grid_view_rounded, size: 17), tooltip: 'Grid'),
                ButtonSegment(value: false, icon: Icon(Icons.view_list_rounded, size: 18), tooltip: 'List'),
              ],
              selected: {_grid},
              onSelectionChanged: (v) {
                setState(() => _grid = v.first);
                widget.prefs?.setAppsGrid(_grid);
              },
            ),
            const SizedBox(width: 6),
          ],
        ),
        Expanded(
          child: LoadView<List<AppSummary>>(
            controller: _reload,
            load: _load,
            builder: (context, apps) {
              if (apps.isEmpty) return const EmptyView('This key can not see any apps.');
              final shown = filterApps(apps, _filter, _search.text);
              return ListView(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'Search apps',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            suffixIcon: _search.text.isEmpty
                                ? null
                                : IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(_search.clear)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final f in AppFilter.values)
                              _FilterPill(
                                label: f.label,
                                count: apps.where(f.matches).length,
                                on: f == _filter,
                                onTap: () => setState(() => _filter = f),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 60),
                      child: EmptyView(
                        _search.text.isEmpty ? 'No apps in this filter.' : 'No apps match “${_search.text}”.',
                        icon: Icons.search_off,
                      ),
                    )
                  else if (_grid)
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = (c.maxWidth / 340).floor().clamp(1, 4);
                        final w = (c.maxWidth - 16 * (cols - 1)) / cols;
                        return Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            for (final a in shown)
                              SizedBox(
                                width: w,
                                child: _AppCard(app: a, onTap: () => widget.onOpen(a)),
                              ),
                          ],
                        );
                      },
                    )
                  else
                    RowsCard(
                      children: [for (final a in shown) _AppRow(app: a, onTap: () => widget.onOpen(a))],
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({required this.label, required this.count, required this.on, required this.onTap});
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Material(
      color: on ? k.accentSoft : k.surface,
      shape: StadiumBorder(side: BorderSide(color: on ? k.accent.withValues(alpha: 0.5) : k.line)),
      child: MergeSemantics(
        child: Semantics(
          button: true,
          selected: on,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? k.accentInk : k.body),
                  ),
                  const SizedBox(width: 7),
                  Text('$count', style: TextStyle(fontSize: 12, color: on ? k.accentInk : k.muted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlatformPill extends StatelessWidget {
  const _PlatformPill(this.platform);
  final String? platform;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(platformIcon(platform), size: 14, color: k.muted),
        const SizedBox(width: 4),
        Text(prettyPlatform(platform), style: TextStyle(color: k.muted, fontSize: 12.5)),
      ],
    );
  }
}

/// A card for one app. It carries no rating and no build number: those live inside the app.
class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.onTap});
  final AppSummary app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: MergeSemantics(
        child: Semantics(
          button: true,
          hint: 'Opens the app',
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSquircleIcon(name: app.name, platform: app.platform, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              app.bundleId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: k.muted, fontSize: 12.5),
                            ),
                            const SizedBox(height: 6),
                            _PlatformPill(app.platform),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: k.line),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [if (app.versionString != null) 'v${app.versionString}', if (app.sku.isNotEmpty) 'SKU ${app.sku}'].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: k.muted, fontSize: 12.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusBadge(app.state),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.onTap});
  final AppSummary app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: 'Opens the app',
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                AppSquircleIcon(name: app.name, platform: app.platform, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(app.bundleId, style: TextStyle(color: k.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                SizedBox(width: 120, child: _PlatformPill(app.platform)),
                SizedBox(
                  width: 90,
                  child: Text(
                    app.versionString == null ? '' : 'v${app.versionString}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: Text(
                    app.sku,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: k.muted, fontSize: 12.5),
                  ),
                ),
                StatusBadge(app.state),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: k.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
