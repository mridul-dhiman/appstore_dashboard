import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/asc_client.dart';
import '../../api/export.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/reviews.dart';
import '../../api/testflight.dart';
import '../theme.dart';
import '../export_button.dart';
import '../widgets.dart';
import 'apps_page.dart';
import 'groups_tab.dart';
import 'iap_dialogs.dart';
import 'listing_tab.dart';
import 'reviews_tab.dart';
import 'submit_tab.dart';
import 'upload_tab.dart';

const _tabLabels = [
  'Store Listing',
  'TestFlight & Groups',
  'Customer Reviews',
  'Builds',
  'Upload .IPA',
  'In-App Purchases',
  'App Review Preflight',
];
const _uploadTab = 4;

/// One app's workspace: a header with the app's details and quick actions, and a tab for each job.
class AppDetailPage extends StatefulWidget {
  const AppDetailPage({super.key, required this.client, required this.summary, required this.onBack, this.initialTab = 0});
  final AscClient client;
  final AppSummary summary;
  final VoidCallback onBack;
  final int initialTab;

  /// Tab index of "Upload .IPA", for shortcuts that jump straight to it.
  static const uploadTabIndex = _uploadTab;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  /// Staged listing edits, shared by the Listing tab (which edits them) and the Submit tab (which refuses to submit while
  /// they are unsent).
  late final _draft = ListingDraft(libraryId: widget.summary.app.id);
  ReviewsData? _reviews;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _openStore() async {
    final ok = await launchUrl(Uri.parse('https://apps.apple.com/app/id${widget.summary.id}'), mode: LaunchMode.externalApplication);
    if (!ok && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the App Store page.')));
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final summary = widget.summary;
    final k = Tokens.of(context);
    final id = summary.id;
    final meta = [summary.bundleId, if (summary.sku.isNotEmpty) 'SKU ${summary.sku}', 'Apple ID $id'];
    // One controller for the header's tab strip, the pages, and the Submit tab's "Open Listing" shortcut.
    return DefaultTabController(
      length: _tabLabels.length,
      initialIndex: widget.initialTab.clamp(0, _tabLabels.length - 1),
      child: Builder(
        builder: (context) {
          final tabs = DefaultTabController.of(context);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 22, 40, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(padding: const EdgeInsets.only(left: 0, right: 8), foregroundColor: k.accentInk),
                      onPressed: widget.onBack,
                      icon: const Icon(Icons.chevron_left, size: 20),
                      label: const Text('Applications'),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        AppSquircleIcon(name: summary.name, platform: summary.platform, size: 64),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      summary.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  StatusBadge(summary.state),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                meta.join('  ·  '),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: k.muted, fontSize: 13),
                              ),
                              if (summary.versionString != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Version ${summary.versionString}  ·  ${prettyPlatform(summary.platform)}',
                                    style: TextStyle(color: k.muted, fontSize: 13),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            ExportButton(
                              items: {
                                'Reviews': () async => reviewsTable(summary.name, (_reviews ?? await loadReviews(client, id)).reviews),
                                'In-app purchases': () async => purchasesTable(
                                  summary.name,
                                  (await client.all('/v1/apps/$id/inAppPurchasesV2', {'limit': '200'}, 2)).data,
                                ),
                              },
                            ),
                            OutlinedButton.icon(
                              onPressed: _openStore,
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('View on App Store'),
                            ),
                            FilledButton.icon(
                              onPressed: () => tabs.animateTo(_uploadTab),
                              icon: const Icon(Icons.upload_file, size: 17),
                              label: const Text('Upload .IPA'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SegmentedTabs(controller: tabs, labels: _tabLabels),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    ListingTab(client: client, appId: id, draft: _draft),
                    GroupsTab(client: client, appId: id),
                    ReviewsTab(client: client, appId: id, onLoaded: (d) => _reviews = d),
                    _BuildsTab(client: client, appId: id),
                    UploadTab(client: client, appId: id, bundleId: summary.bundleId),
                    _PurchasesTab(client: client, appId: id, appName: summary.name),
                    SubmitTab(client: client, appId: id, draft: _draft),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BuildsData {
  _BuildsData(this.builds, this.uploads, this.details);
  final ResourcePage builds;
  final List<BuildUpload> uploads;
  final Map<String, Resource> details;

  Set<String> get known => {
        for (final b in builds.data)
          if (builds.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') case final v?) buildKey(v, b.str('version') ?? ''),
      };
  List<BuildUpload> get pending => pendingUploads(uploads, known);
}

class _BuildsTab extends StatefulWidget {
  const _BuildsTab({required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  State<_BuildsTab> createState() => _BuildsTabState();
}

class _BuildsTabState extends State<_BuildsTab> {
  final _expiring = <String>{};
  _BuildsData? _data;
  Object? _error;
  bool _loading = true;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// [quiet] reloads in the background (no spinner) so the list does not flicker while a build is processing.
  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final r = await Future.wait<Object>([
        widget.client.all('/v1/builds', {'filter[app]': widget.appId, 'sort': '-uploadedDate', 'limit': '100', 'include': 'preReleaseVersion'}, 1),
        // The uploads list only adds rows; if Apple refuses it the builds are still shown.
        loadBuildUploads(widget.client, widget.appId).catchError((Object _) => <BuildUpload>[]),
        // TestFlight states are a bonus too.
        loadBetaDetails(widget.client, widget.appId).catchError((Object _) => <String, Resource>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _BuildsData(r[0] as ResourcePage, r[1] as List<BuildUpload>, r[2] as Map<String, Resource>);
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (!quiet || _data == null) setState(() => _error = e);
      setState(() => _loading = false);
    }
    _schedulePoll();
  }

  /// While anything is processing, look again every 20 seconds.
  void _schedulePoll() {
    _poll?.cancel();
    if (_data?.pending.any((u) => u.processing) ?? false) _poll = Timer(const Duration(seconds: 20), () => _load(quiet: true));
  }

  Future<void> _expire(Resource b, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Expire build $label?'),
        content: const Text(
          'Apple has no way to delete a build, so this expires it. It disappears from TestFlight, testers can no longer install it, '
          'and it can not be chosen for a submission.\n\nThis can not be undone. Apple refuses it for a build on a released version.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Expire Build'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _expiring.add(b.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await expireBuild(widget.client, b.id);
      messenger.showSnackBar(SnackBar(content: Text('Build $label expired.')));
      await _load(quiet: true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not expire $label: $e')));
    } finally {
      if (mounted) setState(() => _expiring.remove(b.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      if (_error != null) return ErrorView(error: _error!, onRetry: _load);
      return const Center(child: CircularProgressIndicator());
    }
    final p = _data!.builds;
    final pending = _data!.pending;
    if (p.data.isEmpty && pending.isEmpty) return const EmptyView('No builds uploaded.');
    final k = Tokens.of(context);
    return ListView(
      padding: const EdgeInsets.all(40),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              pending.any((u) => u.processing) ? 'Apple is processing an upload. This list refreshes by itself.' : '',
              style: TextStyle(color: k.muted, fontSize: 12.5),
            ),
          ),
          TextButton.icon(onPressed: _loading ? null : () => _load(), icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
        ]),
        const SizedBox(height: 6),
        RowsCard(
          children: [
            for (final u in pending) _uploadRow(u),
            for (final b in p.data) _buildRow(context, p, b),
          ],
        ),
        TruncatedNote(p, 'builds, newest first'),
      ],
    );
  }

  Widget _uploadRow(BuildUpload u) {
    final k = Tokens.of(context);
    final since = u.uploaded == null ? null : DateTime.now().difference(u.uploaded!);
    final took = since == null || since.isNegative ? '' : ' · ${u.processing ? 'for ' : ''}${_ago(since)}';
    final lines = <String>[
      if (u.failed && u.errors.isNotEmpty) ...u.errors.take(2) else '${u.stateLabel}$took',
      if (u.warnings.isNotEmpty) '${u.warnings.length} warning${u.warnings.length == 1 ? '' : 's'}: ${u.warnings.first}',
    ];
    return Tooltip(
      message: [...u.errors, ...u.warnings].join('\n\n'),
      waitDuration: const Duration(milliseconds: 500),
      child: ListTile(
        leading: u.processing
            ? const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.2)))
            : Icon(u.failed ? Icons.error_outline : Icons.hourglass_empty, color: u.failed ? Theme.of(context).colorScheme.error : null),
        title: Text(u.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(lines.join('\n'), maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(color: u.failed ? Theme.of(context).colorScheme.error : k.muted)),
        trailing: StateChip(u.state, label: u.stateLabel),
      ),
    );
  }

  static String _ago(Duration d) => d.inMinutes < 1 ? 'just now' : d.inHours < 1 ? '${d.inMinutes} min' : d.inDays < 1 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inDays} d';

  Widget _buildRow(BuildContext context, ResourcePage p, Resource b) {
    final expired = b.flag('expired') == true;
    final detail = _data?.details[b.id];
    final internal = betaStateLabel(detail?.str('internalBuildState'));
    final external = betaStateLabel(detail?.str('externalBuildState'));
    final label = '${p.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '—'} (${b.str('version')})';
    return ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Uploaded ${fmtDateTime(b.date('uploadedDate'))} · ${expired ? 'expired' : 'expires ${fmtDate(b.date('expirationDate'))}'} · iOS ${b.str('minOsVersion') ?? '—'}+'
        '${!expired && (internal.isNotEmpty || external.isNotEmpty) ? '\nTestFlight: ${[if (internal.isNotEmpty) 'internal $internal', if (external.isNotEmpty) 'external $external'].join(' · ')}' : ''}',
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        StateChip(expired ? 'EXPIRED' : b.str('processingState')),
        if (!expired) ...[
          const SizedBox(width: 10),
          _expiring.contains(b.id)
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: () => _expire(b, label),
                  child: const Text('Expire'),
                ),
        ],
      ]),
    );
  }
}

class _PurchaseData {
  _PurchaseData(this.iaps, this.groups);
  final ResourcePage iaps;
  final ResourcePage groups;
}

class _PurchasesTab extends StatefulWidget {
  const _PurchasesTab({required this.client, required this.appId, required this.appName});
  final AscClient client;
  final String appId;
  final String appName;

  @override
  State<_PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<_PurchasesTab> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<void> _open(Widget dialog) async {
    final changed = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => dialog);
    if (changed == true) _reload.reload();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final appId = widget.appId;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 16, 40, 0),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => _open(NewIapDialog(client: client, appId: appId, appName: widget.appName)),
                icon: const Icon(Icons.add),
                label: const Text('New in-app purchase'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _open(BulkIapDialog(client: client, appId: appId, appName: widget.appName)),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Bulk create'),
              ),
              const Spacer(),
              IconButton(tooltip: 'Refresh', onPressed: _reload.reload, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: LoadView<_PurchaseData>(
            controller: _reload,
            load: () async {
              final r = await Future.wait([
                client.all('/v1/apps/$appId/inAppPurchasesV2', {'limit': '200'}, 2),
                client.all('/v1/apps/$appId/subscriptionGroups', {'limit': '50', 'include': 'subscriptions'}, 1),
              ]);
              return _PurchaseData(r[0], r[1]);
            },
            builder: (context, d) {
              if (d.iaps.data.isEmpty && d.groups.data.isEmpty) {
                return const EmptyView('No in-app purchases or subscriptions yet.', icon: Icons.shopping_bag_outlined);
              }
              return ListView(
                padding: const EdgeInsets.all(40),
                children: [
                  if (d.iaps.data.isNotEmpty) ...[
                    _SectionLabel('In-app purchases · ${d.iaps.data.length}'),
                    RowsCard(
                      children: [
                        for (final i in d.iaps.data)
                          ListTile(
                            title: Text(i.str('name') ?? i.str('productId') ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${i.str('productId')} · ${prettyEnum(i.str('inAppPurchaseType'))}'),
                            trailing: StateChip(i.str('state')),
                          ),
                      ],
                    ),
                    TruncatedNote(d.iaps, 'in-app purchases'),
                    const SizedBox(height: 20),
                  ],
                  for (final g in d.groups.data) ...[
                    _SectionLabel('Subscription group · ${g.str('referenceName') ?? ''}'),
                    RowsCard(
                      children: [
                        for (final s in g.relIds('subscriptions').map((id) => d.groups.inc('subscriptions', id)).whereType<Resource>())
                          ListTile(
                            title: Text(s.str('name') ?? s.str('productId') ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${s.str('productId')} · ${prettyEnum(s.str('subscriptionPeriod'))}'),
                            trailing: StateChip(s.str('state')),
                          ),
                        if (g.relIds('subscriptions').isEmpty) const ListTile(title: Text('No subscriptions in this group.')),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  );
}
