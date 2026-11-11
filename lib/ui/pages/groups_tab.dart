import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../api/team.dart' show looksLikeEmail;
import '../../api/testflight.dart';

import 'package:flutter/services.dart';

import '../qr_view.dart';
import '../theme.dart';
import '../widgets.dart';

part 'groups_dialogs.dart';
part 'group_detail.dart';

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
    final created = await showDialog<String>(
      context: context,
      builder: (_) => _NewGroupDialog(client: widget.client, appId: widget.appId),
    );
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
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  selected: on,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _selected = g.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      child: Row(
                        children: [
                          Icon(isInternal ? Icons.badge_outlined : Icons.public, size: 18, color: on ? k.accentInk : k.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              g.str('name') ?? 'Group',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, color: on ? k.accentInk : null),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 8, 0, 40),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 2, 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text('Groups', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              ),
                              IconButton(
                                tooltip: 'Refresh',
                                visualDensity: VisualDensity.compact,
                                onPressed: _reload.reload,
                                icon: const Icon(Icons.refresh, size: 18),
                              ),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 30),
                                  padding: const EdgeInsets.symmetric(horizontal: 11),
                                ),
                                onPressed: _create,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('New'),
                              ),
                            ],
                          ),
                        ),
                        const SectionLabel('Internal', padding: EdgeInsets.fromLTRB(8, 8, 8, 6)),
                        if (internal.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Text('None', style: TextStyle(color: k.muted)),
                          ),
                        for (final g in internal) tile(g),
                        const SectionLabel('External', padding: EdgeInsets.fromLTRB(8, 14, 8, 6)),
                        if (external.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Text('None', style: TextStyle(color: k.muted)),
                          ),
                        for (final g in external) tile(g),
                      ],
                    ),
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
          ],
        );
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
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
              _internal ? 'Internal: up to 100 people who are users on this App Store Connect team. Builds need no review.' : 'External: up to 10,000 testers, invited by email or a public link. The first build of each version needs Beta App Review.',
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
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _create, child: const Text('Create group')),
      ],
    );
  }
}
