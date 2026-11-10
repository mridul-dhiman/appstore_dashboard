import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../api/team.dart' show looksLikeEmail;
import '../../api/testflight.dart';
import 'package:flutter/services.dart';

import '../qr_view.dart';
import '../theme.dart';
import '../widgets.dart';

class _GroupsData {
  _GroupsData(this.groups, this.builds);
  final List<Resource> groups;
  final List<AppBuild> builds;
}

/// TestFlight groups of one app: internal and external, their testers, builds and public link.
class GroupsTab extends StatefulWidget {
  const GroupsTab({super.key, required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  final _reload = ReloadController();
  String? _selected;

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await showDialog<String>(context: context, builder: (_) => _NewGroupDialog(client: widget.client, appId: widget.appId));
    if (created == null) return;
    setState(() => _selected = created);
    _reload.reload();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<_GroupsData>(
      controller: _reload,
      load: () async {
        final r = await Future.wait<Object>([loadGroups(widget.client, widget.appId), loadAppBuilds(widget.client, widget.appId)]);
        return _GroupsData(r[0] as List<Resource>, r[1] as List<AppBuild>);
      },
      builder: (context, d) {
        final selected = d.groups.where((g) => g.id == _selected).firstOrNull ?? d.groups.firstOrNull;
        final internal = d.groups.where((g) => g.flag('isInternalGroup') == true).toList();
        final external = d.groups.where((g) => g.flag('isInternalGroup') != true).toList();
        final k = Tokens.of(context);
        Widget tile(Resource g) {
          final on = g.id == selected?.id;
          final isInternal = g.flag('isInternalGroup') == true;
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: on ? k.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selected = g.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [
                    Icon(isInternal ? Icons.badge_outlined : Icons.public, size: 18, color: on ? k.accentInk : k.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(g.str('name') ?? 'Group', overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: on ? k.accentInk : null))),
                  ]),
                ),
              ),
            ),
          );
        }

        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 8, 0, 40),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 2, 8),
                      child: Row(children: [
                        const Expanded(child: Text('Groups', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                        IconButton(tooltip: 'Refresh', visualDensity: VisualDensity.compact, onPressed: _reload.reload, icon: const Icon(Icons.refresh, size: 18)),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 11)),
                          onPressed: _create,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('New'),
                        ),
                      ]),
                    ),
                    const SectionLabel('Internal', padding: EdgeInsets.fromLTRB(8, 8, 8, 6)),
                    if (internal.isEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text('None', style: TextStyle(color: k.muted))),
                    for (final g in internal) tile(g),
                    const SectionLabel('External', padding: EdgeInsets.fromLTRB(8, 14, 8, 6)),
                    if (external.isEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Text('None', style: TextStyle(color: k.muted))),
                    for (final g in external) tile(g),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(
            child: selected == null
                ? const EmptyView('No TestFlight groups yet. Create one with New.')
                : _GroupDetail(
                    key: ValueKey(selected.id),
                    client: widget.client,
                    group: selected,
                    builds: d.builds,
                    onChanged: _reload.reload,
                    onDeleted: () {
                      setState(() => _selected = null);
                      _reload.reload();
                    },
                  ),
          ),
        ]);
      },
    );
  }
}

class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog({required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final _name = TextEditingController();
  bool _internal = false;
  bool _allBuilds = true;
  bool _feedback = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final s = GroupSettings(name: _name.text, feedback: _feedback);
    final problems = groupProblems(s);
    if (problems.isNotEmpty) return setState(() => _error = problems.join('\n'));
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final g = await createGroup(widget.client, groupCreateBody(widget.appId, s, internal: _internal, allBuilds: _allBuilds));
      if (mounted) Navigator.pop(context, g.id);
    } on AscException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New TestFlight group'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Group name')),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('External'), icon: Icon(Icons.public)),
              ButtonSegment(value: true, label: Text('Internal'), icon: Icon(Icons.badge_outlined)),
            ],
            selected: {_internal},
            onSelectionChanged: (v) => setState(() => _internal = v.first),
          ),
          const SizedBox(height: 6),
          Text(
            _internal
                ? 'Internal: up to 100 people who are users on this App Store Connect team. Builds need no review.'
                : 'External: up to 10,000 testers, invited by email or a public link. The first build of each version needs Beta App Review.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (_internal)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Give access to all builds'),
              subtitle: const Text('Every new build is available automatically.'),
              value: _allBuilds,
              onChanged: (v) => setState(() => _allBuilds = v),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tester feedback'),
            value: _feedback,
            onChanged: (v) => setState(() => _feedback = v),
          ),
          if (_error != null) SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _create, child: const Text('Create group')),
      ],
    );
  }
}

