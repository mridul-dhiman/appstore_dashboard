part of 'submit_tab.dart';

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
              decoration: const InputDecoration(labelText: 'Version number', helperText: 'Must be higher than the live version.'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _release,
              decoration: const InputDecoration(labelText: 'Release'),
              items: [
                for (final e in releaseTypes.entries.where((e) => e.key != 'SCHEDULED'))
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
                        : (builds.isEmpty ? 'No processed builds yet. Attach one later.' : 'Optional, can be attached later.'),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No build yet')),
                    for (final b in builds)
                      DropdownMenuItem(value: b.id, child: Text('Build ${b.str('version')} · uploaded ${fmtDate(b.date('uploadedDate'))}')),
                  ],
                  onChanged: (v) => setState(() => _buildId = v),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = _version.text.trim();
            if (RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(v)) {
              Navigator.pop(context, (version: v, release: _release, buildId: _buildId));
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
              ? const EmptyView('No processed, unexpired builds. Upload one from the Upload tab.')
              : ListView(
                  children: [
                    for (final b in builds)
                      ListTile(
                        title: Text('Build ${b.str('version')}'),
                        subtitle: Text('Uploaded ${fmtDateTime(b.date('uploadedDate'))} · expires ${fmtDate(b.date('expirationDate'))}'),
                        onTap: () => Navigator.pop(context, b.id),
                      ),
                  ],
                ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
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

  Widget _f(String key, String label, {bool obscure = false, int lines = 1}) => Padding(
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
                _f('demoAccountPassword', 'Demo account password', obscure: true),
              ],
              _f('notes', 'Notes for the reviewer (optional)', lines: 3),
              if (_problem != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final fields = {for (final k in reviewDetailFields) k: _c[k]!.text.trim()};
            if (fields['contactFirstName']!.isEmpty ||
                fields['contactLastName']!.isEmpty ||
                fields['contactPhone']!.isEmpty ||
                fields['contactEmail']!.isEmpty) {
              setState(() => _problem = 'Name, phone and email are required.');
              return;
            }
            if (_demo && (fields['demoAccountName']!.isEmpty || fields['demoAccountPassword']!.isEmpty)) {
              setState(() => _problem = 'Enter the demo account, or turn off the sign-in switch.');
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
                    RadioListTile<String>(contentPadding: EdgeInsets.zero, value: e.key, title: Text(e.value)),
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
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (_type == 'SCHEDULED' && _date == null) ? null : () => Navigator.pop(context, (type: _type, date: _date)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// The last gate. The version number has to be typed, so submitting is never an accident.
class _ConfirmSubmitDialog extends StatefulWidget {
  const _ConfirmSubmitDialog({required this.versionString, required this.buildNumber, required this.release});
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
            const Text('Apple starts reviewing straight away. You can cancel while it is still waiting, but not once review has begun.'),
            const SizedBox(height: 16),
            TextField(
              controller: _typed,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Type ${widget.versionString} to confirm'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
        FilledButton(onPressed: match ? () => Navigator.pop(context, true) : null, child: const Text('Submit for review')),
      ],
    );
  }
}
