import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api/asc_client.dart';
import '../state/app_state.dart';
import '../state/reply_templates.dart';
import '../state/upload_jobs.dart';
import 'command_palette.dart';
import 'pages/analytics_page.dart';
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

/// The five places in the sidebar. TestFlight, reviews and uploads live inside each app, not here.
const _dests = [
  _Dest('Apps', Icons.apps_outlined, Icons.apps),
  _Dest('Sales & Trends', Icons.bar_chart_outlined, Icons.bar_chart),
  _Dest('Analytics', Icons.analytics_outlined, Icons.analytics),
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
  UploadJobs _uploads = UploadJobs(); // per client; outlives the app page so an upload keeps its progress
  ReplyTemplates? _templates; // per client

  /// The apps list, loaded once per client and shared with the command palette.
  AppsStore _storeFor(Credentials creds, AscClient client) {
    // Renaming a client or changing its vendor number makes a new AscClient (the old one is closed), so the store must
    // follow the client object itself, not just the client id. Only a different client closes the open app.
    if (_owner != creds.id) {
      _app = null;
      if (_store != null) _uploads = UploadJobs();
    }
    if (_owner != creds.id || _store == null || !identical(_store!.client, client)) {
      final newClient = _owner != creds.id;
      _owner = creds.id;
      if (newClient) _templates = ReplyTemplates(prefs: widget.state.prefs, clientId: creds.id);
      _store = AppsStore(client);
      if (newClient) _restoreLastApp(creds, _store!);
    }
    return _store!;
  }

  bool _unsaved = false; // the open app has listing edits that are not sent yet

  /// Runs [leave] once it is safe to close the open app page: straight away, or after confirming that unsent listing
  /// edits may be thrown away.
  Future<void> _guard(VoidCallback leave) async {
    if (_app == null || !_unsaved) return leave();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard unsent changes?'),
        content: const Text('The store listing has edits that have not been applied yet. Leaving this page throws them away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true && mounted) {
      _unsaved = false;
      leave();
    }
  }

  /// An app page saw a version state the apps list does not have; the list reloads when shown again.
  bool _appsStale = false;

  void _select(int i) => _guard(() {
    if (i == 0 && _appsStale) {
      _appsStale = false;
      unawaited(_store?.refresh());
    }
    setState(() {
      _index = i;
      _app = null;
    });
    _remember(null);
  });

  void _openApp(AppSummary app, {int tab = 0}) => _guard(() => _show(app, tab: tab));

  void _show(AppSummary app, {int tab = 0}) {
    setState(() {
      _index = 0;
      _app = app;
      _appTab = tab;
    });
    _remember(app.id, tab);
  }

  void _remember(String? appId, [int tab = 0]) {
    final id = widget.state.credentials?.id;
    if (id != null) unawaited(widget.state.prefs.setLastApp(id, appId, tab));
  }

  /// On the first load for a client, reopen the app and tab that were open last time.
  void _restoreLastApp(Credentials creds, AppsStore store) {
    final last = widget.state.prefs.lastApp(creds.id);
    if (last == null) return;
    unawaited(
      store.apps.then((apps) {
        final app = apps.where((a) => a.id == last.appId).firstOrNull;
        if (app == null || !mounted || _owner != creds.id || _app != null || _index != 0) return;
        setState(() {
          _app = app;
          _appTab = last.tab;
        });
      }, onError: (_) {}),
    );
  }

  int _refresh = 0; // bumped by ⌘R: the current page is rebuilt from scratch and loads again
  int _currentTab = 0; // the open app's tab right now, so a refresh keeps it

  void _reloadPage() => _guard(() {
    if (_app != null) _appTab = _currentTab;
    // The apps list is cached in the store, not the page; refresh it from inside an app too, so going back shows a state
    // changed meanwhile (for example a submission).
    if (_index == 0) unawaited(_store?.refresh());
    setState(() => _refresh++);
  });

  void _back() {
    if (_app != null) _select(0);
  }

  /// One table for the menu bar and the keyboard: ⌘1–4 go to the sidebar places, ⌘R reloads, ⌘K searches, ⌘[ goes back
  /// from an app. Ctrl works too, for the web build on other systems. (No bare Esc: it would leave the page from inside
  /// a text field.) Each one asks first when the listing has unsent edits.
  Map<ShortcutActivator, VoidCallback> get _shortcuts => {
    for (final mod in [(meta: true, control: false), (meta: false, control: true)]) ...{
      SingleActivator(LogicalKeyboardKey.keyK, meta: mod.meta, control: mod.control): _palette,
      SingleActivator(LogicalKeyboardKey.keyR, meta: mod.meta, control: mod.control): _reloadPage,
      SingleActivator(LogicalKeyboardKey.bracketLeft, meta: mod.meta, control: mod.control): _back,
      for (var i = 0; i < _dests.length; i++)
        SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), meta: mod.meta, control: mod.control): () => _select(i),
    },
  };

  /// The macOS menu bar, replacing Flutter's default one. Its shortcuts are the same as [_shortcuts].
  List<PlatformMenuItem> _menus(Brightness brightness) => [
    PlatformMenu(
      label: 'App Store Dashboard',
      menus: [
        const PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about)]),
        if (widget.state.supportsDeviceLock)
          PlatformMenuItemGroup(
            members: [
              PlatformMenuItem(
                label: 'Lock',
                shortcut: const SingleActivator(LogicalKeyboardKey.keyL, meta: true, control: true),
                onSelected: widget.state.lock,
              ),
            ],
          ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hideOtherApplications),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.showAllApplications),
          ],
        ),
        const PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit)]),
      ],
    ),
    PlatformMenu(
      label: 'View',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Reload Page',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
              onSelected: _reloadPage,
            ),
            PlatformMenuItem(label: 'Search…', shortcut: const SingleActivator(LogicalKeyboardKey.keyK, meta: true), onSelected: _palette),
            PlatformMenu(
              label: 'Appearance',
              menus: [
                for (final m in ThemeMode.values)
                  PlatformMenuItem(
                    label: '${widget.state.themeMode == m ? '✓ ' : ''}${themeModeLabel(m)}',
                    onSelected: () => widget.state.setThemeMode(m),
                  ),
              ],
            ),
          ],
        ),
        const PlatformMenuItemGroup(members: [PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.toggleFullScreen)]),
      ],
    ),
    PlatformMenu(
      label: 'Go',
      menus: [
        PlatformMenuItemGroup(
          members: [
            for (var i = 0; i < _dests.length; i++)
              PlatformMenuItem(
                label: _dests[i].label,
                shortcut: SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), meta: true),
                onSelected: () => _select(i),
              ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: 'Back to Applications',
              shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
              onSelected: _app == null ? null : _back,
            ),
          ],
        ),
      ],
    ),
    const PlatformMenu(
      label: 'Window',
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.minimizeWindow),
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
          ],
        ),
      ],
    ),
  ];

  void _palette() {
    final store = _store;
    if (store == null || !mounted) return;
    unawaited(
      showCommandPalette(
        context,
        PaletteActions(store: store, openApp: _openApp, go: _select, lock: widget.state.supportsDeviceLock ? widget.state.lock : null),
      ),
    );
  }

  Widget _page(AscClient client, Credentials creds, AppsStore store) {
    if (_index == 0 && _app != null) {
      return AppDetailPage(
        key: ValueKey('${_app!.id}/$_appTab/$_refresh'),
        client: client,
        summary: _app!,
        initialTab: _appTab,
        uploads: _uploads,
        templates: _templates,
        onTabChanged: (t) {
          _currentTab = t;
          _remember(_app?.id, t);
        },
        onUnsavedChanged: (v) => _unsaved = v,
        onStateChanged: () => _appsStale = true,
        onBack: () => _select(0),
      );
    }
    return switch (_index) {
      0 => AppsPage(
        store: store,
        onOpen: _openApp,
        onOpenTestFlight: (a) => _openApp(a, tab: AppDetailPage.testFlightTabIndex),
        prefs: widget.state.prefs,
      ),
      1 => SalesPage(client: client, credentials: creds, state: widget.state),
      2 => AnalyticsPage(client: client, store: store),
      3 => SigningPage(client: client),
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
        final body = KeyedSubtree(key: ValueKey('${creds.id}/$_index/$_refresh'), child: _page(client, creds, store));
        final wide = MediaQuery.sizeOf(context).width >= 860;
        final brightness = Theme.of(context).brightness;
        final bar = MacTitleBar(onSearch: _palette, themeMode: widget.state.themeMode, onThemeMode: widget.state.setThemeMode);
        final shell = CallbackShortcuts(
          bindings: _shortcuts,
          child: Focus(
            autofocus: true,
            child: wide
                ? Scaffold(
                    body: Column(
                      children: [
                        bar,
                        Expanded(
                          child: Row(
                            children: [
                              _Sidebar(state: widget.state, index: _index, onSelect: _select),
                              Expanded(child: body),
                            ],
                          ),
                        ),
                      ],
                    ),
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
                      destinations: [
                        for (final d in _dests)
                          NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
                      ],
                    ),
                  ),
          ),
        );
        // The real menu bar exists only in the macOS app; elsewhere the keyboard table above does the same.
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return shell;
        return PlatformMenuBar(menus: _menus(brightness), child: shell);
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
      decoration: BoxDecoration(
        color: k.sidebar,
        border: Border(right: BorderSide(color: k.line)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Workspace', padding: EdgeInsets.fromLTRB(10, 0, 10, 8)),
          for (var i = 0; i < _dests.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: i == index ? k.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: MergeSemantics(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => onSelect(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(i == index ? _dests[i].selectedIcon : _dests[i].icon, size: 19, color: i == index ? k.accentInk : k.muted),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                _dests[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                                  color: i == index ? k.accentInk : t.colorScheme.onSurface.withValues(alpha: 0.82),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
        ],
      ),
    );
  }
}

/// The client picker: shows the active API key and lets you switch to another saved one, or add a new key + issuer ID.
class ClientSwitcher extends StatelessWidget {
  const ClientSwitcher({super.key, required this.state});
  final AppState state;

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
        final n = await askText(context, title: 'Rename client', label: 'Name', initial: active.label);
        if (n != null && n.trim().isNotEmpty) await state.rename(active.id, n);
      case '__vendor':
        await askVendorNumber(context, state);
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
            child: Row(
              children: [
                SizedBox(width: 24, child: a.id == active.id ? const Icon(Icons.check, size: 18) : null),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.label, overflow: TextOverflow.ellipsis),
                      Text('Key ${a.keyId}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: '__add',
          child: ListTile(dense: true, leading: Icon(Icons.add), title: Text('Add client (key + issuer ID)…')),
        ),
        const PopupMenuItem(
          value: '__rename',
          child: ListTile(dense: true, leading: Icon(Icons.edit_outlined), title: Text('Rename this client…')),
        ),
        const PopupMenuItem(
          value: '__vendor',
          child: ListTile(dense: true, leading: Icon(Icons.tag), title: Text('Vendor number…')),
        ),
        const PopupMenuItem(
          value: '__remove',
          child: ListTile(dense: true, leading: Icon(Icons.delete_outline), title: Text('Remove this client')),
        ),
        if (state.supportsDeviceLock)
          const PopupMenuItem(
            value: '__lock',
            child: ListTile(dense: true, leading: Icon(Icons.lock_outline), title: Text('Lock now')),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Tokens.of(context).surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Tokens.of(context).line),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Avatar(active.label, size: 32),
                // Green: the key is loaded and requests are going through.
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Tokens.of(context).good,
                      shape: BoxShape.circle,
                      border: Border.all(color: Tokens.of(context).surface, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    active.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text('Key ${active.keyId}', style: TextStyle(fontSize: 11.5, color: t.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            const Icon(Icons.unfold_more, size: 17),
          ],
        ),
      ),
    );
  }
}
