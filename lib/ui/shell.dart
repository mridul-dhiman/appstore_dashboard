import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/asc_client.dart';
import '../state/app_state.dart';
import 'command_palette.dart';
import 'pages/app_detail_page.dart';
import 'pages/apps_page.dart';
import 'pages/sales_page.dart';
import 'pages/signing_page.dart';
import 'pages/team_page.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The four places in the sidebar. TestFlight, reviews and uploads live inside each app, not here.
const _dests = [
  _Dest('Apps', Icons.apps_outlined, Icons.apps),
  _Dest('Sales & Trends', Icons.bar_chart_outlined, Icons.bar_chart),
  _Dest('Signing', Icons.verified_user_outlined, Icons.verified_user),
  _Dest('Users and Access', Icons.group_outlined, Icons.group),
];

/// The sidebar's labels, in order. A test pins this to four so TestFlight and friends cannot drift back out here.
List<String> get shellDestinationLabels => [for (final d in _dests) d.label];

class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  AppSummary? _app; // the app whose workspace is open inside the Apps destination
  int _appTab = 0;
  String? _owner; // client id the open app and the apps list belong to
  AppsStore? _store;

  /// The apps list, loaded once per client and shared with the command palette.
  AppsStore _storeFor(Credentials creds, AscClient client) {
    // Renaming a client or changing its vendor number makes a new AscClient (the old one is closed), so the store must
    // follow the client object itself, not just the client id. Only a different client closes the open app.
    if (_owner != creds.id) _app = null;
    if (_owner != creds.id || _store == null || !identical(_store!.client, client)) {
      _owner = creds.id;
      _store = AppsStore(client);
    }
    return _store!;
  }

  void _select(int i) => setState(() {
        _index = i;
        _app = null;
      });

  void _openApp(AppSummary app, {int tab = 0}) => setState(() {
        _index = 0;
        _app = app;
        _appTab = tab;
      });

  void _palette() {
    final store = _store;
    if (store == null || !mounted) return;
    showCommandPalette(
      context,
      PaletteActions(store: store, openApp: _openApp, go: _select, lock: widget.state.supportsDeviceLock ? widget.state.lock : null),
    );
  }

  Widget _page(AscClient client, Credentials creds, AppsStore store) {
    if (_index == 0 && _app != null) {
      return AppDetailPage(key: ValueKey('${_app!.id}/$_appTab'), client: client, summary: _app!, initialTab: _appTab, onBack: () => setState(() => _app = null));
    }
    return switch (_index) {
      0 => AppsPage(store: store, onOpen: _openApp),
      1 => SalesPage(client: client, credentials: creds, state: widget.state),
      2 => SigningPage(client: client),
      _ => TeamPage(client: client),
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final client = widget.state.client;
        final creds = widget.state.credentials;
        if (client == null || creds == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final store = _storeFor(creds, client);
        // Keyed by client so switching clients starts every page from scratch.
        final body = KeyedSubtree(key: ValueKey('${creds.id}/$_index'), child: _page(client, creds, store));
        final wide = MediaQuery.sizeOf(context).width >= 860;
        final brightness = Theme.of(context).brightness;
        final bar = MacTitleBar(onSearch: _palette, themeMode: widget.state.themeMode, onToggleTheme: () => widget.state.toggleTheme(brightness));
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _palette,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): _palette,
          },
          child: Focus(
            autofocus: true,
            child: wide
                ? Scaffold(
                    body: Column(children: [
                      bar,
                      Expanded(
                        child: Row(children: [
                          _Sidebar(state: widget.state, index: _index, onSelect: _select),
                          Expanded(child: body),
                        ]),
                      ),
                    ]),
                  )
                : Scaffold(
                    appBar: AppBar(
                      titleSpacing: 8,
                      title: ClientSwitcher(state: widget.state),
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                      scrolledUnderElevation: 0,
                      actions: [IconButton(tooltip: 'Search', onPressed: _palette, icon: const Icon(Icons.search))],
                    ),
                    body: body,
                    bottomNavigationBar: NavigationBar(
                      selectedIndex: _index,
                      onDestinationSelected: _select,
                      destinations: [for (final d in _dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)],
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.state, required this.index, required this.onSelect});
  final AppState state;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final k = Tokens.of(context);
    return Container(
      width: 240,
      decoration: BoxDecoration(color: k.sidebar, border: Border(right: BorderSide(color: k.line))),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SectionLabel('Workspace', padding: EdgeInsets.fromLTRB(10, 0, 10, 8)),
        for (var i = 0; i < _dests.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: i == index ? k.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Row(children: [
                    Icon(i == index ? _dests[i].selectedIcon : _dests[i].icon, size: 19, color: i == index ? k.accentInk : k.muted),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(_dests[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, fontWeight: i == index ? FontWeight.w600 : FontWeight.w500, color: i == index ? k.accentInk : t.colorScheme.onSurface.withValues(alpha: 0.82))),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        const Spacer(),
        ClientSwitcher(state: state),
        if (state.supportsDeviceLock)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(onPressed: state.lock, icon: const Icon(Icons.lock_outline, size: 16), label: const Text('Lock')),
          ),
      ]),
    );
  }
}

