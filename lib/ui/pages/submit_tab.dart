import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/listing.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/queries.dart';
import '../../api/submission.dart';
import '../widgets.dart';

part 'submit_dialogs.dart';

String? _state(Resource v) => v.str('appStoreState') ?? v.str('appVersionState');

/// "1.1.16" → "1.1.17".
String suggestNextVersion(String? latest) {
  if (latest == null || latest.isEmpty) return '1.0.0';
  final parts = latest.split('.');
  final last = int.tryParse(parts.last);
  if (last == null) return latest;
  return [...parts.take(parts.length - 1), '${last + 1}'].join('.');
}

/// The path to App Review: checks what Apple would refuse, fixes it from here, then submits.
class SubmitTab extends StatefulWidget {
  const SubmitTab({super.key, required this.client, required this.appId, required this.draft});
  final AscClient client;
  final String appId;
  final ListingDraft draft;

  @override
  State<SubmitTab> createState() => _SubmitTabState();
}

class _SubmitTabState extends State<SubmitTab> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      controller: _reload,
      load: () => loadVersions(widget.client, widget.appId),
      builder: (context, p) => _Body(
        key: ValueKey(p.data.map((v) => v.id).join(',')),
        client: widget.client,
        appId: widget.appId,
        draft: widget.draft,
        versions: p.data,
        onVersionsChanged: _reload.reload,
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body({
    super.key,
    required this.client,
    required this.appId,
    required this.draft,
    required this.versions,
    required this.onVersionsChanged,
  });
  final AscClient client;
  final String appId;
  final ListingDraft draft;
  final List<Resource> versions;
  final VoidCallback onVersionsChanged;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _pre = ReloadController();
  late Resource _version;
  bool _busy = false;

  SubmissionFlow get _flow => SubmissionFlow(widget.client, widget.appId);

  @override
  void initState() {
    super.initState();
    _version = widget.versions.isEmpty
        ? Resource(id: '', type: 'appStoreVersions', attributes: const {}, relationships: const {})
        : widget.versions.firstWhere((v) => isVersionEditable(_state(v)), orElse: () => widget.versions.first);
    if (_version.id.isNotEmpty) unawaited(_loadPhased());
  }

  @override
  void dispose() {
    _pre.dispose();
    super.dispose();
  }

  Future<PreflightData> _loadPre() => loadPreflight(widget.client, widget.appId, _version, hasPriorVersion: widget.versions.length > 1);

  /// Runs a change against Apple, shows its error if it fails, and refreshes the checklist.
  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      _pre.reload();
      return true;
    } on AscException catch (e) {
      if (mounted) await _showError(e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showError(String message) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Apple refused that'),
      content: SelectableText(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );

  /// The platform of the version being worked on (iOS, macOS, tvOS, visionOS). New versions and builds follow it.
  String get _platform => _version.str('platform') ?? (widget.versions.isEmpty ? null : widget.versions.first.str('platform')) ?? 'IOS';

  Future<List<Resource>> _validBuilds() => loadAttachableBuilds(widget.client, widget.appId, _platform);

  Future<void> _newVersion() async {
    final latest = widget.versions.isEmpty ? null : widget.versions.first.str('versionString');
    final result = await showDialog<({String version, String release, String? buildId})>(
      context: context,
      builder: (_) => _NewVersionDialog(suggestion: suggestNextVersion(latest), loadBuilds: _validBuilds),
    );
    if (result == null) return;
    final ok = await _run(() async {
      await _flow.createVersion(versionString: result.version, platform: _platform, releaseType: result.release, buildId: result.buildId);
    });
    if (ok) widget.onVersionsChanged();
  }

  Future<void> _pickBuild() async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _BuildPickerDialog(loadBuilds: _validBuilds),
    );
    if (id != null) await _run(() => _flow.attachBuild(_version.id, id));
  }

  Future<void> _compliance(Resource build) async {
    final uses = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export compliance'),
        content: const Text(
          'Does this build use encryption beyond what iOS provides (anything other than HTTPS and standard system APIs)?\n\n'
          'Choose "No" if the app only uses HTTPS and Apple\'s built-in encryption. If you choose "Yes", Apple may also need an encryption declaration filed in App Store Connect.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, it does')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No, it does not')),
        ],
      ),
    );
    if (uses != null) {
      await _run(() => _flow.setExportCompliance(build.id, uses));
    }
  }

  Future<void> _reviewDetail(PreflightData d) async {
    final r = await showDialog<({Map<String, String> fields, bool demo})>(
      context: context,
      builder: (_) => _ReviewDetailDialog(existing: d.reviewDetail),
    );
    if (r != null) {
      await _run(() => _flow.saveReviewDetail(_version.id, existingId: d.reviewDetail?.id, fields: r.fields, demoAccountRequired: r.demo));
    }
  }

  Future<void> _release() async {
    final r = await showDialog<({String type, DateTime? date})>(
      context: context,
      builder: (_) => _ReleaseDialog(current: _version.str('releaseType')),
    );
    if (r != null) {
      await _run(() => _flow.setReleaseType(_version.id, r.type, earliest: r.date));
      widget.onVersionsChanged();
    }
  }

  // ---- Phased release ----

  Resource? _phasedRelease;

  Future<void> _loadPhased() async {
    try {
      _phasedRelease = await loadPhasedRelease(widget.client, _version.id);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _createPhased() async {
    await _run(() async {
      _phasedRelease = await createPhasedRelease(widget.client, _version.id);
    });
  }

  Future<void> _updatePhased(String state) async {
    final pr = _phasedRelease;
    if (pr == null) return;
    await _run(() async {
      await updatePhasedRelease(widget.client, pr.id, state);
      _phasedRelease = await loadPhasedRelease(widget.client, _version.id);
    });
  }

  Future<void> _deletePhased() async {
    final pr = _phasedRelease;
    if (pr == null) return;
    await _run(() async {
      await deletePhasedRelease(widget.client, pr.id);
      _phasedRelease = null;
    });
  }

  void _fix(CheckFix key, PreflightData d) {
    switch (key) {
      case CheckFix.version:
        unawaited(_newVersion());
      case CheckFix.build:
        unawaited(_pickBuild());
      case CheckFix.compliance:
        if (d.build != null) unawaited(_compliance(d.build!));
      case CheckFix.review:
        unawaited(_reviewDetail(d));
      case CheckFix.release:
        unawaited(_release());
      case CheckFix.listing:
        DefaultTabController.maybeOf(context)?.animateTo(0);
    }
  }

  Future<void> _submit() async {
    // Check again against Apple right now: the screen may be minutes old.
    setState(() => _busy = true);
    PreflightData fresh;
    try {
      fresh = await _loadPre();
    } on AscException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        await _showError(e.message);
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final checks = [...evaluatePreflight(fresh), ..._draftChecks()];
    if (!canSubmit(checks)) {
      _pre.reload();
      await _showError('Not ready: ${checks.where((c) => c.level == CheckLevel.fail).map((c) => c.title).join('; ')}.');
      return;
    }
    final versionString = _version.str('versionString') ?? '';
    final build = fresh.build;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmSubmitDialog(
        versionString: versionString,
        buildNumber: build?.str('version') ?? '?',
        release: releaseTypes[_version.str('releaseType')] ?? 'Not set',
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final out = await _flow.submit(_version.id, platform: _platform);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Color(0xFF1F8F45), size: 36),
          title: const Text('Submitted for review'),
          content: Text('Version $versionString is now ${prettyState(out.state)}. You can cancel it from this tab while it is waiting.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      widget.onVersionsChanged();
    } on AscException catch (e) {
      if (mounted) await _showError(e.message);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _pre.reload();
      }
    }
  }

  Widget _phasedReleaseCard() {
    final pr = _phasedRelease;
    final state = pr?.str('phasedReleaseState') ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timelapse, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Phased Release',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                if (pr == null)
                  OutlinedButton(onPressed: _busy ? null : _createPhased, child: const Text('Enable'))
                else ...[
                  StateChip(state, label: phasedReleaseLabel(pr)),
                ],
              ],
            ),
            if (pr == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Roll out the update gradually over 7 days (1% → 2% → 5% → 10% → 20% → 50% → 100%).',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ),
            if (pr != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (state == 'INACTIVE' || state == 'PAUSED')
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _updatePhased('ACTIVE'),
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(state == 'PAUSED' ? 'Resume' : 'Start'),
                      ),
                    if (state == 'ACTIVE')
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _updatePhased('PAUSE'),
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('Pause'),
                      ),
                    if (state == 'ACTIVE' || state == 'PAUSED')
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _updatePhased('COMPLETE'),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Release to all'),
                      ),
                    if (state == 'INACTIVE')
                      OutlinedButton(
                        onPressed: _busy ? null : _deletePhased,
                        style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                        child: const Text('Remove'),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Check> _draftChecks() => widget.draft.isEmpty
      ? const []
      : [
          Check(
            CheckLevel.fail,
            'Unsent listing changes',
            '${widget.draft.count} staged change(s) have not been applied. Apply the changelist on the Listing tab first, so what you submit is what you reviewed.',
            CheckFix.listing,
          ),
        ];

  Future<void> _cancel(ActiveSubmission s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this submission?'),
        content: const Text('The version is removed from the review queue and goes back to being editable. You can submit it again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel submission')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _flow.cancel(s.resource.id));
      widget.onVersionsChanged();
    }
  }

  Widget _checkRow(Check c, PreflightData d) {
    final t = Theme.of(context);
    final (icon, color) = switch (c.level) {
      CheckLevel.pass => (Icons.check_circle, const Color(0xFF1F8F45)),
      CheckLevel.warn => (Icons.warning_amber_rounded, const Color(0xFFB77300)),
      CheckLevel.fail => (Icons.cancel, t.colorScheme.error),
    };
    final fixLabel = switch (c.fix) {
      CheckFix.version => 'New version…',
      CheckFix.build => 'Choose build…',
      CheckFix.compliance => 'Answer…',
      CheckFix.review => 'Edit…',
      CheckFix.release => 'Choose…',
      CheckFix.listing => 'Open Listing',
      null => null,
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: c.detail == null ? null : Text(c.detail!),
      trailing: c.level != CheckLevel.pass && c.fix != null && fixLabel != null
          ? OutlinedButton(onPressed: _busy ? null : () => _fix(c.fix!, d), child: Text(fixLabel))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (widget.versions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EmptyView('This app has no App Store version yet.'),
            FilledButton(onPressed: _newVersion, child: const Text('Create the first version')),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('sv${_version.id}'),
                initialValue: _version.id,
                decoration: const InputDecoration(labelText: 'Version to submit'),
                items: [
                  for (final v in widget.versions)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text('${v.str('versionString')} · ${prettyEnum(_state(v))}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _busy ? null : (id) => setState(() => _version = widget.versions.firstWhere((v) => v.id == id)),
              ),
            ),
            StateChip(_state(_version)),
            OutlinedButton.icon(onPressed: _busy ? null : _newVersion, icon: const Icon(Icons.add), label: const Text('New version')),
            IconButton(tooltip: 'Re-check', onPressed: _pre.reload, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          // key: a different version is a different checklist
          key: ValueKey('pre${_version.id}'),
          child: LoadView<PreflightData>(
            controller: _pre,
            load: _loadPre,
            builder: (context, d) => ListenableBuilder(
              listenable: widget.draft,
              builder: (context, _) {
                final checks = [...evaluatePreflight(d), ..._draftChecks()];
                final ready = canSubmit(checks);
                final blocked = checks.where((c) => c.level == CheckLevel.fail).length;
                final cancelable = d.submissions
                    .where((s) => const {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES'}.contains(s.state))
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (cancelable.isNotEmpty) ...[
                      Card(
                        child: Column(
                          children: [
                            for (final s in cancelable)
                              ListTile(
                                leading: const Icon(Icons.hourglass_top),
                                title: const Text('In the review queue', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Submission ${s.resource.id.substring(0, 8)}… · ${prettyState(s.state)}'),
                                trailing: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    StateChip(s.state),
                                    OutlinedButton(onPressed: _busy ? null : () => _cancel(s), child: const Text('Cancel submission')),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    RowsCard(children: [for (final c in checks) _checkRow(c, d)]),
                    const SizedBox(height: 16),
                    _phasedReleaseCard(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: (!ready || _busy) ? null : _submit,
                          icon: _busy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.send_outlined),
                          label: Text('Submit ${_version.str('versionString')} for review'),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            ready ? 'All required checks pass.' : '$blocked thing${blocked == 1 ? '' : 's'} to fix first.',
                            style: t.textTheme.bodyMedium?.copyWith(color: ready ? const Color(0xFF1F8F45) : t.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The checks cover what the API can see. Apple can still ask for more at review time (for example age rating answers or pricing), and Submit asks you to confirm first.',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---- Dialogs --------------------------------------------------------------------------------------------------------
