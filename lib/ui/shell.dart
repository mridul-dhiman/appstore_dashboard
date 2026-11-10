import 'package:flutter/material.dart';

import '../api/asc_client.dart';
import '../state/app_state.dart';
import 'pages/apps_page.dart';
import 'pages/sales_page.dart';
import 'pages/signing_page.dart';
import 'pages/team_page.dart';
import 'pages/testflight_page.dart';
import 'setup_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('Apps', Icons.apps_outlined, Icons.apps),
  _Dest('TestFlight', Icons.flight_outlined, Icons.flight),
  _Dest('Sales & Trends', Icons.bar_chart_outlined, Icons.bar_chart),
  _Dest('Signing', Icons.verified_user_outlined, Icons.verified_user),
  _Dest('Users and Access', Icons.group_outlined, Icons.group),
];

class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  Widget _page(AscClient client, Credentials creds) => switch (_index) {
        0 => AppsPage(client: client),
        1 => TestFlightPage(client: client),
        2 => SalesPage(client: client, credentials: creds, state: widget.state),
        3 => SigningPage(client: client),
        _ => TeamPage(client: client),
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final client = widget.state.client;
        final creds = widget.state.credentials;
        if (client == null || creds == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        // Keyed by client so switching clients starts every page from scratch.
        final body = KeyedSubtree(key: ValueKey('${creds.id}/$_index'), child: _page(client, creds));
        final wide = MediaQuery.sizeOf(context).width >= 860;
        if (wide) {
          return Scaffold(
            body: Row(children: [
              _Sidebar(state: widget.state, index: _index, onSelect: (i) => setState(() => _index = i)),
              Expanded(child: body),
            ]),
          );
        }
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 8,
            title: ClientSwitcher(state: widget.state),
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            scrolledUnderElevation: 0,
          ),
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [for (final d in _dests) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label)],
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
      width: 248,
      decoration: BoxDecoration(color: k.surface, border: Border(right: BorderSide(color: k.line))),
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: k.accent, borderRadius: BorderRadius.circular(9)),
              child: const Icon(Icons.storefront_outlined, size: 17, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text('Store Console', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
        const SectionLabel('Workspace', padding: EdgeInsets.fromLTRB(10, 6, 10, 8)),
        for (var i = 0; i < _dests.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Material(
              color: i == index ? k.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                hoverColor: t.colorScheme.onSurface.withValues(alpha: 0.05),
                onTap: () => onSelect(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  child: Row(children: [
                    Icon(i == index ? _dests[i].selectedIcon : _dests[i].icon, size: 19, color: i == index ? k.accentInk : k.muted),
                    const SizedBox(width: 11),
                    Text(
                      _dests[i].label,
                      style: TextStyle(fontWeight: i == index ? FontWeight.w600 : FontWeight.w500, color: i == index ? k.accentInk : t.colorScheme.onSurface.withValues(alpha: 0.8)),
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
            padding: const EdgeInsets.only(top: 6),
            child: TextButton.icon(onPressed: state.lock, icon: const Icon(Icons.lock_outline, size: 17), label: const Text('Lock')),
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
        state.switchTo(value);
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
        decoration: BoxDecoration(
          color: t.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: t.colorScheme.primaryContainer,
            child: Text(active.label.characters.first.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w700, color: t.colorScheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(active.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('Key ${active.keyId}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const Icon(Icons.unfold_more, size: 18),
        ]),
      ),
    );
  }
}