/// The client picker: shows the active API key and lets you switch to another saved one, or add a new key + issuer ID.
class ClientSwitcher extends StatelessWidget {
  const ClientSwitcher({super.key, required this.state});
  final AppState state;

  Future<String?> _ask(BuildContext context, String title, String label, String initial, {String? helper}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: label, helperText: helper), onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, String value) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _run(context, value);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the change to your keychain: $e')));
    }
  }

  Future<void> _run(BuildContext context, String value) async {
    final active = state.credentials!;
    switch (value) {
      case '__add':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetupScreen(state: state, embedded: true)));
      case '__rename':
        final n = await _ask(context, 'Rename client', 'Name', active.label);
        if (n != null && n.trim().isNotEmpty) await state.rename(active.id, n);
      case '__vendor':
        final v = await _ask(context, 'Vendor number', 'Vendor number', active.vendorNumber,
            helper: 'App Store Connect → Payments and Financial Reports. Used for Sales & Trends.');
        if (v != null) await state.setVendorNumber(v);
      case '__remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Remove ${active.label}?'),
            content: const Text('This deletes the saved key from this app. The key itself stays valid in App Store Connect.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
            ],
          ),
        );
        if (ok == true) await state.remove(active.id);
      case '__lock':
        state.lock();
      default:
        await state.switchTo(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final active = state.credentials!;
    return PopupMenuButton<String>(
      tooltip: 'Switch client',
      position: PopupMenuPosition.under,
      onSelected: (v) => _onSelected(context, v),
      itemBuilder: (_) => [
        for (final a in state.accounts)
          PopupMenuItem(
            value: a.id,
            child: Row(children: [
              SizedBox(width: 24, child: a.id == active.id ? const Icon(Icons.check, size: 18) : null),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.label, overflow: TextOverflow.ellipsis),
                  Text('Key ${a.keyId}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ]),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: '__add', child: ListTile(dense: true, leading: Icon(Icons.add), title: Text('Add client (key + issuer ID)…'))),
        const PopupMenuItem(value: '__rename', child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Rename this client…'))),
        const PopupMenuItem(value: '__vendor', child: ListTile(dense: true, leading: Icon(Icons.tag), title: Text('Vendor number…'))),
        const PopupMenuItem(value: '__remove', child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Remove this client'))),
        if (state.supportsDeviceLock) const PopupMenuItem(value: '__lock', child: ListTile(dense: true, leading: Icon(Icons.lock_outline), title: Text('Lock now'))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: Tokens.of(context).surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Tokens.of(context).line)),
        child: Row(children: [
          Stack(clipBehavior: Clip.none, children: [
            Avatar(active.label, size: 32),
            // Green: the key is loaded and requests are going through.
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: const Color(0xFF34C759), shape: BoxShape.circle, border: Border.all(color: Tokens.of(context).surface, width: 2)),
              ),
            ),
          ]),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(active.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Key ${active.keyId}', style: TextStyle(fontSize: 11.5, color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const Icon(Icons.unfold_more, size: 17),
        ]),
      ),
    );
  }
}
