import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/listing.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/submission.dart';
import '../widgets.dart';

String? _state(Resource v) =>
    v.str('appStoreState') ?? v.str('appVersionState');

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
  const SubmitTab({
    super.key,
    required this.client,
    required this.appId,
    required this.draft,
  });
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
      load: () => widget.client.page(
        '/v1/apps/${widget.appId}/appStoreVersions',
        {'limit': '20'},
      ),
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
        ? Resource(
            id: '',
            type: 'appStoreVersions',
            attributes: const {},
            relationships: const {},
          )
        : widget.versions.firstWhere(
            (v) => isVersionEditable(_state(v)),
            orElse: () => widget.versions.first,
          );
  }

  @override
  void dispose() {
    _pre.dispose();
    super.dispose();
  }

  Future<PreflightData> _loadPre() => loadPreflight(
    widget.client,
    widget.appId,
    _version,
    hasPriorVersion: widget.versions.length > 1,
  );

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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );

  /// The platform of the version being worked on (iOS, macOS, tvOS, visionOS). New versions and builds follow it.
  String get _platform => _version.str('platform') ?? (widget.versions.isEmpty ? null : widget.versions.first.str('platform')) ?? 'IOS';

  Future<List<Resource>> _validBuilds() async {
    final p = await widget.client.page('/v1/builds', {
      'filter[app]': widget.appId,
      'filter[preReleaseVersion.platform]': _platform,
      'sort': '-uploadedDate',
      'limit': '30',
      'include': 'preReleaseVersion',
    });
    return [
      for (final b in p.data)
        if (b.str('processingState') == 'VALID' && b.flag('expired') != true) b,
    ];
  }

  Future<void> _newVersion() async {
    final latest = widget.versions.isEmpty
        ? null
        : widget.versions.first.str('versionString');
    final result =
        await showDialog<({String version, String release, String? buildId})>(
          context: context,
          builder: (_) => _NewVersionDialog(
            suggestion: suggestNextVersion(latest),
            loadBuilds: _validBuilds,
          ),
        );
    if (result == null) return;
    final ok = await _run(() async {
      await _flow.createVersion(
        versionString: result.version,
        platform: _platform,
        releaseType: result.release,
        buildId: result.buildId,
      );
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, it does'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No, it does not'),
          ),
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
      await _run(
        () => _flow.saveReviewDetail(
          _version.id,
          existingId: d.reviewDetail?.id,
          fields: r.fields,
          demoAccountRequired: r.demo,
        ),
      );
    }
  }

  Future<void> _release() async {
    final r = await showDialog<({String type, DateTime? date})>(
      context: context,
      builder: (_) => _ReleaseDialog(current: _version.str('releaseType')),
    );
    if (r != null) {
      await _run(
        () => _flow.setReleaseType(_version.id, r.type, earliest: r.date),
      );
      widget.onVersionsChanged();
    }
  }

  void _fix(String key, PreflightData d) {
    switch (key) {
      case 'version':
        _newVersion();
      case 'build':
        _pickBuild();
      case 'compliance':
        if (d.build != null) _compliance(d.build!);
      case 'review':
        _reviewDetail(d);
      case 'release':
        _release();
      case 'listing':
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
      await _showError(
        'Not ready: ${checks.where((c) => c.level == CheckLevel.fail).map((c) => c.title).join('; ')}.',
      );
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
          icon: const Icon(
            Icons.check_circle,
            color: Color(0xFF1F8F45),
            size: 36,
          ),
          title: const Text('Submitted for review'),
          content: Text(
            'Version $versionString is now ${prettyState(out.state)}. You can cancel it from this tab while it is waiting.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
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

  List<Check> _draftChecks() => widget.draft.isEmpty
      ? const []
      : [
          Check(
            CheckLevel.fail,
            'Unsent listing changes',
            '${widget.draft.count} staged change(s) have not been applied. Apply the changelist on the Listing tab first, so what you submit is what you reviewed.',
            'listing',
          ),
        ];

  Future<void> _cancel(ActiveSubmission s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this submission?'),
        content: const Text(
          'The version is removed from the review queue and goes back to being editable. You can submit it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel submission'),
          ),
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
      'version' => 'New version…',
      'build' => 'Choose build…',
      'compliance' => 'Answer…',
      'review' => 'Edit…',
      'release' => 'Choose…',
      'listing' => 'Open Listing',
      _ => null,
    };
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: c.detail == null ? null : Text(c.detail!),
      trailing: c.level != CheckLevel.pass && c.fix != null && fixLabel != null
          ? OutlinedButton(
              onPressed: _busy ? null : () => _fix(c.fix!, d),
              child: Text(fixLabel),
            )
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
            FilledButton(
              onPressed: _newVersion,
              child: const Text('Create the first version'),
            ),
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
                decoration: const InputDecoration(
                  labelText: 'Version to submit',
                ),
                items: [
                  for (final v in widget.versions)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text(
                        '${v.str('versionString')} · ${prettyEnum(_state(v))}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (id) => setState(
                        () => _version = widget.versions.firstWhere(
                          (v) => v.id == id,
                        ),
                      ),
              ),
            ),
            StateChip(_state(_version)),
            OutlinedButton.icon(
              onPressed: _busy ? null : _newVersion,
              icon: const Icon(Icons.add),
              label: const Text('New version'),
            ),
            IconButton(
              tooltip: 'Re-check',
              onPressed: _pre.reload,
              icon: const Icon(Icons.refresh),
            ),
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
                final blocked = checks
                    .where((c) => c.level == CheckLevel.fail)
                    .length;
                final cancelable = d.submissions
                    .where(
                      (s) => const {
                        'WAITING_FOR_REVIEW',
                        'IN_REVIEW',
                        'UNRESOLVED_ISSUES',
                      }.contains(s.state),
                    )
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
                                title: const Text(
                                  'In the review queue',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  'Submission ${s.resource.id.substring(0, 8)}… · ${prettyState(s.state)}',
                                ),
                                trailing: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    StateChip(s.state),
                                    OutlinedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _cancel(s),
                                      child: const Text('Cancel submission'),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    RowsCard(
                      children: [for (final c in checks) _checkRow(c, d)],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: (!ready || _busy) ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(
                            'Submit ${_version.str('versionString')} for review',
                          ),
                        ),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            ready
                                ? 'All required checks pass.'
                                : '$blocked thing${blocked == 1 ? '' : 's'} to fix first.',
                            style: t.textTheme.bodyMedium?.copyWith(
                              color: ready
                                  ? const Color(0xFF1F8F45)
                                  : t.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'The checks cover what the API can see. Apple can still ask for more at review time (for example age rating answers or pricing), and Submit asks you to confirm first.',
                      style: t.textTheme.bodySmall?.copyWith(
                        color: t.colorScheme.onSurfaceVariant,
                      ),
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

class _NewVersionDialog extends StatefulWidget {
  const _NewVersionDialog({required this.suggestion, required this.loadBuilds});
  final String suggestion;
  final Future<List<Resource>> Function() loadBuilds;

  @override
  State<_NewVersionDialog> createState() => _NewVersionDialogState();
}

class _NewVersionDialogState extends State<_NewVersionDialog> {
  late final _version = TextEditingController(text: widget.suggestion);
  String _release = 'MANUAL';
  String? _buildId;
  late final Future<List<Resource>> _builds = widget.loadBuilds();

  @override
  void dispose() {
    _version.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New App Store version'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _version,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Version number',
                helperText: 'Must be higher than the live version.',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _release,
              decoration: const InputDecoration(labelText: 'Release'),
              items: [
                for (final e in releaseTypes.entries.where(
                  (e) => e.key != 'SCHEDULED',
                ))
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _release = v ?? _release),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<Resource>>(
              future: _builds,
              builder: (context, snap) {
                final builds = snap.data ?? const <Resource>[];
                return DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _buildId,
                  decoration: InputDecoration(
                    labelText: 'Build',
                    helperText: snap.connectionState != ConnectionState.done
                        ? 'Loading builds…'
                        : (builds.isEmpty
                              ? 'No processed builds yet. Attach one later.'
                              : 'Optional, can be attached later.'),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('No build yet'),
                    ),
                    for (final b in builds)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(
                          'Build ${b.str('version')} · uploaded ${fmtDate(b.date('uploadedDate'))}',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _buildId = v),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final v = _version.text.trim();
            if (RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(v)) {
              Navigator.pop(context, (
                version: v,
                release: _release,
                buildId: _buildId,
              ));
            }
          },
          child: const Text('Create version'),
        ),
      ],
    );
  }
}

