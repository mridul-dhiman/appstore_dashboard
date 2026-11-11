part of 'groups_tab.dart';

class _GroupDetail extends StatefulWidget {
  const _GroupDetail({
    super.key,
    required this.client,
    required this.group,
    required this.builds,
    required this.onChanged,
    required this.onDeleted,
  });
  final AscClient client;
  final Resource group;
  final List<AppBuild> builds;
  final VoidCallback onChanged;
  final VoidCallback onDeleted;

  @override
  State<_GroupDetail> createState() => _GroupDetailState();
}

class _Members {
  _Members(this.testers, this.buildIds);
  final List<Resource> testers;
  final Set<String> buildIds;
}

class _GroupDetailState extends State<_GroupDetail> {
  final _members = ReloadController();
  late final _name = TextEditingController(text: widget.group.str('name'));
  late final GroupSettings _before = settingsOf(widget.group);
  late GroupSettings _draft = _before;
  late final _limit = TextEditingController(text: _before.limit?.toString() ?? '');
  bool _saving = false;

  bool get _internal => widget.group.flag('isInternalGroup') == true;
  bool get _allBuilds => widget.group.flag('hasAccessToAllBuilds') == true;

  @override
  void dispose() {
    _members.dispose();
    _name.dispose();
    _limit.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (done.isNotEmpty) _toast(done);
    } on AscException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _save() async {
    final next = GroupSettings(
      name: _name.text,
      feedback: _draft.feedback,
      publicLink: _draft.publicLink,
      limit: int.tryParse(_limit.text.trim()),
    );
    final problems = groupProblems(next);
    if (problems.isNotEmpty) return _toast(problems.join(' '));
    final body = groupUpdateBody(widget.group.id, _before, next, internal: _internal);
    if (!groupChanged(body)) return;
    setState(() => _saving = true);
    await _run(() => updateGroup(widget.client, widget.group.id, body), 'Group saved.');
    if (!mounted) return;
    setState(() => _saving = false);
    widget.onChanged();
  }

  Future<void> _delete() async {
    final name = widget.group.str('name') ?? 'this group';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $name?'),
        content: const Text('Testers in this group lose access to its builds. The testers themselves stay in TestFlight.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete group'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => deleteGroup(widget.client, widget.group.id), 'Group deleted.');
    if (mounted) widget.onDeleted();
  }

  Future<void> _addTester() async {
    if (_internal) return _addTeamMembers();
    final r = await showDialog<_NewTester>(context: context, builder: (_) => const _AddTesterDialog());
    if (r == null) return;
    await _run(() async {
      final existing = await addTester(widget.client, widget.group.id, email: r.email, firstName: r.first, lastName: r.last);
      _toast(
        existing ? '${r.email} was already a tester and is now in this group.' : 'Added ${r.email}. TestFlight emails them an invitation.',
      );
    }, '');
    _members.reload();
  }

  /// Internal testers are people already on the team: show them all and let the person tick who to add.
  Future<void> _addTeamMembers() async {
    final List<Resource> users;
    try {
      users = (await widget.client.all('/v1/users', {'limit': '200'})).data;
    } on AscException catch (e) {
      return _toast(e.message);
    }
    if (!mounted) return;
    final taken = {for (final t in _currentTesters) (t.str('email') ?? '').toLowerCase()};
    final picked = await showDialog<List<Resource>>(
      context: context,
      builder: (_) => _PickUsersDialog(users: users, alreadyIn: taken),
    );
    if (picked == null || picked.isEmpty) return;
    final failed = <String>[];
    for (final u in picked) {
      final email = u.str('username') ?? u.str('email') ?? '';
      try {
        await addTester(
          widget.client,
          widget.group.id,
          email: email,
          firstName: u.str('firstName') ?? '',
          lastName: u.str('lastName') ?? '',
        );
      } on AscException catch (e) {
        failed.add('$email: ${e.message}');
      }
    }
    _toast(
      failed.isEmpty
          ? 'Added ${picked.length} ${picked.length == 1 ? 'person' : 'people'} to the group.'
          : 'Could not add:\n${failed.join('\n')}',
    );
    _members.reload();
  }

  List<Resource> _currentTesters = const [];

  Future<void> _removeTester(Resource t) async {
    await _run(() => removeTestersFromGroup(widget.client, widget.group.id, [t.id]), 'Removed from the group.');
    _members.reload();
  }

  Future<void> _toggleBuild(AppBuild b, bool inGroup) async {
    await _run(
      () => inGroup
          ? removeBuildsFromGroup(widget.client, widget.group.id, [b.id])
          : addBuildsToGroup(widget.client, widget.group.id, [b.id]),
      inGroup ? 'Build removed from the group.' : 'Build added to the group.',
    );
    _members.reload();
  }

