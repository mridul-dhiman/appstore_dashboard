import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../api/queries.dart';
import '../widgets.dart';

/// Certificates, identifiers, profiles and devices: the Developer-portal side of the same API key.
class SigningPage extends StatefulWidget {
  const SigningPage({super.key, required this.client});
  final AscClient client;

  @override
  State<SigningPage> createState() => _SigningPageState();
}

class _SigningPageState extends State<SigningPage> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          PageHeader(title: 'Signing', subtitle: 'Certificates, identifiers, profiles and devices', reload: _reload),
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 16),
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Certificates'),
                  Tab(text: 'Identifiers'),
                  Tab(text: 'Profiles'),
                  Tab(text: 'Devices'),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _List(
                  controller: _reload,
                  load: () => loadCertificates(c),
                  empty: 'No certificates.',
                  tile: (r, _) => ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: Text(
                      '${prettyEnum(r.str('certificateType'))} · ${r.str('displayName') ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('${r.str('name') ?? ''} · serial ${r.str('serialNumber') ?? ''}'),
                    trailing: _Expiry(r.date('expirationDate')),
                  ),
                ),
                _IdentifiersTab(client: c, controller: _reload),
                _List(
                  controller: _reload,
                  load: () => loadProfiles(c),
                  empty: 'No profiles.',
                  tile: (r, _) => ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(r.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${prettyEnum(r.str('profileType'))} · created ${fmtDate(r.date('createdDate'))}'),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [StateChip(r.str('profileState')), _Expiry(r.date('expirationDate'))],
                    ),
                  ),
                ),
                _List(
                  controller: _reload,
                  load: () => loadDevices(c),
                  empty: 'No registered devices.',
                  tile: (r, _) => ListTile(
                    leading: Icon(r.str('deviceClass') == 'IPAD' ? Icons.tablet_mac : Icons.phone_iphone),
                    title: Text(r.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: SelectableText('${r.str('model') ?? prettyEnum(r.str('deviceClass'))} · ${r.str('udid')}'),
                    trailing: StateChip(r.str('status')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Identifiers tab with capabilities -------------------------------------------------------------------------------

class _IdentifiersTab extends StatelessWidget {
  const _IdentifiersTab({required this.client, required this.controller});
  final AscClient client;
  final ReloadController controller;

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      controller: controller,
      load: () => loadBundleIds(client),
      builder: (context, p) {
        if (p.data.isEmpty) return const EmptyView('No identifiers.');
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            for (final r in p.data) _BundleIdTile(client: client, bundleId: r),
          ],
        );
      },
    );
  }
}

class _BundleIdTile extends StatefulWidget {
  const _BundleIdTile({required this.client, required this.bundleId});
  final AscClient client;
  final Resource bundleId;

  @override
  State<_BundleIdTile> createState() => _BundleIdTileState();
}

class _BundleIdTileState extends State<_BundleIdTile> {
  bool _expanded = false;
  List<Resource>? _caps;
  bool _loading = false;
  String? _error;

  Future<void> _loadCaps() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await loadBundleIdCapabilities(widget.client, widget.bundleId.id);
      if (mounted) setState(() => _caps = p.data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _caps == null && !_loading) unawaited(_loadCaps());
  }

  Future<void> _enable(String capType) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await enableCapability(widget.client, widget.bundleId.id, capType);
      messenger.showSnackBar(SnackBar(content: Text('Enabled ${prettyCapability(capType)}.')));
      unawaited(_loadCaps());
    } on AscException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _disable(Resource cap) async {
    final type = cap.str('capabilityType') ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disable ${prettyCapability(type)}?'),
        content: const Text('This removes the capability from this identifier. Profiles using it may need to be regenerated.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disable'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await disableCapability(widget.client, cap.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Disabled ${prettyCapability(type)}.')));
      unawaited(_loadCaps());
    } on AscException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _addCapability() async {
    final enabledTypes = {for (final c in _caps ?? <Resource>[]) c.str('capabilityType')};
    final available = capabilityLabels.entries.where((e) => !enabledTypes.contains(e.key)).toList()..sort((a, b) => a.value.compareTo(b.value));
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All known capabilities are already enabled.')));
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Enable capability'),
        children: [
          for (final e in available)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value)),
        ],
      ),
    );
    if (chosen != null) await _enable(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.bundleId;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: Text(r.str('identifier') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${r.str('name')} · ${prettyPlatform(r.str('platform'))}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_caps != null) Text('${_caps!.length} capabilities', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: _toggle,
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (_loading && _caps == null)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
            else if (_caps != null) ...[
              for (final cap in _caps!)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle, size: 18, color: Color(0xFF1F8F45)),
                  title: Text(prettyCapability(cap.str('capabilityType') ?? '')),
                  trailing: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () => _disable(cap),
                    child: const Text('Disable'),
                  ),
                ),
              if (_caps!.isEmpty)
                const ListTile(dense: true, leading: Icon(Icons.info_outline, size: 18), title: Text('No capabilities enabled.')),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addCapability,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Enable capability'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 32), textStyle: const TextStyle(fontSize: 12.5)),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---- Shared widgets --------------------------------------------------------------------------------------------------

class _Expiry extends StatelessWidget {
  const _Expiry(this.date);
  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    if (date == null) return const SizedBox.shrink();
    final days = date!.difference(DateTime.now()).inDays;
    final color = days < 0
        ? const Color(0xFFD13438)
        : days < 30
        ? const Color(0xFFB77300)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      days < 0 ? 'Expired ${fmtDate(date)}' : 'Expires ${fmtDate(date)}',
      style: TextStyle(color: color, fontWeight: days < 30 ? FontWeight.w700 : null, fontSize: 13),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller, required this.load, required this.tile, required this.empty});
  final ReloadController controller;
  final Future<ResourcePage> Function() load;
  final Widget Function(Resource r, ResourcePage p) tile;
  final String empty;

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      controller: controller,
      load: load,
      builder: (context, p) {
        if (p.data.isEmpty) return EmptyView(empty);
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            RowsCard(children: [for (final r in p.data) tile(r, p)]),
          ],
        );
      },
    );
  }
}
