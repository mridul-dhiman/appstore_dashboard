import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../api/team.dart';
import '../theme.dart';
import '../widgets.dart';

part 'team_access_dialog.dart';

/// Slides a panel in from the right edge. Resolves with whatever the panel pops with.
Future<T?> showDrawer<T>(BuildContext context, WidgetBuilder builder) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Tokens.of(context).scrim,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, _) => Align(alignment: Alignment.centerRight, child: builder(ctx)),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
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

  /// Waits between follow-up reloads while Apple's lists still disagree with what was just done.
  static const catchUpDelays = [Duration(seconds: 2), Duration(seconds: 5), Duration(seconds: 10)];
  int _catchUp = 0;
  Timer? _catchUpTimer;

  /// Reload now; if Apple has not caught up yet, [_load] keeps trying on [catchUpDelays].
  void _refreshSoon() {
    _catchUp = 0;
    _catchUpTimer?.cancel();
    _reload.reload();
  }

  bool get _overlaysPending => _hidden.isNotEmpty || _addedInvites.isNotEmpty || _edited.isNotEmpty;

  Future<TeamData> _load() async {
    final d = await loadTeam(widget.client);
    _apps = d.apps;
    _reconcile(d);
    _catchUpTimer?.cancel();
    if (_overlaysPending && _catchUp < catchUpDelays.length) {
      _catchUpTimer = Timer(catchUpDelays[_catchUp++], () {
        if (mounted) _reload.reload();
      });
    }
    return d;
  }

  /// Drops each local overlay once Apple's own list shows the change, so the page stops second-guessing Apple.
  void _reconcile(TeamData d) {
    final users = {for (final u in d.users.data) u.id: u};
    final invites = d.invites?.data ?? const <Resource>[];
    final inviteIds = {for (final i in invites) i.id};
    final inviteEmails = {for (final i in invites) (i.str('email') ?? '').toLowerCase()};
    _hidden.removeWhere((id) => !users.containsKey(id) && !inviteIds.contains(id));
    _addedInvites.removeWhere((i) => inviteIds.contains(i.id) || inviteEmails.contains((i.str('email') ?? '').toLowerCase()));
    _edited.removeWhere((id, e) => users[id] == null || _sameAccess(users[id]!, e));
  }

  /// Roles and app visibility both match: an edit Apple has applied.
  static bool _sameAccess(Resource a, Resource b) {
    final x = [...a.list('roles')]..sort(), y = [...b.list('roles')]..sort();
    return x.join(',') == y.join(',') && a.flag('allAppsVisible') == b.flag('allAppsVisible');
  }

  List<Resource> _users(TeamData d) {
    return [
      for (final u in d.users.data)
        if (!_hidden.contains(u.id))
          if (_edited[u.id] case final e? when !_sameAccess(u, e)) e else u,
    ];
  }

  List<Resource> _invites(TeamData d) {
    final server = d.invites?.data ?? const <Resource>[];
    final have = {for (final i in server) i.id, for (final i in server) (i.str('email') ?? '').toLowerCase()};
    return [
      ...server.where((i) => !_hidden.contains(i.id)),
      for (final i in _addedInvites)
        if (!_hidden.contains(i.id) && !have.contains(i.id) && !have.contains((i.str('email') ?? '').toLowerCase())) i,
    ];
  }

  @override
  void dispose() {
    _catchUpTimer?.cancel();
    _reload.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _invite() async {
    final sent = await showDrawer<_Done>(context, (_) => _AccessDialog(client: widget.client, apps: _apps));
    if (sent == null) return;
    _addedInvites.add(sent.resource);
    _toast('Invitation sent to ${sent.name}. They get an email from Apple and appear here as Invited until they accept.');
    _refreshSoon();
  }

  Future<void> _edit(Resource user) async {
    final done = await showDrawer<_Done>(context, (_) => _AccessDialog(client: widget.client, apps: _apps, user: user));
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
        content: Text('$who loses access to App Store Connect for this team straight away. They can be invited again later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
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
    final name = '${u.str('firstName') ?? ''} ${u.str('lastName') ?? ''}'.trim();
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
          Avatar(name, color: invited ? (Tokens.light.warnSoft, Tokens.light.warn) : null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  u.str('username') ?? u.str('email') ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (invited) ...[const StateChip('PENDING', label: 'Invited'), const SizedBox(width: 16)],
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
              children: [for (final r in roles) StateChip(null, label: prettyEnum(r))],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 190,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (invited)
                  OutlinedButton(style: _small, onPressed: () => _revoke(u), child: const Text('Revoke'))
                else if (!isHolder) ...[
                  OutlinedButton(style: _small, onPressed: () => _edit(u), child: const Text('Edit')),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: _small.copyWith(foregroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.error)),
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
            FilledButton.icon(onPressed: _invite, icon: const Icon(Icons.add, size: 18), label: const Text('Invite user')),
            const SizedBox(width: 8),
          ],
        ),
        Expanded(
          child: LoadView<TeamData>(
            controller: _reload,
            load: _load,
            builder: (context, d) => ListView(
              padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
              children: [
                RowsCard(children: [for (final u in _users(d)) _row(u)]),
                TruncatedNote(d.users, 'people'),
                if (_invites(d).isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const SectionLabel('Pending invitations'),
                  RowsCard(children: [for (final u in _invites(d)) _row(u, invited: true)]),
                ],
                if (d.invites == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16, left: 4),
                    child: Text(
                      'Invitations could not be loaded: ${d.invitesError ?? 'unknown error'}\nInviting and managing people needs an Admin or Account Holder key.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
