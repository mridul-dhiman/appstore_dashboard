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
    unawaited(_load());
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
        loadBuilds(widget.client, widget.appId),
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
        for (final (i, g) in _groups(p, pending).indexed) _versionGroup(p, g, expandedByDefault: i == 0),
        TruncatedNote(p, 'builds, newest first'),
      ],
    );
  }

  /// Builds and in-flight uploads under their app version, newest version first (builds already arrive newest first).
  List<({String version, List<BuildUpload> uploads, List<Resource> builds})> _groups(ResourcePage p, List<BuildUpload> pending) {
    final order = <String>[];
    final uploads = <String, List<BuildUpload>>{};
    final builds = <String, List<Resource>>{};
    for (final u in pending) {
      if (!uploads.containsKey(u.shortVersion) && !builds.containsKey(u.shortVersion)) order.add(u.shortVersion);
      (uploads[u.shortVersion] ??= []).add(u);
    }
    for (final b in p.data) {
      final v = p.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '—';
      if (!uploads.containsKey(v) && !builds.containsKey(v)) order.add(v);
      (builds[v] ??= []).add(b);
    }
    return [for (final v in order) (version: v, uploads: uploads[v] ?? const [], builds: builds[v] ?? const [])];
  }

  final _toggled = <String>{};

  Widget _versionGroup(
    ResourcePage p,
    ({String version, List<BuildUpload> uploads, List<Resource> builds}) g, {
    required bool expandedByDefault,
  }) {
    final k = Tokens.of(context);
    final live = g.builds.any((b) => (_data?.live.contains(b.id) ?? false) && b.flag('expired') != true);
    final open = (expandedByDefault || live) != _toggled.contains(g.version);
    final count = g.uploads.length + g.builds.length;
    final allExpired = g.uploads.isEmpty && g.builds.every((b) => b.flag('expired') == true);
    final rows = [for (final u in g.uploads) _uploadRow(u), for (final b in g.builds) _buildRow(context, p, b)];
    // One card per version, its header inside, as in the design.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _toggled.contains(g.version) ? _toggled.remove(g.version) : _toggled.add(g.version)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20, color: k.muted),
                    const SizedBox(width: 6),
                    Text('Version ${g.version}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: k.ink)),
                    const SizedBox(width: 10),
                    Text(
                      '$count build${count == 1 ? '' : 's'}${allExpired ? ' · all expired' : ''}',
                      style: TextStyle(color: k.muted, fontSize: 12.5),
                    ),
                    // An open group shows these on its rows, so the header only summarises a closed one.
                    if (!open && g.uploads.any((u) => u.processing)) ...[
                      const SizedBox(width: 10),
                      const StateChip('PROCESSING', label: 'Processing'),
                    ],
                    if (!open && live) ...[const SizedBox(width: 10), const StateChip('READY_FOR_SALE', label: 'Live on App Store')],
                    const Spacer(),
                    if (allExpired && !live) const StateChip(null, label: 'Archived'),
                  ],
                ),
              ),
            ),
            if (open)
              for (final r in rows) ...[const Divider(), r],
          ],
        ),
      ),
    );
  }

  /// A rounded icon tile, tinted by how the build stands.
  Widget _tile(IconData icon, Color fg, Color bg) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: fg.withValues(alpha: 0.25))),
    child: Icon(icon, size: 19, color: fg),
  );

  /// "● Internal: In testing", the dot coloured by the state's tone.
  Widget _betaState(String who, String? state) {
    final k = Tokens.of(context);
    final label = betaStateLabel(state);
    final color = switch (toneFor(state)) {
      Tone.good => k.good,
      Tone.warn => k.warn,
      Tone.bad => k.bad,
      Tone.neutral => k.muted,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$who: ', style: TextStyle(color: k.muted)),
              TextSpan(text: label, style: TextStyle(color: k.body, fontWeight: FontWeight.w500)),
            ],
          ),
          style: const TextStyle(fontSize: 12.5),
        ),
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
            ? Container(
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: k.warnSoft, borderRadius: BorderRadius.circular(10)),
                child: CircularProgressIndicator(strokeWidth: 2, color: k.warn),
              )
            : _tile(u.failed ? Icons.error_outline : Icons.hourglass_empty, u.failed ? k.bad : k.warn, u.failed ? k.badSoft : k.warnSoft),
        title: Text('Build ${u.buildNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
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
    final k = Tokens.of(context);
    final valid = !expired && b.str('processingState') == 'VALID';
    final (icon, fg, bg) = expired
        ? (Icons.inventory_2_outlined, k.muted, k.inset)
        : live
        ? (Icons.storefront_outlined, k.good, k.goodSoft)
        : valid
        ? (Icons.verified_outlined, k.good, k.goodSoft)
        : (Icons.inventory_2_outlined, k.warn, k.warnSoft);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _tile(icon, fg, bg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Build ${b.str('version') ?? '—'}', style: TextStyle(fontWeight: FontWeight.w700, color: k.ink)),
                    StateChip(expired ? 'EXPIRED' : b.str('processingState')),
                    if (live && !expired) const StateChip('READY_FOR_SALE', label: 'Live on App Store'),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Uploaded ${fmtDateTime(b.date('uploadedDate'))} · ${expired ? 'expired' : 'expires ${fmtDate(b.date('expirationDate'))}'} · iOS ${b.str('minOsVersion') ?? '—'}+',
                  style: TextStyle(color: k.muted, fontSize: 12.5),
                ),
                if (!expired && (internal.isNotEmpty || external.isNotEmpty)) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      if (internal.isNotEmpty) _betaState('Internal', detail?.str('internalBuildState')),
                      if (external.isNotEmpty) _betaState('External', detail?.str('externalBuildState')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!expired) ...[
            const SizedBox(width: 10),
            _expiring.contains(b.id)
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: k.bad,
                      side: BorderSide(color: k.bad.withValues(alpha: 0.35)),
                      backgroundColor: k.badSoft,
                    ),
                    onPressed: () => _expire(b, label, live: live),
                    icon: const Icon(Icons.timer_off_outlined, size: 16),
                    label: const Text('Expire'),
                  ),
          ],
        ],
      ),
    );
  }
}
