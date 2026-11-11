import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/asc_client.dart';
import '../../api/export.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/reviews.dart';
import '../../api/testflight.dart';
import '../../state/reply_templates.dart';
import '../../state/upload_jobs.dart';
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
part 'builds_tab.dart';
part 'purchases_tab.dart';

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
  const AppDetailPage({
    super.key,
    required this.client,
    required this.summary,
    required this.onBack,
    this.initialTab = 0,
    this.uploads,
    this.onTabChanged,
    this.templates,
    this.onUnsavedChanged,
  });
  final AscClient client;

  /// The shell's build uploads. Null when the page is shown on its own (tests).
  final UploadJobs? uploads;

  /// Told whether the listing has edits that are not sent yet, so leaving the page can ask first.
  final ValueChanged<bool>? onUnsavedChanged;

  /// This client's review reply templates.
  final ReplyTemplates? templates;

  /// Told the tab index whenever it changes, so the shell can reopen the same tab next launch.
  final ValueChanged<int>? onTabChanged;
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

  /// The shell's uploads (they outlive this page); a page shown on its own keeps its own.
  late final _fallbackUploads = UploadJobs();
  String? _iconUrl;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_draftChanged);
    // The list shows initials to stay at one request; here one more small request gets the real icon.
    loadAppIconUrl(widget.client, widget.summary.id).then((u) {
      if (mounted && u != null) setState(() => _iconUrl = u);
    }, onError: (_) {});
  }

  UploadJobs get _uploads => widget.uploads ?? _fallbackUploads;

  @override
  void dispose() {
    _draft.removeListener(_draftChanged);
    widget.onUnsavedChanged?.call(false);
    _draft.dispose();
    super.dispose();
  }

  bool _wasUnsaved = false;
  void _draftChanged() {
    final now = !_draft.isEmpty;
    if (now != _wasUnsaved) widget.onUnsavedChanged?.call(_wasUnsaved = now);
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
          return _TabWatcher(
            controller: tabs,
            onChanged: widget.onTabChanged,
            child: Column(
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
                          AppSquircleIcon(name: summary.name, platform: summary.platform, size: 64, imageUrl: _iconUrl),
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
                      ReviewsTab(client: client, appId: id, onLoaded: (d) => _reviews = d, templates: widget.templates),
                      _BuildsTab(client: client, appId: id),
                      UploadTab(client: client, appId: id, bundleId: summary.bundleId, uploads: _uploads),
                      _PurchasesTab(client: client, appId: id, appName: summary.name),
                      SubmitTab(client: client, appId: id, draft: _draft),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Reports tab changes of [controller] to [onChanged].
class _TabWatcher extends StatefulWidget {
  const _TabWatcher({required this.controller, required this.onChanged, required this.child});
  final TabController controller;
  final ValueChanged<int>? onChanged;
  final Widget child;

  @override
  State<_TabWatcher> createState() => _TabWatcherState();
}

class _TabWatcherState extends State<_TabWatcher> {
  int? _last;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_tick);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    final i = widget.controller.index;
    if (i == _last) return;
    _last = i;
    widget.onChanged?.call(i);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
