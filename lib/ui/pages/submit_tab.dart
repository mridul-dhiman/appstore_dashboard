import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/asc_client.dart';
import '../../api/listing.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/queries.dart';
import '../../api/submission.dart';
import '../theme.dart';
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
  const SubmitTab({super.key, required this.client, required this.appId, required this.draft, this.onNewestVersion});
  final AscClient client;
  final String appId;
  final ListingDraft draft;

  /// Called with the newest version each time the versions load, e.g. after submitting, so the page header can show its
  /// current state.
  final ValueChanged<Resource>? onNewestVersion;

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
      load: () async {
        final p = await loadVersions(widget.client, widget.appId);
        if (p.data.isNotEmpty) widget.onNewestVersion?.call(p.data.first);
        return p;
      },
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

  /// The version list reloads after a change (submit, release type); show the selected version's new state.
  @override
  void didUpdateWidget(_Body old) {
    super.didUpdateWidget(old);
    final fresh = widget.versions.where((v) => v.id == _version.id).firstOrNull;
    if (fresh != null && !identical(fresh, _version)) _version = fresh;
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

  Future<void> _pickBuild({String? currentId}) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => _BuildPickerDialog(loadBuilds: _validBuilds, currentId: currentId),
    );
    if (id != null) await _run(() => _flow.attachBuild(_version.id, id));
  }

  /// The version's rejected submission, if App Review sent it back.
  ActiveSubmission? _rejection(PreflightData d) =>
      d.submissions.where((s) => s.isUnresolved && s.versionIds.contains(_version.id)).firstOrNull;

  Future<void> _reply(PreflightData d) async {
    final r = await showDialog<({String text, bool resubmit})>(
      context: context,
      builder: (_) => _ReplyDialog(existingNotes: d.reviewDetail?.str('notes'), canResubmit: _rejection(d) != null),
    );
    if (r == null) return;
    final ok = await _run(() => _flow.replyInNotes(_version.id, d.reviewDetail, r.text));
    if (!ok || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply added to the App Review notes.')));
    if (r.resubmit) await _submit();
  }

  Uri get _ascVersionPage => Uri.parse('https://appstoreconnect.apple.com/apps/${widget.appId}/distribution');

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
        unawaited(_pickBuild(currentId: d.build?.id));
      case CheckFix.reply:
        unawaited(_reply(d));
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
    final resubmit = _rejection(fresh) != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmSubmitDialog(
        versionString: versionString,
        buildNumber: build?.str('version') ?? '?',
        release: releaseTypes[_version.str('releaseType')] ?? 'Not set',
        resubmit: resubmit,
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
          title: Text(out.resubmitted ? 'Resubmitted for review' : 'Submitted for review'),
          content: Text(
            out.state == null
                ? 'Apple accepted version $versionString. Its status in App Store Connect can take a minute to update; refresh this tab to see it.'
                : 'Version $versionString is now ${prettyState(out.state)}. You can cancel it from this tab while it is waiting.',
          ),
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
                  child: Text('Phased Release', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
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

  /// The build attached to the version, and changing it, as on the version page in App Store Connect.
  Widget _buildCard(PreflightData d) {
    final t = Theme.of(context);
    final b = d.build;
    final inQueue = d.submissions.any(
      (s) => s.versionIds.contains(_version.id) && const {'WAITING_FOR_REVIEW', 'IN_REVIEW'}.contains(s.state),
    );
    final canChange = isVersionEditable(_state(_version)) && !inQueue;
    final hint = inQueue
        ? 'The version is with App Review. Cancel the submission to change its build.'
        : !isVersionEditable(_state(_version))
        ? 'This version is ${prettyState(_state(_version))}; its build can no longer change. Create a new version.'
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b == null ? 'No build attached' : 'Build ${b.str('version')}',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      if (b != null)
                        Text(
                          'Uploaded ${fmtDateTime(b.date('uploadedDate'))} · '
                          '${b.flag('expired') == true ? 'expired' : 'expires ${fmtDate(b.date('expirationDate'))}'}',
                          style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                    ],
                  ),
                ),
                if (b != null) ...[StateChip(b.flag('expired') == true ? 'EXPIRED' : b.str('processingState')), const SizedBox(width: 10)],
                OutlinedButton.icon(
                  onPressed: _busy || !canChange ? null : () => _pickBuild(currentId: b?.id),
                  icon: Icon(b == null ? Icons.add : Icons.swap_horiz, size: 18),
                  label: Text(b == null ? 'Add build' : 'Change build'),
                ),
              ],
            ),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(hint, style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 12.5)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rejectedCard(PreflightData d, ActiveSubmission s) {
    final t = Theme.of(context);
    final k = Tokens.of(context);
    final rejected = s.rejectedItems.length;
    return Card(
      // A soft tint with a red edge, as in the design; a solid red fill shouts too loudly in dark mode.
      color: Color.alphaBlend(k.badSoft, k.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: k.bad.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.report_outlined, color: k.bad),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Rejected by App Review', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                StateChip(s.state),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${rejected == 0 ? 'The submission' : '$rejected item${rejected == 1 ? '' : 's'}'} came back with unresolved issues. '
              'Read App Review\'s message in the Resolution Center (Apple\'s API does not expose it), fix what they asked for, '
              'for example by changing the build above, then reply and resubmit.',
              style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(_ascVersionPage, mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open in App Store Connect'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _reply(d),
                  icon: const Icon(Icons.reply, size: 18),
                  label: const Text('Reply in review notes…'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Resubmit for review'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkRow(Check c, PreflightData d) {
    final k = Tokens.of(context);
    final (icon, color, soft) = switch (c.level) {
      CheckLevel.pass => (Icons.check_rounded, k.good, k.goodSoft),
      CheckLevel.warn => (Icons.priority_high_rounded, k.warn, k.warnSoft),
      CheckLevel.fail => (Icons.close_rounded, k.bad, k.badSoft),
    };
    final fixLabel = switch (c.fix) {
      CheckFix.version => 'New version…',
      CheckFix.build => 'Choose build…',
      CheckFix.compliance => 'Answer…',
      CheckFix.review => 'Edit…',
      CheckFix.release => 'Choose…',
      CheckFix.listing => 'Open Listing',
      CheckFix.reply => 'Reply…',
      null => null,
    };
    // Problems get a tinted row so they stand out from the passing checks, as in the design.
    return ListTile(
      tileColor: c.level == CheckLevel.pass ? null : soft,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: soft,
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Icon(
          icon,
          color: color,
          size: 17,
          semanticLabel: switch (c.level) {
            CheckLevel.pass => 'Passed',
            CheckLevel.warn => 'Warning',
            CheckLevel.fail => 'Failed',
          },
        ),
      ),
      title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: c.detail == null ? null : Text(c.detail!, style: TextStyle(color: c.level == CheckLevel.pass ? null : color)),
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
                final all = [...evaluatePreflight(d), ..._draftChecks()];
                final ready = canSubmit(all);
                // With App Review is a state, not a problem: say so once instead of listing it as a failed check.
                final withReview = all.any((c) => c.title == 'Already submitted');
                final checks = [
                  for (final c in all)
                    if (c.title != 'Already submitted') c,
                ];
                final blocked = checks.where((c) => c.level == CheckLevel.fail).length;
                final cancelable = d.submissions.where((s) => const {'WAITING_FOR_REVIEW', 'IN_REVIEW'}.contains(s.state)).toList();
                final rejection = _rejection(d);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (rejection != null) ...[_rejectedCard(d, rejection), const SizedBox(height: 16)],
                    if (cancelable.isNotEmpty) ...[
                      Card(
                        child: Column(
                          children: [
                            for (final s in cancelable)
                              ListTile(
                                leading: const Icon(Icons.hourglass_top),
                                title: const Text('In the review queue', style: TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Submission ${s.resource.id.length > 8 ? '${s.resource.id.substring(0, 8)}…' : s.resource.id} · ${prettyState(s.state)}'),
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
                    _buildCard(d),
                    const SizedBox(height: 16),
                    RowsCard(children: [for (final c in checks) _checkRow(c, d)]),
                    const SizedBox(height: 16),
                    _phasedReleaseCard(),
                    const SizedBox(height: 16),
                    if (withReview)
                      Text(
                        'With App Review. Nothing to do until Apple responds; cancel the submission above to change anything.',
                        style: t.textTheme.bodyMedium?.copyWith(color: Tokens.of(context).muted),
                      )
                    else
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: (!ready || _busy) ? null : _submit,
                            icon: _busy
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.send_outlined),
                            label: Text('${rejection != null ? 'Resubmit' : 'Submit'} ${_version.str('versionString')} for review'),
                          ),
                          const SizedBox(width: 14),
                          Flexible(
                            child: Text(
                              ready ? 'All required checks pass.' : '$blocked thing${blocked == 1 ? '' : 's'} to fix first.',
                              style: t.textTheme.bodyMedium?.copyWith(color: ready ? Tokens.of(context).good : t.colorScheme.error),
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
