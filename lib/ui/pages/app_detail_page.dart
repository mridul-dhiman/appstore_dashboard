import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/asc_client.dart';
import '../../api/export.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/reviews.dart';
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

class _BuildsTab extends StatelessWidget {
  const _BuildsTab({required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      load: () =>
          client.all('/v1/builds', {'filter[app]': appId, 'sort': '-uploadedDate', 'limit': '100', 'include': 'preReleaseVersion'}, 1),
      builder: (context, p) {
        if (p.data.isEmpty) return const EmptyView('No builds uploaded.');
        return ListView(
          padding: const EdgeInsets.all(40),
          children: [
            RowsCard(
              children: [
                for (final b in p.data)
                  ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(
                      '${p.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '—'} (${b.str('version')})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'Uploaded ${fmtDateTime(b.date('uploadedDate'))} · ${b.flag('expired') == true ? 'expired' : 'expires ${fmtDate(b.date('expirationDate'))}'} · iOS ${b.str('minOsVersion') ?? '—'}+',
                    ),
                    trailing: StateChip(b.flag('expired') == true ? 'EXPIRED' : b.str('processingState')),
                  ),
              ],
            ),
          ],
        );
      },
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