  Future<void> _submitReview(AppBuild b) async {
    await _run(() => submitForBetaReview(widget.client, b.id), 'Submitted ${b.label} for Beta App Review.');
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final g = widget.group;
    final link = g.str('publicLink');
    final k = Tokens.of(context);
    final small = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 30),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
    );
    Widget head(String title, {String? subtitle, Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle, style: TextStyle(color: k.muted, fontSize: 13)),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 8, 40, 40),
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                g.str('name') ?? 'Group',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4),
              ),
            ),
            const SizedBox(width: 12),
            StateChip(_internal ? 'READY' : 'PENDING', label: _internal ? 'Internal' : 'External'),
            const Spacer(),
            OutlinedButton(
              style: small.copyWith(foregroundColor: WidgetStatePropertyAll(t.colorScheme.error)),
              onPressed: _delete,
              child: const Text('Delete group'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              head('Settings'),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Group name'),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                title: const Text('Tester feedback', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Screenshots and crash reports from TestFlight.'),
                value: _draft.feedback,
                onChanged: (v) => setState(
                  () => _draft = GroupSettings(name: _draft.name, feedback: v, publicLink: _draft.publicLink, limit: _draft.limit),
                ),
              ),
              if (!_internal) ...[
                const Divider(),
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  title: const Text('Public link', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Anyone with the link can join, up to the limit below.'),
                  value: _draft.publicLink,
                  onChanged: (v) => setState(
                    () => _draft = GroupSettings(name: _draft.name, feedback: _draft.feedback, publicLink: v, limit: _draft.limit),
                  ),
                ),
                if (_draft.publicLink)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _limit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Tester limit', helperText: 'Empty = no limit (max 10000)'),
                          ),
                        ),
                        if (link != null && link.isNotEmpty) _PublicLink(link: link),
                      ],
                    ),
                  ),
              ],
              if (_internal) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _allBuilds ? 'Every new build is available to this group automatically.' : 'Builds are chosen below.',
                          style: TextStyle(color: k.muted),
                        ),
                      ),
                      if (_allBuilds) const StateChip('READY', label: 'All builds'),
                    ],
                  ),
                ),
              ],
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save settings')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LoadView<_Members>(
          controller: _members,
          load: () async {
            final r = await Future.wait<Object>([loadGroupTesters(widget.client, g.id), loadGroupBuildIds(widget.client, g.id)]);
            _currentTesters = r[0] as List<Resource>;
            return _Members(r[0] as List<Resource>, r[1] as Set<String>);
          },
          builder: (context, m) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Column(
                  children: [
                    head(
                      'Testers · ${m.testers.length}',
                      trailing: FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 12)),
                        onPressed: _addTester,
                        icon: const Icon(Icons.person_add_alt_1_outlined, size: 16),
                        label: Text(_internal ? 'Add team members' : 'Add tester'),
                      ),
                    ),
                    if (m.testers.isEmpty) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text('No testers in this group yet.', style: TextStyle(color: k.muted)),
                      ),
                    ],
                    for (final x in m.testers) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        child: Row(
                          children: [
                            Avatar(_testerName(x)),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_testerName(x), style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text(x.str('email') ?? '', style: TextStyle(color: k.muted, fontSize: 13)),
                                ],
                              ),
                            ),
                            if (x.str('state') != null) ...[
                              StateChip(x.str('state'), label: prettyEnum(x.str('state')!)),
                              const SizedBox(width: 12),
                            ],
                            OutlinedButton(style: small, onPressed: () => _removeTester(x), child: const Text('Remove')),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!(_internal && _allBuilds)) ...[
                const SizedBox(height: 18),
                Card(
                  child: Column(
                    children: [
                      head('Builds', subtitle: _internal ? null : 'External groups need Beta App Review for each version.'),
                      if (widget.builds.isEmpty) ...[
                        const Divider(),
                        Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text('No builds uploaded yet.', style: TextStyle(color: k.muted)),
                        ),
                      ],
                      for (final b in widget.builds) ...[
                        const Divider(),
                        Builder(
                          builder: (context) {
                            final inGroup = m.buildIds.contains(b.id);
                            final needsReview = !_internal && b.externalState == 'READY_FOR_BETA_SUBMISSION';
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                              child: Row(
                                children: [
                                  Icon(Icons.flight_takeoff, size: 20, color: k.muted),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        if (!_internal && b.externalState != null)
                                          Text(prettyEnum(b.externalState!), style: TextStyle(color: k.muted, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                                  if (needsReview) ...[
                                    OutlinedButton(
                                      style: small,
                                      onPressed: () => _submitReview(b),
                                      child: const Text('Submit for beta review'),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  if (inGroup)
                                    OutlinedButton(style: small, onPressed: () => _toggleBuild(b, true), child: const Text('Remove'))
                                  else
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 30),
                                        padding: const EdgeInsets.symmetric(horizontal: 14),
                                        textStyle: const TextStyle(fontSize: 12.5),
                                      ),
                                      onPressed: b.usable ? () => _toggleBuild(b, false) : null,
                                      child: const Text('Add'),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _testerName(Resource t) {
    final n = '${t.str('firstName') ?? ''} ${t.str('lastName') ?? ''}'.trim();
    return n.isEmpty ? (t.str('email') ?? 'Tester') : n;
  }
}
