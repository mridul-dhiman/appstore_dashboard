import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../api/team.dart';
import '../theme.dart';
import '../widgets.dart';

/// Slides a panel in from the right edge. Resolves with whatever the panel pops with.
Future<T?> showDrawer<T>(BuildContext context, WidgetBuilder builder) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x6114171F),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) =>
        Align(alignment: Alignment.centerRight, child: builder(ctx)),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class TeamPage extends StatefulWidget {
  const TeamPage({super.key, required this.client});
  final AscClient client;

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  final _reload = ReloadController();
  List<Resource> _apps = const [];

  // Apple's lists can lag a few seconds behind a change. What was just done is kept here and laid over whatever Apple
  // returns, so the page shows the new state straight away; entries drop out once Apple's own list agrees.
  final _hidden = <String>{};
  final _addedInvites = <Resource>[];
  final _edited = <String, Resource>{};

  /// Reload now, and once more shortly after, when Apple has usually caught up.
  void _refreshSoon() {
    _reload.reload();
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted) _reload.reload();
    });
  }

  static bool _sameRoles(Resource a, Resource b) {
    final x = [...a.list('roles')]..sort(), y = [...b.list('roles')]..sort();
    return x.join(',') == y.join(',');
  }

  List<Resource> _users(TeamData d) {
    return [
      for (final u in d.users.data)
        if (!_hidden.contains(u.id))
          if (_edited[u.id] case final e? when !_sameRoles(u, e)) e else u,
    ];
  }

  List<Resource> _invites(TeamData d) {
    final server = d.invites?.data ?? const <Resource>[];
    final have = {
      for (final i in server) i.id,
      for (final i in server) (i.str('email') ?? '').toLowerCase(),
    };
    return [
      ...server.where((i) => !_hidden.contains(i.id)),
      for (final i in _addedInvites)
        if (!_hidden.contains(i.id) &&
            !have.contains(i.id) &&
            !have.contains((i.str('email') ?? '').toLowerCase()))
          i,
    ];
  }

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _invite() async {
    final sent = await showDrawer<_Done>(
      context,
      (_) => _AccessDialog(client: widget.client, apps: _apps),
    );
    if (sent == null) return;
    _addedInvites.add(sent.resource);
    _toast(
      'Invitation sent to ${sent.name}. They get an email from Apple and appear here as Invited until they accept.',
    );
    _refreshSoon();
  }

  Future<void> _edit(Resource user) async {
    final done = await showDrawer<_Done>(
      context,
      (_) => _AccessDialog(client: widget.client, apps: _apps, user: user),
    );
    if (done == null) return;
    _edited[user.id] = done.resource;
    _toast('Updated access for ${done.name}.');
    _refreshSoon();
  }

  Future<void> _remove(Resource user) async {
    final who = _display(user);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $who?'),
        content: Text(
          '$who loses access to App Store Connect for this team straight away. They can be invited again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await removeUser(widget.client, user.id);
      _hidden.add(user.id);
      _toast('Removed $who.');
      _refreshSoon();
    } on AscException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _revoke(Resource invite) async {
    try {
      await revokeInvitation(widget.client, invite.id);
      _hidden.add(invite.id);
      _toast('Invitation to ${invite.str('email') ?? 'that address'} revoked.');
      _refreshSoon();
    } on AscException catch (e) {
      _toast(e.message);
    }
  }

  static String _display(Resource u) {
    final name = '${u.str('firstName') ?? ''} ${u.str('lastName') ?? ''}'
        .trim();
    return name.isEmpty ? (u.str('email') ?? u.str('username') ?? '—') : name;
  }

  String _access(Resource u) {
    if (u.flag('allAppsVisible') == true) return 'All apps';
    final n = u.relIds('visibleApps').length;
    return n == 0 ? '' : '$n app${n == 1 ? '' : 's'}';
  }

  Widget _row(Resource u, {bool invited = false}) {
    final name = _display(u);
    final isHolder = u.list('roles').contains('ACCOUNT_HOLDER');
    final access = _access(u);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final roles = u.list('roles');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      child: Row(
        children: [
          Avatar(
            name,
            color: invited
                ? (const Color(0xFFFFF1D6), const Color(0xFF7A4E00))
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  u.str('username') ?? u.str('email') ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (invited) ...[
            const StateChip('PENDING', label: 'Invited'),
            const SizedBox(width: 16),
          ],
          SizedBox(
            width: 84,
            child: Text(access, style: TextStyle(color: muted, fontSize: 13)),
          ),
          SizedBox(
            width: 230,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                for (final r in roles) StateChip(null, label: prettyEnum(r)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (invited)
                  OutlinedButton(
                    style: _small,
                    onPressed: () => _revoke(u),
                    child: const Text('Revoke'),
                  )
                else if (!isHolder) ...[
                  OutlinedButton(
                    style: _small,
                    onPressed: () => _edit(u),
                    child: const Text('Edit'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: _small.copyWith(
                      foregroundColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onPressed: () => _remove(u),
                    child: const Text('Remove'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static final _small = OutlinedButton.styleFrom(
    minimumSize: const Size(0, 30),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        PageHeader(
          title: 'Users and Access',
          subtitle: 'People on this team and pending invitations',
          reload: _reload,
          actions: [
            FilledButton.icon(
              onPressed: _invite,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Invite user'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        Expanded(
          child: LoadView<TeamData>(
            controller: _reload,
            load: () async {
              final d = await loadTeam(widget.client);
              _apps = d.apps;
              return d;
            },
            builder: (context, d) => ListView(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
              children: [
                RowsCard(children: [for (final u in _users(d)) _row(u)]),
                if (_invites(d).isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionLabel('Pending invitations'),
                  RowsCard(
                    children: [
                      for (final u in _invites(d)) _row(u, invited: true),
                    ],
                  ),
                ],
                if (d.invites == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, left: 4),
                    child: Text(
                      'Invitations could not be loaded: ${d.invitesError ?? 'unknown error'}\nInviting and managing people needs an Admin or Account Holder key.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What the dialog hands back: a name for the confirmation and the resource as it now stands, shown at once.
class _Done {
  _Done(this.name, this.resource);
  final String name;
  final Resource resource;
}

/// Invite a new person (no [user]) or change an existing person's roles and app access. Pops with a name to show in the
/// confirmation, or null when cancelled.
class _AccessDialog extends StatefulWidget {
  const _AccessDialog({required this.client, required this.apps, this.user});
  final AscClient client;
  final List<Resource> apps;
  final Resource? user;

  @override
  State<_AccessDialog> createState() => _AccessDialogState();
}

class _AccessDialogState extends State<_AccessDialog> {
  final _email = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();
  late final Set<String> _roles = {...?widget.user?.list('roles')};
  late bool _allApps = widget.user?.flag('allAppsVisible') ?? true;
  late final Set<String> _appIds = {...?widget.user?.relIds('visibleApps')};
  bool _busy = false;
  String? _error;
  bool _tried = false;

  bool get _isInvite => widget.user == null;

  @override
  void dispose() {
    _email.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  List<String> get _problems => accessProblems(
    email: _isInvite ? _email.text : null,
    roles: _roles,
    allApps: _allApps,
    appIds: _appIds,
  );

  Future<void> _submit() async {
    setState(() => _tried = true);
    if (_problems.isNotEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isInvite) {
        final inv = await sendInvitation(
          widget.client,
          inviteBody(
            email: _email.text,
            firstName: _first.text,
            lastName: _last.text,
            roles: _roles,
            allApps: _allApps,
            appIds: _appIds,
          ),
        );
        // Show what was sent even if Apple's reply is sparse.
        final shown = Resource(
          id: inv.id,
          type: 'userInvitations',
          attributes: {
            'email': _email.text.trim(),
            'firstName': _first.text.trim(),
            'lastName': _last.text.trim(),
            'roles': _roles.toList(),
            'allAppsVisible': _allApps || rolesSeeAllApps(_roles),
            ...inv.attributes,
          },
          relationships: {
            'visibleApps': {
              'data': [
                for (final id in _appIds) {'type': 'apps', 'id': id},
              ],
            },
          },
        );
        if (mounted) Navigator.pop(context, _Done(_email.text.trim(), shown));
      } else {
        final u = widget.user!;
        await changeAccess(
          widget.client,
          u.id,
          accessUpdateBody(
            u.id,
            roles: _roles,
            allApps: _allApps,
            appIds: _appIds,
          ),
        );
        final shown = Resource(
          id: u.id,
          type: u.type,
          attributes: {
            ...u.attributes,
            'roles': _roles.toList(),
            'allAppsVisible': _allApps || rolesSeeAllApps(_roles),
          },
          relationships: {
            ...u.relationships,
            'visibleApps': {
              'data': [
                for (final id in _appIds) {'type': 'apps', 'id': id},
              ],
            },
          },
        );
        if (mounted) {
          Navigator.pop(context, _Done(_TeamPageState._display(u), shown));
        }
      }
    } on AscException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _roleCard(
    String r, {
    required bool on,
    required String title,
    String? help,
    required VoidCallback onTap,
  }) {
    final k = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? k.accentSoft.withValues(alpha: 0.6) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: on ? k.accent : k.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    color: on ? k.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: on ? k.accent : const Color(0xFFAEB4C0),
                      width: 1.5,
                    ),
                  ),
                  child: on
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      if (help != null && help.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            help,
                            style: TextStyle(color: k.muted, fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = Tokens.of(context);
    final seesAll = rolesSeeAllApps(_roles);
    final problems = _tried ? _problems : const <String>[];
    final allApps = _allApps || seesAll;
    return Material(
      color: k.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: k.line)),
        ),
        child: SizedBox(
          width: 500,
          height: double.infinity,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isInvite
                                ? 'Invite a user'
                                : 'Edit ${_TeamPageState._display(widget.user!)}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _isInvite
                                ? 'Apple emails them an invitation.'
                                : 'Changes apply straight away.',
                            style: TextStyle(color: k.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isInvite) ...[
                        TextField(
                          controller: _email,
                          autofocus: true,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email address',
                            hintText: 'name@company.com',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _first,
                                decoration: const InputDecoration(
                                  labelText: 'First name',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _last,
                                decoration: const InputDecoration(
                                  labelText: 'Last name',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                      ],
                      const SectionLabel(
                        'Roles',
                        padding: EdgeInsets.only(bottom: 10),
                      ),
                      for (final r in assignableRoles)
                        _roleCard(
                          r,
                          on: _roles.contains(r),
                          title: prettyEnum(r),
                          help: roleHelp[r],
                          onTap: () => setState(
                            () => _roles.contains(r)
                                ? _roles.remove(r)
                                : _roles.add(r),
                          ),
                        ),
                      const SizedBox(height: 10),
                      for (final e in extraPermissions.entries)
                        _roleCard(
                          e.key,
                          on: _roles.contains(e.key),
                          title: e.value,
                          onTap: () => setState(
                            () => _roles.contains(e.key)
                                ? _roles.remove(e.key)
                                : _roles.add(e.key),
                          ),
                        ),
                      const SizedBox(height: 16),
                      const SectionLabel(
                        'App access',
                        padding: EdgeInsets.only(bottom: 10),
                      ),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: true, label: Text('All apps')),
                          ButtonSegment(
                            value: false,
                            label: Text('Selected apps'),
                          ),
                        ],
                        selected: {allApps},
                        onSelectionChanged: seesAll
                            ? null
                            : (v) => setState(() => _allApps = v.first),
                      ),
                      if (seesAll)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Admin and Finance always see every app.',
                            style: TextStyle(color: k.muted, fontSize: 13),
                          ),
                        ),
                      if (!allApps) ...[
                        const SizedBox(height: 12),
                        if (widget.apps.isEmpty)
                          Text(
                            'No apps could be loaded.',
                            style: TextStyle(color: k.muted),
                          )
                        else
                          for (final a in widget.apps)
                            _roleCard(
                              a.id,
                              on: _appIds.contains(a.id),
                              title: a.str('name') ?? a.id,
                              help: a.str('bundleId'),
                              onTap: () => setState(
                                () => _appIds.contains(a.id)
                                    ? _appIds.remove(a.id)
                                    : _appIds.add(a.id),
                              ),
                            ),
                      ],
                      if (problems.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        for (final p in problems)
                          Text(
                            p,
                            style: TextStyle(
                              color: t.colorScheme.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        SelectableText(
                          _error!,
                          style: TextStyle(color: t.colorScheme.error),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isInvite ? 'Send invitation' : 'Save access'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
