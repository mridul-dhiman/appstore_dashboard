import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/analytics.dart';
import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'apps_page.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key, required this.client, required this.store});
  final AscClient client;
  final AppsStore store;

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _reload = ReloadController();
  AppSummary? _app;
  Resource? _request;
  List<AnalyticsReport>? _reports;
  bool _creating = false;

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<List<AppSummary>> _loadApps() => widget.store.apps;

  void _pickApp(AppSummary app) {
    setState(() {
      _app = app;
      _request = null;
      _reports = null;
    });
    unawaited(_loadRequest());
  }

  Future<void> _loadRequest() async {
    final app = _app;
    if (app == null) return;
    try {
      final reqs = await loadReportRequests(widget.client, app.id);
      if (!mounted || _app?.id != app.id) return;
      if (reqs.isEmpty) {
        setState(() => _request = null);
      } else {
        setState(() => _request = reqs.first);
        await _loadReports(reqs.first.id);
      }
    } on AscException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _createRequest() async {
    final app = _app;
    if (app == null) return;
    setState(() => _creating = true);
    try {
      final req = await createReportRequest(widget.client, app.id);
      if (!mounted || _app?.id != app.id) return;
      setState(() => _request = req);
      await _loadReports(req.id);
    } on AscException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _loadReports(String requestId) async {
    try {
      final reports = await loadReports(widget.client, requestId);
      if (mounted) setState(() => _reports = reports);
    } on AscException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _clearApp() => setState(() {
    _app = null;
    _request = null;
    _reports = null;
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(title: 'Analytics Reports', subtitle: 'Download engagement, usage, commerce and performance reports', reload: _reload),
        Expanded(
          child: _app == null
              ? _AppPicker(load: _loadApps, onPick: _pickApp)
              : _ReportsView(
                  client: widget.client,
                  app: _app!,
                  request: _request,
                  reports: _reports,
                  creating: _creating,
                  onCreateRequest: _createRequest,
                  onLoadReports: _loadReports,
                  onClearApp: _clearApp,
                ),
        ),
      ],
    );
  }
}

class _AppPicker extends StatelessWidget {
  const _AppPicker({required this.load, required this.onPick});
  final Future<List<AppSummary>> Function() load;
  final ValueChanged<AppSummary> onPick;

  @override
  Widget build(BuildContext context) {
    return LoadView<List<AppSummary>>(
      load: load,
      builder: (context, apps) {
        if (apps.isEmpty) return const EmptyView('No apps found.');
        return ListView(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
          children: [
            const SectionLabel('Choose an app to view analytics'),
            RowsCard(
              children: [
                for (final app in apps)
                  ListTile(
                    leading: AppSquircleIcon(name: app.name, platform: app.platform, size: 36),
                    title: Text(app.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${app.bundleId} · ${prettyPlatform(app.platform)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onPick(app),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _ReportsView extends StatelessWidget {
  const _ReportsView({
    required this.client,
    required this.app,
    required this.request,
    required this.reports,
    required this.creating,
    required this.onCreateRequest,
    required this.onLoadReports,
    required this.onClearApp,
  });
  final AscClient client;
  final AppSummary app;
  final Resource? request;
  final List<AnalyticsReport>? reports;
  final bool creating;
  final VoidCallback onCreateRequest;
  final void Function(String requestId) onLoadReports;
  final VoidCallback onClearApp;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      children: [
        Row(
          children: [
            AppSquircleIcon(name: app.name, platform: app.platform, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(app.bundleId, style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13)),
                ],
              ),
            ),
            OutlinedButton.icon(onPressed: onClearApp, icon: const Icon(Icons.swap_horiz, size: 16), label: const Text('Change app')),
          ],
        ),
        const SizedBox(height: 24),

        if (request == null && !creating) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.analytics_outlined, size: 40, color: Tokens.of(context).accent),
                  const SizedBox(height: 12),
                  const Text('No analytics report exists for this app yet.'),
                  const SizedBox(height: 8),
                  const Text(
                    'Request a snapshot and Apple generates the reports. This can take a few minutes.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: onCreateRequest, icon: const Icon(Icons.add), label: const Text('Request analytics report')),
                ],
              ),
            ),
          ),
        ] else if (creating) ...[
          const Center(
            child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
          ),
        ] else ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: Text('Report request · ${prettyEnum(request!.str('accessType'))}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StateChip(request!.str('stale') == 'true' ? 'STALE' : 'ACTIVE'),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: onCreateRequest, child: const Text('New request')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (reports == null)
            const Center(child: CircularProgressIndicator())
          else if (reports!.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.hourglass_empty, size: 36),
                    const SizedBox(height: 12),
                    const Text('Reports are still being generated. Check back in a few minutes.'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => onLoadReports(request!.id),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            for (final category in reportCategories.entries) ...[
              () {
                final catReports = reports!.where((r) => r.category == category.key).toList();
                if (catReports.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(category.value),
                    RowsCard(
                      children: [for (final report in catReports) _ReportRow(client: client, report: report)],
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }(),
            ],
          ],
        ],
      ],
    );
  }
}

class _ReportRow extends StatefulWidget {
  const _ReportRow({required this.client, required this.report});
  final AscClient client;
  final AnalyticsReport report;

  @override
  State<_ReportRow> createState() => _ReportRowState();
}

class _ReportRowState extends State<_ReportRow> {
  bool _loading = false;
  List<ReportInstance>? _instances;

  Future<void> _loadInstances() async {
    setState(() => _loading = true);
    try {
      final inst = await loadReportInstances(widget.client, widget.report.id);
      if (mounted) setState(() => _instances = inst);
    } on AscException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download(ReportInstance inst) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await reportSegmentUrl(widget.client, inst.id);
      if (url == null) {
        messenger.showSnackBar(const SnackBar(content: Text('No download URL available for this instance.')));
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on AscException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text(widget.report.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          trailing: _loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : OutlinedButton(onPressed: _loadInstances, child: Text(_instances == null ? 'Show dates' : 'Refresh')),
        ),
        if (_instances != null && _instances!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 0, 16, 12),
            child: Column(
              children: [
                for (final inst in _instances!.take(10))
                  Row(
                    children: [
                      Expanded(
                        child: Text('${inst.processingDate} · ${prettyEnum(inst.granularity)}', style: const TextStyle(fontSize: 13)),
                      ),
                      TextButton.icon(
                        onPressed: () => _download(inst),
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Download'),
                      ),
                    ],
                  ),
                if (_instances!.length > 10)
                  Text(
                    '… and ${_instances!.length - 10} more',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
                  ),
              ],
            ),
          ),
        if (_instances != null && _instances!.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(40, 0, 16, 12),
            child: Text('No instances yet. The report may still be processing.', style: TextStyle(fontSize: 13)),
          ),
      ],
    );
  }
}