class _BuildPickerDialog extends StatelessWidget {
  const _BuildPickerDialog({required this.loadBuilds});
  final Future<List<Resource>> Function() loadBuilds;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a build'),
      content: SizedBox(
        width: 460,
        height: 360,
        child: LoadView<List<Resource>>(
          load: loadBuilds,
          builder: (context, builds) => builds.isEmpty
              ? const EmptyView(
                  'No processed, unexpired builds. Upload one from the Upload tab.',
                )
              : ListView(
                  children: [
                    for (final b in builds)
                      ListTile(
                        title: Text('Build ${b.str('version')}'),
                        subtitle: Text(
                          'Uploaded ${fmtDateTime(b.date('uploadedDate'))} · expires ${fmtDate(b.date('expirationDate'))}',
                        ),
                        onTap: () => Navigator.pop(context, b.id),
                      ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _ReviewDetailDialog extends StatefulWidget {
  const _ReviewDetailDialog({required this.existing});
  final Resource? existing;

  @override
  State<_ReviewDetailDialog> createState() => _ReviewDetailDialogState();
}

class _ReviewDetailDialogState extends State<_ReviewDetailDialog> {
  final _c = <String, TextEditingController>{};
  late bool _demo = widget.existing?.flag('demoAccountRequired') ?? false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    for (final k in reviewDetailFields) {
      _c[k] = TextEditingController(text: widget.existing?.str(k) ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _f(String key, String label, {bool obscure = false, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          obscureText: obscure,
          minLines: lines,
          maxLines: obscure ? 1 : lines,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('App Review information'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _f('contactFirstName', 'Contact first name')),
                  const SizedBox(width: 12),
                  Expanded(child: _f('contactLastName', 'Contact last name')),
                ],
              ),
              _f('contactPhone', 'Contact phone (with country code)'),
              _f('contactEmail', 'Contact email'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _demo,
                onChanged: (v) => setState(() => _demo = v),
                title: const Text('Sign-in is required to review the app'),
              ),
              if (_demo) ...[
                _f('demoAccountName', 'Demo account user name'),
                _f(
                  'demoAccountPassword',
                  'Demo account password',
                  obscure: true,
                ),
              ],
              _f('notes', 'Notes for the reviewer (optional)', lines: 3),
              if (_problem != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _problem!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final fields = {
              for (final k in reviewDetailFields) k: _c[k]!.text.trim(),
            };
            if (fields['contactFirstName']!.isEmpty ||
                fields['contactLastName']!.isEmpty ||
                fields['contactPhone']!.isEmpty ||
                fields['contactEmail']!.isEmpty) {
              setState(() => _problem = 'Name, phone and email are required.');
              return;
            }
            if (_demo &&
                (fields['demoAccountName']!.isEmpty ||
                    fields['demoAccountPassword']!.isEmpty)) {
              setState(
                () => _problem =
                    'Enter the demo account, or turn off the sign-in switch.',
              );
              return;
            }
            if (!_demo) {
              fields['demoAccountName'] = '';
              fields['demoAccountPassword'] = '';
            }
            Navigator.pop(context, (fields: fields, demo: _demo));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReleaseDialog extends StatefulWidget {
  const _ReleaseDialog({required this.current});
  final String? current;

  @override
  State<_ReleaseDialog> createState() => _ReleaseDialogState();
}

class _ReleaseDialogState extends State<_ReleaseDialog> {
  late String _type = widget.current ?? 'MANUAL';
  DateTime? _date;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('How should it be released?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (v) => setState(() => _type = v ?? _type),
              child: Column(
                children: [
                  for (final e in releaseTypes.entries)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: e.key,
                      title: Text(e.value),
                    ),
                ],
              ),
            ),
            if (_type == 'SCHEDULED')
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(_date == null ? 'Pick a date' : fmtDate(_date)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 7)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => _date = d);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_type == 'SCHEDULED' && _date == null)
              ? null
              : () => Navigator.pop(context, (type: _type, date: _date)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The last gate. The version number has to be typed, so submitting is never an accident.
class _ConfirmSubmitDialog extends StatefulWidget {
  const _ConfirmSubmitDialog({
    required this.versionString,
    required this.buildNumber,
    required this.release,
  });
  final String versionString;
  final String buildNumber;
  final String release;

  @override
  State<_ConfirmSubmitDialog> createState() => _ConfirmSubmitDialogState();
}

class _ConfirmSubmitDialogState extends State<_ConfirmSubmitDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = _typed.text.trim() == widget.versionString;
    return AlertDialog(
      title: Text('Submit ${widget.versionString} to App Review?'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Build ${widget.buildNumber} · ${widget.release}'),
            const SizedBox(height: 10),
            const Text(
              'Apple starts reviewing straight away. You can cancel while it is still waiting, but not once review has begun.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _typed,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Type ${widget.versionString} to confirm',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not yet'),
        ),
        FilledButton(
          onPressed: match ? () => Navigator.pop(context, true) : null,
          child: const Text('Submit for review'),
        ),
      ],
    );
  }
}
