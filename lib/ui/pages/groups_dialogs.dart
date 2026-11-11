part of 'groups_tab.dart';

class _NewTester {
  _NewTester(this.email, this.first, this.last);
  final String email, first, last;
}

class _AddTesterDialog extends StatefulWidget {
  const _AddTesterDialog();

  @override
  State<_AddTesterDialog> createState() => _AddTesterDialogState();
}

class _AddTesterDialogState extends State<_AddTesterDialog> {
  final _email = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a tester'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _email,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Email address'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _first,
                    decoration: const InputDecoration(labelText: 'First name (optional)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _last,
                    decoration: const InputDecoration(labelText: 'Last name (optional)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'TestFlight emails an invitation to this address.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!looksLikeEmail(_email.text)) return setState(() => _error = 'That does not look like an email address.');
            Navigator.pop(context, _NewTester(_email.text.trim(), _first.text, _last.text));
          },
          child: const Text('Add tester'),
        ),
      ],
    );
  }
}

/// All users of the team with a checkbox each; people already in the group are shown ticked and locked.
class _PickUsersDialog extends StatefulWidget {
  const _PickUsersDialog({required this.users, required this.alreadyIn});
  final List<Resource> users;
  final Set<String> alreadyIn;

  @override
  State<_PickUsersDialog> createState() => _PickUsersDialogState();
}

class _PickUsersDialogState extends State<_PickUsersDialog> {
  final _picked = <String>{};
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  String _email(Resource u) => (u.str('username') ?? u.str('email') ?? '').toLowerCase();

  String _name(Resource u) {
    final n = '${u.str('firstName') ?? ''} ${u.str('lastName') ?? ''}'.trim();
    return n.isEmpty ? _email(u) : n;
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.text.trim().toLowerCase();
    final shown = [
      for (final u in widget.users)
        if (q.isEmpty || _name(u).toLowerCase().contains(q) || _email(u).contains(q)) u,
    ];
    final selectable = [
      for (final u in shown)
        if (!widget.alreadyIn.contains(_email(u))) u,
    ];
    return AlertDialog(
      title: const Text('Add team members'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _filter,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search the team'),
              onChanged: (_) => setState(() {}),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: selectable.isEmpty
                    ? null
                    : () => setState(() {
                        final ids = selectable.map((u) => u.id);
                        _picked.containsAll(ids) ? _picked.removeAll(ids) : _picked.addAll(ids);
                      }),
                child: Text(selectable.isNotEmpty && _picked.containsAll(selectable.map((u) => u.id)) ? 'Clear all' : 'Select all'),
              ),
            ),
            Expanded(
              child: shown.isEmpty
                  ? const Center(child: Text('Nobody matches.'))
                  : ListView(
                      children: [
                        for (final u in shown)
                          CheckboxListTile(
                            dense: true,
                            value: widget.alreadyIn.contains(_email(u)) || _picked.contains(u.id),
                            title: Text(_name(u)),
                            subtitle: Text([_email(u), ...u.list('roles').map(prettyEnum)].join('  ·  ')),
                            secondary: widget.alreadyIn.contains(_email(u)) ? const Text('In group') : null,
                            onChanged: widget.alreadyIn.contains(_email(u))
                                ? null
                                : (v) => setState(() => v == true ? _picked.add(u.id) : _picked.remove(u.id)),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final u in widget.users)
                    if (_picked.contains(u.id)) u,
                ]),
          child: Text(_picked.isEmpty ? 'Add' : 'Add ${_picked.length}'),
        ),
      ],
    );
  }
}

/// The group's public join link: the link itself, a copy button, and a QR code to scan from a phone.
class _PublicLink extends StatelessWidget {
  const _PublicLink({required this.link});
  final String link;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: k.inset,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: k.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isTestFlightLink(link)) ...[QrView(data: link), const SizedBox(width: 20)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Public link',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: k.muted),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    link,
                    style: TextStyle(color: k.accentInk, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: link));
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Link'),
                  ),
                  if (isTestFlightLink(link))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Scan with a phone camera to open TestFlight.', style: TextStyle(color: k.muted, fontSize: 12.5)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
