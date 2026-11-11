part of 'app_detail_page.dart';

class _BuildsData {
  _BuildsData(this.builds, this.uploads, this.details, [this.live = const {}]);
  final Set<String> live; // builds on a version that is on sale: Apple will not expire them
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
        widget.client.all('/v1/builds', {
          'filter[app]': widget.appId,
          'sort': '-uploadedDate',
          'limit': '100',
          'include': 'preReleaseVersion',
        }, 1),
        // The uploads list only adds rows; if Apple refuses it the builds are still shown.
        loadBuildUploads(widget.client, widget.appId).catchError((Object _) => <BuildUpload>[]),
        // TestFlight states are a bonus too.
        loadBetaDetails(widget.client, widget.appId).catchError((Object _) => <String, Resource>{}),
        loadLiveBuildIds(widget.client, widget.appId).catchError((Object _) => <String>{}),
      ]);
      if (!mounted) return;
      final next = _BuildsData(r[0] as ResourcePage, r[1] as List<BuildUpload>, r[2] as Map<String, Resource>, r[3] as Set<String>);
      _announceFinished(_data, next);
      setState(() {
        _data = next;
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

  /// Says so when an upload that was processing on the last look is now a build (or failed).
  void _announceFinished(_BuildsData? before, _BuildsData after) {
    if (before == null) return;
    final still = {for (final u in after.pending) u.id};
    for (final u in before.pending.where((u) => u.processing && !still.contains(u.id))) {
      final failed = after.uploads.where((x) => x.id == u.id && x.failed).isNotEmpty;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            failed ? 'Build ${u.label} failed processing.' : 'Build ${u.label} finished processing and is ready for TestFlight.',
          ),
        ),
      );
    }
  }

  /// While anything is processing, look again every 20 seconds.
  void _schedulePoll() {
    _poll?.cancel();
    if (_data?.pending.any((u) => u.processing) ?? false) _poll = Timer(const Duration(seconds: 20), () => _load(quiet: true));
  }

  Future<void> _expire(Resource b, String label, {bool live = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Expire build $label?'),
        content: Text(
          '${live ? 'This is the build that is live on the App Store now.\n\n' : ''}'
          'Apple has no way to delete a build, so this expires it. It disappears from TestFlight, testers can no longer install it, '
          'and it can not be chosen for a submission.\n\nThis can not be undone.',
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
        Row(
          children: [
            Expanded(
              child: Text(
                pending.any((u) => u.processing) ? 'Apple is processing an upload. This list refreshes by itself.' : '',
                style: TextStyle(color: k.muted, fontSize: 12.5),
              ),
            ),
            TextButton.icon(
              onPressed: _loading ? null : () => _load(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        RowsCard(children: [for (final u in pending) _uploadRow(u), for (final b in p.data) _buildRow(context, p, b)]),
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
            ? const SizedBox(
                width: 24,
                height: 24,
                child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.2)),
              )
            : Icon(u.failed ? Icons.error_outline : Icons.hourglass_empty, color: u.failed ? Theme.of(context).colorScheme.error : null),
        title: Text(u.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          lines.join('\n'),
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: u.failed ? Theme.of(context).colorScheme.error : k.muted),
        ),
        trailing: StateChip(u.state, label: u.stateLabel),
      ),
    );
  }

  static String _ago(Duration d) => d.inMinutes < 1
      ? 'just now'
      : d.inHours < 1
      ? '${d.inMinutes} min'
      : d.inDays < 1
      ? '${d.inHours} h ${d.inMinutes % 60} min'
      : '${d.inDays} d';

  Widget _buildRow(BuildContext context, ResourcePage p, Resource b) {
    final expired = b.flag('expired') == true;
    final detail = _data?.details[b.id];
    final live = _data?.live.contains(b.id) ?? false;
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live && !expired) ...[const StateChip('READY_FOR_SALE', label: 'Live on App Store'), const SizedBox(width: 8)],
          StateChip(expired ? 'EXPIRED' : b.str('processingState')),
          if (!expired) ...[
            const SizedBox(width: 10),
            _expiring.contains(b.id)
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                    onPressed: () => _expire(b, label, live: live),
                    child: const Text('Expire'),
                  ),
          ],
        ],
      ),
    );
  }
}
