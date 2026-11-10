import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../widgets.dart';
import 'apps_page.dart';
import 'iap_dialogs.dart';
import 'groups_tab.dart';
import 'listing_tab.dart';
import 'submit_tab.dart';
import 'upload_tab.dart';
import '../../api/listing_draft.dart';

class AppDetailPage extends StatefulWidget {
  const AppDetailPage({super.key, required this.client, required this.summary});
  final AscClient client;
  final AppSummary summary;

  @override
  State<AppDetailPage> createState() => _AppDetailPageState();
}

class _AppDetailPageState extends State<AppDetailPage> {
  /// Staged listing edits, shared by the Listing tab (which edits them) and the Submit tab (which refuses to submit while
  /// they are unsent).
  late final _draft = ListingDraft(libraryId: widget.summary.app.id);

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final summary = widget.summary;
    final app = summary.app;
    final id = app.id;
    final t = Theme.of(context);
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: t.scaffoldBackgroundColor,
          scrolledUnderElevation: 0,
          title: Row(children: [
            AppIcon(url: summary.iconUrl(96), size: 36),
            const SizedBox(width: 12),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text('${app.str('bundleId')} · SKU ${app.str('sku')} · ID $id', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Versions'),
            Tab(text: 'Listing'),
            Tab(text: 'Builds'),
            Tab(text: 'TestFlight'),
            Tab(text: 'Reviews'),
            Tab(text: 'Purchases'),
            Tab(text: 'Upload'),
            Tab(text: 'Submit'),
          ]),
        ),
        body: TabBarView(children: [
              _VersionsTab(client: client, appId: id),
              ListingTab(client: client, appId: id, draft: _draft),
              _BuildsTab(client: client, appId: id),
              GroupsTab(client: client, appId: id),
              _ReviewsTab(client: client, appId: id),
              _PurchasesTab(client: client, appId: id, appName: app.str('name') ?? ''),
              UploadTab(client: client, appId: id, bundleId: app.str('bundleId') ?? ''),
              SubmitTab(client: client, appId: id, draft: _draft),
            ]),
      ),
    );
  }
}

class _VersionsTab extends StatelessWidget {
  const _VersionsTab({required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      load: () => client.all('/v1/apps/$appId/appStoreVersions', {'limit': '200'}, 2),
      builder: (context, p) {
        if (p.data.isEmpty) return const EmptyView('No App Store versions yet.');
        return ListView(padding: const EdgeInsets.all(40), children: [
          RowsCard(children: [
            for (final v in p.data)
              ListTile(
                leading: const Icon(Icons.phone_iphone),
                title: Text('Version ${v.str('versionString')}', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${prettyPlatform(v.str('platform'))} · created ${fmtDate(v.date('createdDate'))} · ${prettyEnum(v.str('releaseType'))} release'),
                trailing: StateChip(v.str('appStoreState') ?? v.str('appVersionState')),
              ),
          ]),
          if (p.total != null && p.total! > p.data.length)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('Showing the latest ${p.data.length} of ${p.total}.')),
        ]);
      },
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
      load: () => client.all('/v1/builds', {'filter[app]': appId, 'sort': '-uploadedDate', 'limit': '100', 'include': 'preReleaseVersion'}, 1),
      builder: (context, p) {
        if (p.data.isEmpty) return const EmptyView('No builds uploaded.');
        return ListView(padding: const EdgeInsets.all(40), children: [
          RowsCard(children: [
            for (final b in p.data)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('${p.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '—'} (${b.str('version')})',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Uploaded ${fmtDateTime(b.date('uploadedDate'))} · ${b.flag('expired') == true ? 'expired' : 'expires ${fmtDate(b.date('expirationDate'))}'} · iOS ${b.str('minOsVersion') ?? '—'}+'),
                trailing: StateChip(b.flag('expired') == true ? 'EXPIRED' : b.str('processingState')),
              ),
          ]),
        ]);
      },
    );
  }
}