class _GroupDetail extends StatefulWidget {
  const _GroupDetail({super.key, required this.client, required this.group, required this.builds, required this.onChanged, required this.onDeleted});
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
    final next = GroupSettings(name: _name.text, feedback: _draft.feedback, publicLink: _draft.publicLink, limit: int.tryParse(_limit.text.trim()));
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
      _toast(existing ? '${r.email} was already a tester and is now in this group.' : 'Added ${r.email}. TestFlight emails them an invitation.');
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
    final picked = await showDialog<List<Resource>>(context: context, builder: (_) => _PickUsersDialog(users: users, alreadyIn: taken));
    if (picked == null || picked.isEmpty) return;
    final failed = <String>[];
    for (final u in picked) {
      final email = u.str('username') ?? u.str('email') ?? '';
      try {
        await addTester(widget.client, widget.group.id, email: email, firstName: u.str('firstName') ?? '', lastName: u.str('lastName') ?? '');
      } on AscException catch (e) {
        failed.add('$email: ${e.message}');
      }
    }
    _toast(failed.isEmpty ? 'Added ${picked.length} ${picked.length == 1 ? 'person' : 'people'} to the group.' : 'Could not add:\n${failed.join('\n')}');
    _members.reload();
  }

  List<Resource> _currentTesters = const [];

  Future<void> _removeTester(Resource t) async {
    await _run(() => removeTestersFromGroup(widget.client, widget.group.id, [t.id]), 'Removed from the group.');
    _members.reload();
  }

  Future<void> _toggleBuild(AppBuild b, bool inGroup) async {
    await _run(
      () => inGroup ? removeBuildsFromGroup(widget.client, widget.group.id, [b.id]) : addBuildsToGroup(widget.client, widget.group.id, [b.id]),
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
    final small = OutlinedButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 12), textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600));
    Widget head(String title, {String? subtitle, Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(color: k.muted, fontSize: 13))),
              ]),
            ),
            ?trailing,
          ]),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(28, 8, 40, 40), children: [
      Row(children: [
        Flexible(child: Text(g.str('name') ?? 'Group', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4))),
        const SizedBox(width: 12),
        StateChip(_internal ? 'READY' : 'PENDING', label: _internal ? 'Internal' : 'External'),
        const Spacer(),
        OutlinedButton(
          style: small.copyWith(foregroundColor: WidgetStatePropertyAll(t.colorScheme.error)),
          onPressed: _delete,
          child: const Text('Delete group'),
        ),
      ]),
      const SizedBox(height: 18),
      Card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          head('Settings'),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: SizedBox(width: 360, child: TextField(controller: _name, decoration: const InputDecoration(labelText: 'Group name'))),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: const Text('Tester feedback', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Screenshots and crash reports from TestFlight.'),
            value: _draft.feedback,
            onChanged: (v) => setState(() => _draft = GroupSettings(name: _draft.name, feedback: v, publicLink: _draft.publicLink, limit: _draft.limit)),
          ),
          if (!_internal) ...[
            const Divider(),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('Public link', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Anyone with the link can join, up to the limit below.'),
              value: _draft.publicLink,
              onChanged: (v) => setState(() => _draft = GroupSettings(name: _draft.name, feedback: _draft.feedback, publicLink: v, limit: _draft.limit)),
            ),
            if (_draft.publicLink)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 260, child: TextField(controller: _limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tester limit', helperText: 'Empty = no limit (max 10000)'))),
                  if (link != null && link.isNotEmpty) _PublicLink(link: link),
                ]),
              ),
          ],
          if (_internal) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(children: [
                Expanded(child: Text(_allBuilds ? 'Every new build is available to this group automatically.' : 'Builds are chosen below.', style: TextStyle(color: k.muted))),
                if (_allBuilds) const StateChip('READY', label: 'All builds'),
              ]),
            ),
          ],
          const Divider(),
          Padding(padding: const EdgeInsets.all(14), child: Align(alignment: Alignment.centerRight, child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save settings')))),
        ]),
      ),
      const SizedBox(height: 18),
      LoadView<_Members>(
        controller: _members,
        load: () async {
          final r = await Future.wait<Object>([loadGroupTesters(widget.client, g.id), loadGroupBuildIds(widget.client, g.id)]);
          _currentTesters = r[0] as List<Resource>;
          return _Members(r[0] as List<Resource>, r[1] as Set<String>);
        },
        builder: (context, m) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: Column(children: [
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
                Padding(padding: const EdgeInsets.all(28), child: Text('No testers in this group yet.', style: TextStyle(color: k.muted))),
              ],
              for (final x in m.testers) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(children: [
                    Avatar(_testerName(x)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_testerName(x), style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(x.str('email') ?? '', style: TextStyle(color: k.muted, fontSize: 13)),
                      ]),
                    ),
                    if (x.str('state') != null) ...[StateChip(x.str('state'), label: prettyEnum(x.str('state')!)), const SizedBox(width: 12)],
                    OutlinedButton(style: small, onPressed: () => _removeTester(x), child: const Text('Remove')),
                  ]),
                ),
              ],
            ]),
          ),
          if (!(_internal && _allBuilds)) ...[
            const SizedBox(height: 18),
            Card(
              child: Column(children: [
                head('Builds', subtitle: _internal ? null : 'External groups need Beta App Review for each version.'),
                if (widget.builds.isEmpty) ...[
                  const Divider(),
                  Padding(padding: const EdgeInsets.all(28), child: Text('No builds uploaded yet.', style: TextStyle(color: k.muted))),
                ],
                for (final b in widget.builds) ...[
                  const Divider(),
                  Builder(builder: (context) {
                    final inGroup = m.buildIds.contains(b.id);
                    final needsReview = !_internal && b.externalState == 'READY_FOR_BETA_SUBMISSION';
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                      child: Row(children: [
                        Icon(Icons.flight_takeoff, size: 20, color: k.muted),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                            if (!_internal && b.externalState != null) Text(prettyEnum(b.externalState!), style: TextStyle(color: k.muted, fontSize: 13)),
                          ]),
                        ),
                        if (needsReview) ...[OutlinedButton(style: small, onPressed: () => _submitReview(b), child: const Text('Submit for beta review')), const SizedBox(width: 8)],
                        if (inGroup)
                          OutlinedButton(style: small, onPressed: () => _toggleBuild(b, true), child: const Text('Remove'))
                        else
                          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 14), textStyle: const TextStyle(fontSize: 12.5)), onPressed: b.usable ? () => _toggleBuild(b, false) : null, child: const Text('Add')),
                      ]),
                    );
                  }),
                ],
              ]),
            ),
          ],
        ]),
      ),
    ]);
  }

  static String _testerName(Resource t) {
    final n = '${t.str('firstName') ?? ''} ${t.str('lastName') ?? ''}'.trim();
    return n.isEmpty ? (t.str('email') ?? 'Tester') : n;
  }
}

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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _email, autofocus: true, decoration: const InputDecoration(labelText: 'Email address')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _first, decoration: const InputDecoration(labelText: 'First name (optional)'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _last, decoration: const InputDecoration(labelText: 'Last name (optional)'))),
          ]),
          const SizedBox(height: 10),
          Text('TestFlight emails an invitation to this address.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
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
    final shown = [for (final u in widget.users) if (q.isEmpty || _name(u).toLowerCase().contains(q) || _email(u).contains(q)) u];
    final selectable = [for (final u in shown) if (!widget.alreadyIn.contains(_email(u))) u];
    return AlertDialog(
      title: const Text('Add team members'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(children: [
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
                : ListView(children: [
                    for (final u in shown)
                      CheckboxListTile(
                        dense: true,
                        value: widget.alreadyIn.contains(_email(u)) || _picked.contains(u.id),
                        title: Text(_name(u)),
                        subtitle: Text([_email(u), ...u.list('roles').map(prettyEnum)].join('  ·  ')),
                        secondary: widget.alreadyIn.contains(_email(u)) ? const Text('In group') : null,
                        onChanged: widget.alreadyIn.contains(_email(u)) ? null : (v) => setState(() => v == true ? _picked.add(u.id) : _picked.remove(u.id)),
                      ),
                  ]),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, [for (final u in widget.users) if (_picked.contains(u.id)) u]),
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
        decoration: BoxDecoration(color: k.inset, borderRadius: BorderRadius.circular(12), border: Border.all(color: k.line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          if (isTestFlightLink(link)) ...[QrView(data: link), const SizedBox(width: 20)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Public link', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: k.muted)),
              const SizedBox(height: 4),
              SelectableText(link, style: TextStyle(color: k.accentInk, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy Link'),
              ),
              if (isTestFlightLink(link)) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Scan with a phone camera to open TestFlight.', style: TextStyle(color: k.muted, fontSize: 12.5))),
            ]),
          ),
        ]),
      ),
    );
  }
}
