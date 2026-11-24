import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/models.dart';
import '../../api/queries.dart';
import '../../services/profile_installer.dart';
import '../theme.dart';
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
                _ProfilesTab(client: c, controller: _reload),
                _DevicesTab(client: c, controller: _reload),
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
          children: [for (final r in p.data) _BundleIdTile(client: client, bundleId: r)],
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
    final available = capabilityLabels.entries.where((e) => !enabledTypes.contains(e.key)).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All known capabilities are already enabled.')));
      return;
    }
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Enable capability'),
        children: [for (final e in available) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.key), child: Text(e.value))],
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
                if (_caps != null)
                  Text(
                    '${_caps!.length} capabilities',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: _toggle,
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            if (_loading && _caps == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              )
            else if (_caps != null) ...[
              for (final cap in _caps!)
                ListTile(
                  dense: true,
                  leading: Icon(Icons.check_circle, size: 18, color: Tokens.of(context).good),
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

// ---- Profiles tab with regeneration -----------------------------------------------------------------------------------

class _ProfilesTab extends StatefulWidget {
  const _ProfilesTab({required this.client, required this.controller});
  final AscClient client;
  final ReloadController controller;

  @override
  State<_ProfilesTab> createState() => _ProfilesTabState();
}

class _ProfilesTabState extends State<_ProfilesTab> {
  final _reload = ReloadController();
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onParentReload);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onParentReload);
    _reload.dispose();
    super.dispose();
  }

  void _onParentReload() => _reload.reload();

  Future<void> _create() async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _CreateProfileDialog(client: widget.client),
    );
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    setState(() => _epoch++);
    _reload.reload();
  }

  Future<void> _download(Resource profile) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final installed = await installProfile(profile);
      if (installed) {
        messenger.showSnackBar(SnackBar(content: Text('Installed "${profile.str('name')}" for Xcode.')));
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Profile install is only available in the macOS app.')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed to install: $e')));
    }
  }

  Future<void> _regenerate(Resource profile) async {
    final name = profile.str('name') ?? '';
    final type = profile.str('profileType') ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate profile?'),
        content: Text(
          'This deletes "$name" and recreates it with the same certificates and all currently registered devices.\n\n'
          'Xcode will pick up the new profile automatically.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Regenerate')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final detail = await loadProfileDetail(widget.client, profile.id);
      final p = detail.data.first;
      final bundleIdId = p.relId('bundleId');
      if (bundleIdId == null) throw AscException('Profile has no linked bundle ID.');

      final certIds = p.relIds('certificates');
      final allDevices = await loadDevices(widget.client);
      final deviceIds = allDevices.data.map((r) => r.id).toList();

      await deleteProfile(widget.client, profile.id);
      final newProfile = await createProfile(
        widget.client,
        name: name,
        profileType: type,
        bundleIdResourceId: bundleIdId,
        certificateIds: certIds,
        deviceIds: deviceIds,
      );
      final installed = await installProfile(newProfile);
      final suffix = installed ? ' and installed locally' : '';
      messenger.showSnackBar(
        SnackBar(content: Text('Regenerated "$name" with ${deviceIds.length} device${deviceIds.length == 1 ? '' : 's'}$suffix.')),
      );
      if (mounted) {
        setState(() => _epoch++);
        _reload.reload();
      }
    } on AscException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      key: ValueKey(_epoch),
      controller: _reload,
      load: () => loadProfiles(widget.client),
      builder: (context, p) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Spacer(),
                  FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add, size: 18), label: const Text('Create profile')),
                ],
              ),
            ),
            if (p.data.isEmpty)
              const EmptyView('No profiles.')
            else
              RowsCard(
                children: [
                  for (final r in p.data)
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: Text(r.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${prettyEnum(r.str('profileType'))} · created ${fmtDate(r.date('createdDate'))}'),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StateChip(r.str('profileState')),
                          _Expiry(r.date('expirationDate')),
                          IconButton(
                            onPressed: () => _download(r),
                            icon: const Icon(Icons.download, size: 18),
                            tooltip: 'Install profile locally',
                            style: IconButton.styleFrom(minimumSize: const Size(32, 32)),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _regenerate(r),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Regenerate'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 30), textStyle: const TextStyle(fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog({required this.client});
  final AscClient client;

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  late final Future<(List<Resource>, List<Resource>, List<Resource>)> _data = _load();
  final _name = TextEditingController();
  ProfileKind _kind = profileKinds.firstWhere((k) => k.type == 'IOS_APP_STORE');
  String? _bundleId;
  final _certs = <String>{};
  Set<String>? _devices;
  bool _busy = false;
  String? _error;

  Future<(List<Resource>, List<Resource>, List<Resource>)> _load() async {
    final r = await Future.wait([loadBundleIds(widget.client), loadCertificates(widget.client), loadDevices(widget.client)]);
    return (r[0].data, r[1].data, r[2].data);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<Resource> _certsFor(List<Resource> all) => [
    for (final c in all)
      if (_kind.certTypes.contains(c.str('certificateType')) && (c.date('expirationDate')?.isAfter(DateTime.now()) ?? true)) c,
  ];

  List<Resource> _devicesFor(List<Resource> all) => [
    for (final d in all)
      if (d.str('platform') == _kind.platform && d.str('status') != 'DISABLED') d,
  ];

  void _setKind(ProfileKind k, List<Resource> bundles) {
    setState(() {
      _kind = k;
      _certs.clear();
      _devices = null;
      if (_bundleId != null && !k.fitsBundle(bundles.firstWhere((b) => b.id == _bundleId).str('platform'))) _bundleId = null;
    });
  }

  Future<void> _submit(List<Resource> devices) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final name = _name.text.trim();
      final created = await createProfile(
        widget.client,
        name: name,
        profileType: _kind.type,
        bundleIdResourceId: _bundleId!,
        certificateIds: _certs.toList(),
        deviceIds: _kind.needsDevices ? (_devices ?? {for (final d in devices) d.id}).toList() : const [],
      );
      var installed = false;
      try {
        installed = await installProfile(created);
      } catch (_) {}
      if (mounted) Navigator.pop(context, 'Created "$name"${installed ? ' and installed it for Xcode' : ''}.');
    } on AscException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Widget _section(String title, String? hint) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Row(
        children: [
          Text(title, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          if (hint != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(hint, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _data,
      builder: (context, snap) {
        final Widget body;
        List<Resource> devices = const [];
        var valid = false;
        if (snap.hasError) {
          body = Text('${snap.error}', style: TextStyle(color: Theme.of(context).colorScheme.error));
        } else if (!snap.hasData) {
          body = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
        } else {
          final (allBundles, allCerts, allDevices) = snap.data!;
          final bundles = [
            for (final b in allBundles)
              if (_kind.fitsBundle(b.str('platform'))) b,
          ];
          final certs = _certsFor(allCerts);
          devices = _devicesFor(allDevices);
          final chosenDevices = _devices ?? {for (final d in devices) d.id};
          valid =
              _name.text.trim().isNotEmpty && _bundleId != null && _certs.isNotEmpty && (!_kind.needsDevices || chosenDevices.isNotEmpty);
          body = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Profile name', helperText: 'e.g. "Vidyagram AppStore"'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ProfileKind>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [for (final k in profileKinds) DropdownMenuItem(value: k, child: Text(k.label))],
                onChanged: (k) => _setKind(k!, allBundles),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('bundle-${_kind.type}'),
                initialValue: _bundleId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'App ID'),
                items: [
                  for (final b in bundles)
                    DropdownMenuItem(
                      value: b.id,
                      child: Text('${b.str('name')} · ${b.str('identifier')}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _bundleId = v),
              ),
              _section('Certificates', 'Choose the certificate you sign with.'),
              if (certs.isEmpty)
                Text(
                  'No valid certificate can sign a ${_kind.label} profile.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                for (final c in certs)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _certs.contains(c.id),
                    onChanged: (v) => setState(() => v! ? _certs.add(c.id) : _certs.remove(c.id)),
                    title: Text('${prettyEnum(c.str('certificateType'))} · ${c.str('displayName') ?? c.str('name') ?? ''}'),
                    subtitle: Text('Serial ${c.str('serialNumber') ?? ''} · expires ${fmtDate(c.date('expirationDate'))}'),
                  ),
              if (_kind.needsDevices) ...[
                _section('Devices', '${chosenDevices.length} of ${devices.length} selected'),
                if (devices.isEmpty)
                  Text(
                    'No ${prettyPlatform(_kind.platform)} devices are registered.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  )
                else
                  for (final d in devices)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: chosenDevices.contains(d.id),
                      onChanged: (v) => setState(() {
                        final s = {...chosenDevices};
                        v! ? s.add(d.id) : s.remove(d.id);
                        _devices = s;
                      }),
                      title: Text(d.str('name') ?? ''),
                      subtitle: Text(d.str('udid') ?? ''),
                    ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          );
        }
        return AlertDialog(
          title: const Text('Create provisioning profile'),
          content: SizedBox(width: 520, child: SingleChildScrollView(child: body)),
          actions: [
            TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: valid && !_busy ? () => _submit(devices) : null,
              child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}

// ---- Devices tab with registration ------------------------------------------------------------------------------------

class _DevicesTab extends StatefulWidget {
  const _DevicesTab({required this.client, required this.controller});
  final AscClient client;
  final ReloadController controller;

  @override
  State<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<_DevicesTab> {
  final _reload = ReloadController();
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onParentReload);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onParentReload);
    _reload.dispose();
    super.dispose();
  }

  void _onParentReload() => _reload.reload();

  Future<void> _addDevice() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => _RegisterDeviceDialog(client: widget.client),
    );
    if (added == true && mounted) {
      setState(() => _epoch++);
      _reload.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<ResourcePage>(
      key: ValueKey(_epoch),
      controller: _reload,
      load: () => loadDevices(widget.client),
      builder: (context, p) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  const Spacer(),
                  FilledButton.icon(onPressed: _addDevice, icon: const Icon(Icons.add, size: 18), label: const Text('Register device')),
                ],
              ),
            ),
            if (p.data.isEmpty)
              const EmptyView('No registered devices.')
            else
              RowsCard(
                children: [
                  for (final r in p.data)
                    ListTile(
                      leading: Icon(r.str('deviceClass') == 'IPAD' ? Icons.tablet_mac : Icons.phone_iphone),
                      title: Text(r.str('name') ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: SelectableText('${r.str('model') ?? prettyEnum(r.str('deviceClass'))} · ${r.str('udid')}'),
                      trailing: StateChip(r.str('status')),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _RegisterDeviceDialog extends StatefulWidget {
  const _RegisterDeviceDialog({required this.client});
  final AscClient client;

  @override
  State<_RegisterDeviceDialog> createState() => _RegisterDeviceDialogState();
}

class _RegisterDeviceDialogState extends State<_RegisterDeviceDialog> {
  final _name = TextEditingController();
  final _udid = TextEditingController();
  String _platform = 'IOS';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _udid.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _udid.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await registerDevice(widget.client, name: _name.text.trim(), udid: _udid.text.trim(), platform: _platform);
      if (mounted) Navigator.pop(context, true);
    } on AscException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Register a device'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Device name', helperText: 'e.g. "Mridul\'s iPhone"'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _udid,
              decoration: const InputDecoration(labelText: 'UDID', helperText: '40-character hex (or 25-character for Apple Silicon Macs)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _platform,
              decoration: const InputDecoration(labelText: 'Platform'),
              items: [for (final p in devicePlatforms) DropdownMenuItem(value: p, child: Text(prettyPlatform(p)))],
              onChanged: (v) => setState(() => _platform = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _valid && !_busy ? _submit : null,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Register'),
        ),
      ],
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
        ? Tokens.of(context).bad
        : days < 30
        ? Tokens.of(context).warn
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