class _ReviewData {
  _ReviewData(this.reviews, this.total);
  final List<Resource> reviews;
  final int? total;
}

class _ReviewsTab extends StatelessWidget {
  const _ReviewsTab({required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  Widget build(BuildContext context) {
    return LoadView<_ReviewData>(
      load: () async {
        final p = await client.all('/v1/apps/$appId/customerReviews', {'sort': '-createdDate', 'limit': '200'}, 1);
        return _ReviewData(p.data, p.total);
      },
      builder: (context, d) {
        if (d.reviews.isEmpty) return const EmptyView('No customer reviews yet.', icon: Icons.rate_review_outlined);
        final ratings = d.reviews.map((r) => r.integer('rating') ?? 0).toList();
        final avg = ratings.reduce((a, b) => a + b) / ratings.length;
        final counts = [for (var s = 5; s >= 1; s--) ratings.where((r) => r == s).length];
        final t = Theme.of(context);
        return ListView(padding: const EdgeInsets.all(40), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Column(children: [
                  Text(avg.toStringAsFixed(1), style: t.textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${fmtNum(d.total ?? d.reviews.length)} reviews', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                  if (d.total != null && d.total! > d.reviews.length)
                    Text('average of latest ${d.reviews.length}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(children: [
                    for (var i = 0; i < 5; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          SizedBox(width: 14, child: Text('${5 - i}')),
                          const Icon(Icons.star, size: 12, color: Color(0xFFF5A524)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: counts[i] / d.reviews.length, minHeight: 6, backgroundColor: t.colorScheme.surfaceContainerHighest),
                            ),
                          ),
                          SizedBox(width: 36, child: Text('${counts[i]}', textAlign: TextAlign.end, style: t.textTheme.bodySmall)),
                        ]),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          RowsCard(children: [
            for (final r in d.reviews)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    for (var i = 1; i <= 5; i++) Icon(i <= (r.integer('rating') ?? 0) ? Icons.star : Icons.star_border, size: 16, color: const Color(0xFFF5A524)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.str('title') ?? '', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  ]),
                  const SizedBox(height: 4),
                  Text('${r.str('reviewerNickname') ?? 'Anonymous'} · ${r.str('territory') ?? ''} · ${fmtDate(r.date('createdDate'))}',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  SelectableText(r.str('body') ?? ''),
                ]),
              ),
          ]),
        ]);
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
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(40, 16, 40, 0),
        child: Row(children: [
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
        ]),
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
            if (d.iaps.data.isEmpty && d.groups.data.isEmpty) return const EmptyView('No in-app purchases or subscriptions yet.', icon: Icons.shopping_bag_outlined);
            return ListView(padding: const EdgeInsets.all(40), children: [
              if (d.iaps.data.isNotEmpty) ...[
                _SectionLabel('In-app purchases · ${d.iaps.data.length}'),
                RowsCard(children: [
                  for (final i in d.iaps.data)
                    ListTile(
                      title: Text(i.str('name') ?? i.str('productId') ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${i.str('productId')} · ${prettyEnum(i.str('inAppPurchaseType'))}'),
                      trailing: StateChip(i.str('state')),
                    ),
                ]),
                const SizedBox(height: 20),
              ],
              for (final g in d.groups.data) ...[
                _SectionLabel('Subscription group · ${g.str('referenceName') ?? ''}'),
                RowsCard(children: [
                  for (final s in g.relIds('subscriptions').map((id) => d.groups.inc('subscriptions', id)).whereType<Resource>())
                    ListTile(
                      title: Text(s.str('name') ?? s.str('productId') ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${s.str('productId')} · ${prettyEnum(s.str('subscriptionPeriod'))}'),
                      trailing: StateChip(s.str('state')),
                    ),
                  if (g.relIds('subscriptions').isEmpty) const ListTile(title: Text('No subscriptions in this group.')),
                ]),
                const SizedBox(height: 20),
              ],
            ]);
          },
        ),
      ),
    ]);
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
