import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/apps_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// How well [query] matches [text] when its letters appear in order, or null when they do not. Higher is better: matches
/// that start the text, start a word or run unbroken score more.
int? fuzzyScore(String query, String text) {
  final q = query.trim().toLowerCase();
  final t = text.toLowerCase();
  if (q.isEmpty) return 0;
  var score = 0, ti = 0, run = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final found = t.indexOf(q[qi], ti);
    if (found < 0) return null;
    final startsWord = found == 0 || ' ._-/'.contains(t[found - 1]);
    run = found == ti && qi > 0 ? run + 1 : 0;
    score += 10 + run * 6 + (startsWord ? 8 : 0) - (found - ti).clamp(0, 6);
    ti = found + 1;
  }
  if (t.startsWith(q)) score += 25;
  return score;
}

/// A line in the palette: an action to run, or an app to open.
class PaletteItem {
  PaletteItem({required this.title, required this.subtitle, required this.icon, required this.run, this.keepOpen = false, this.leading});
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? leading;

  /// Runs when chosen. The palette has closed by then unless [keepOpen] is set.
  final VoidCallback run;
  final bool keepOpen;
}

/// What the palette may do to the rest of the app.
class PaletteActions {
  PaletteActions({required this.store, required this.openApp, required this.go, this.lock});
  final AppsStore store;
  final void Function(AppSummary app, {int tab}) openApp;
  final void Function(int destination) go;
  final VoidCallback? lock;
}

Future<void> showCommandPalette(BuildContext context, PaletteActions actions) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, _) => Align(
      alignment: const Alignment(0, -0.45),
      child: _Palette(actions: actions),
    ),
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(anim), child: child),
    ),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.actions});
  final PaletteActions actions;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _query = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _onKey);
  final _scroll = ScrollController();
  List<AppSummary>? _apps;
  Object? _error;
  int _selected = 0;
  bool _pickingForUpload = false;
  List<PaletteItem> _items = const [];

  @override
  void initState() {
    super.initState();
    widget.actions.store.apps
        .then((a) {
          if (mounted) setState(() => _apps = a);
        })
        .catchError((Object e) {
          if (mounted) setState(() => _error = e);
        });
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _choose(_selected);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int d) {
    if (_items.isEmpty) return;
    setState(() => _selected = (_selected + d) % _items.length);
    final target = _selected * 52.0;
    if (_scroll.hasClients && (target < _scroll.offset || target > _scroll.offset + 52.0 * 6)) {
      _scroll.animateTo(
        (target - 52.0 * 3).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeOut,
      );
    }
  }

  void _choose(int i) {
    if (i < 0 || i >= _items.length) return;
    final item = _items[i];
    if (!item.keepOpen) Navigator.of(context).pop();
    item.run();
  }

  List<PaletteItem> _build() {
    final a = widget.actions;
    final apps = _apps ?? const <AppSummary>[];
    PaletteItem appItem(AppSummary s, {int tab = 0, String? verb}) => PaletteItem(
      title: s.name,
      subtitle: verb ?? '${s.bundleId}  ·  ${prettyPlatform(s.platform)}${s.versionString == null ? '' : '  ·  v${s.versionString}'}',
      icon: Icons.apps,
      leading: AppSquircleIcon(name: s.name, platform: s.platform, size: 30),
      run: () => a.openApp(s, tab: tab),
    );
    final q = _query.text;

    if (_pickingForUpload) {
      final scored = [
        for (final s in apps)
          if (fuzzyScore(q, '${s.name} ${s.bundleId}') case final sc?) (sc, s),
      ]..sort((x, y) => y.$1.compareTo(x.$1));
      return [for (final e in scored) appItem(e.$2, tab: 4, verb: 'Upload a build to ${e.$2.bundleId}')];
    }

    final actionsList = <PaletteItem>[
      PaletteItem(
        title: 'Upload New Build',
        subtitle: apps.length == 1 ? 'Opens ${apps.first.name} → Upload .IPA' : 'Choose an app, then pick the .ipa',
        icon: Icons.upload_file,
        keepOpen: apps.length != 1,
        run: () {
          if (apps.length == 1) return a.openApp(apps.first, tab: 4);
          setState(() {
            _pickingForUpload = true;
            _query.clear();
            _selected = 0;
          });
        },
      ),
      PaletteItem(title: 'Check Sales & Proceeds', subtitle: 'Sales & Trends', icon: Icons.bar_chart, run: () => a.go(1)),
      PaletteItem(title: 'Manage Team', subtitle: 'Users and Access', icon: Icons.group_outlined, run: () => a.go(3)),
      if (a.lock != null)
        PaletteItem(title: 'Lock Console', subtitle: 'Ask for your password or Touch ID again', icon: Icons.lock_outline, run: a.lock!),
    ];
    final scored = <(int, PaletteItem)>[
      for (final it in actionsList)
        if (fuzzyScore(q, it.title) case final sc?) (sc + 1, it),
      for (final s in apps)
        if (fuzzyScore(q, '${s.name} ${s.bundleId}') case final sc?) (sc, appItem(s)),
    ];
    if (q.trim().isNotEmpty) scored.sort((x, y) => y.$1.compareTo(x.$1));
    return [for (final e in scored) e.$2];
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    _items = _build();
    if (_selected >= _items.length) _selected = _items.isEmpty ? 0 : _items.length - 1;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 460),
        decoration: BoxDecoration(
          color: k.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: k.line),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(_pickingForUpload ? Icons.upload_file : Icons.search, size: 20, color: k.muted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      onChanged: (_) => setState(() => _selected = 0),
                      style: const TextStyle(fontSize: 16),
                      decoration: InputDecoration(
                        hintText: _pickingForUpload ? 'Upload to which app?' : 'Search apps, or type an action',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  if (_pickingForUpload) TextButton(onPressed: () => setState(() => _pickingForUpload = false), child: const Text('Back')),
                ],
              ),
            ),
            Divider(color: k.line),
            Flexible(
              child: _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load apps: $_error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    )
                  : _apps == null && _items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text('Nothing matches “${_query.text}”.', style: TextStyle(color: k.muted)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(6),
                      itemExtent: 52,
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        final on = i == _selected;
                        return Material(
                          color: on ? k.accentSoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          child: MergeSemantics(
                            child: Semantics(
                              button: true,
                              selected: on,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => _choose(i),
                                onHover: (h) {
                                  if (h && _selected != i) setState(() => _selected = i);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  child: Row(
                                    children: [
                                      it.leading ??
                                          Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(color: k.inset, borderRadius: BorderRadius.circular(8)),
                                            child: Icon(it.icon, size: 17, color: on ? k.accentInk : k.muted),
                                          ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              it.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontWeight: FontWeight.w600, color: on ? k.accentInk : null),
                                            ),
                                            Text(
                                              it.subtitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 12, color: k.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (on) Icon(Icons.keyboard_return, size: 15, color: k.accentInk),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Divider(color: k.line),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                children: [
                  Text('↑↓ navigate     ⏎ open     esc close', style: TextStyle(fontSize: 11.5, color: k.muted)),
                  const Spacer(),
                  Text(
                    _apps == null ? 'Loading apps…' : '${_apps!.length} app${_apps!.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 11.5, color: k.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
