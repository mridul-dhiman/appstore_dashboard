import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../services/window.dart';
import 'theme.dart';

String fmtDate(DateTime? d) => d == null ? '—' : DateFormat.yMMMd().format(d);
String fmtDateTime(DateTime? d) => d == null ? '—' : DateFormat.yMMMd().add_jm().format(d);
String fmtNum(num n) => NumberFormat.decimalPattern().format(n);

/// `IOS` → `iOS`, `MAC_OS` → `macOS`.
String prettyPlatform(String? s) => switch (s) {
  'IOS' => 'iOS',
  'MAC_OS' => 'macOS',
  'TV_OS' => 'tvOS',
  'VISION_OS' => 'visionOS',
  'UNIVERSAL' => 'Universal',
  _ => prettyEnum(s),
};

/// `READY_FOR_SALE` → `Ready for sale`.
String prettyEnum(String? s) {
  if (s == null || s.isEmpty) return '—';
  final t = s.replaceAll('_', ' ').toLowerCase();
  return t[0].toUpperCase() + t.substring(1);
}

/// "Showing the first 100 builds" when Apple had more than was loaded ([page] still has a `next` link). Nothing otherwise.
class TruncatedNote extends StatelessWidget {
  const TruncatedNote(this.page, this.noun, {super.key});
  final ResourcePage page;
  final String noun;

  @override
  Widget build(BuildContext context) {
    if (page.next == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        'Showing the first ${page.data.length} $noun. There are more in App Store Connect.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
      ),
    );
  }
}

/// Lets a page header trigger a reload of the [LoadView] below it.
class ReloadController extends ChangeNotifier {
  void reload() => notifyListeners();
}

/// Runs [load], shows a spinner, an error with Try again, or [builder] with the result.
class LoadView<T> extends StatefulWidget {
  const LoadView({super.key, required this.load, required this.builder, this.controller});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final ReloadController? controller;

  @override
  State<LoadView<T>> createState() => _LoadViewState<T>();
}

class _LoadViewState<T> extends State<LoadView<T>> with AutomaticKeepAliveClientMixin {
  // Last good result. A reload keeps it on screen (with a thin progress bar) instead of blanking the page.
  T? _data;
  bool _hasData = false;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  /// Inside a tab view, keeps the page (and what it loaded) alive when another tab is shown, so coming back does not
  /// fetch it all again. Refresh still reloads.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_reload);
    _run();
  }

  @override
  void didUpdateWidget(covariant LoadView<T> old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_reload);
      widget.controller?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_reload);
    super.dispose();
  }

  void _reload() => _run();

  Future<void> _run() async {
    final gen = ++_generation; // a newer load wins over a slower older one
    final future = widget.load();
    if (mounted) setState(() => _loading = true);
    try {
      final data = await future;
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = data;
        _hasData = true;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_hasData) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return ErrorView(error: _error!, onRetry: _reload);
    }
    final cs = Theme.of(context).colorScheme;
    final bar = _error != null && !_loading
        ? Material(
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_outlined, size: 16, color: cs.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Could not refresh: $_error',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 12.5),
                    ),
                  ),
                  TextButton(onPressed: _reload, child: const Text('Try again')),
                ],
              ),
            ),
          )
        : null;
    // Same 2 px either way, so the content does not jump when a reload starts or ends.
    final progress = SizedBox(height: 2, child: _loading ? const LinearProgressIndicator(minHeight: 2) : null);
    return LayoutBuilder(
      builder: (context, c) {
        final page = widget.builder(context, _data as T);
        // A page that fills its space keeps filling it; one placed in an unbounded height (a scroll view) keeps its own.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: c.hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            progress,
            ?bar,
            if (c.hasBoundedHeight) Expanded(child: page) else page,
          ],
        );
      },
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 40, color: cs.error),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: muted),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

enum Tone { good, warn, bad, neutral }

Tone toneFor(String? state) {
  final s = (state ?? '').toUpperCase();
  if (s.isEmpty) return Tone.neutral;
  if (RegExp(r'REJECT|INVALID|FAIL|EXPIRED|REVOKED|REMOVED|DEVELOPER_REMOVED|DISABLED|MISSING').hasMatch(s)) return Tone.bad;
  if (RegExp(r'REVIEW|WAITING|PROCESSING|PENDING|PREPARE|METADATA|UPLOAD|SUBMIT').hasMatch(s)) return Tone.warn;
  if (RegExp(r'READY|VALID|ACCEPT|APPROVED|ACTIVE|ENABLED|LIVE|DISTRIBUTION').hasMatch(s)) return Tone.good;
  return Tone.neutral;
}

class StateChip extends StatelessWidget {
  const StateChip(this.state, {super.key, this.label});
  final String? state;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (bg, fg) = _badgeColors(toneFor(state), dark);
    // A Row (not `alignment:`) so the chip hugs its text instead of stretching to the width it is offered.
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label ?? prettyEnum(state),
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Title row at the top of a page, with an optional reload button.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.reload, this.actions = const []});
  final String title;
  final String? subtitle;
  final ReloadController? reload;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 30, 40, 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 26, letterSpacing: -0.5)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          ...actions,
          if (reload != null) IconButton(tooltip: 'Refresh', onPressed: reload!.reload, icon: const Icon(Icons.refresh)),
        ],
      ),
    );
  }
}

/// A rounded card holding rows separated by dividers.
class RowsCard extends StatelessWidget {
  const RowsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(), children[i]],
        ],
      ),
    );
  }
}

class Stat extends StatelessWidget {
  const Stat({super.key, required this.label, required this.value, this.icon, this.tone});
  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: tone ?? t.colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round initials badge; the colour is picked from the name so a person keeps theirs everywhere.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.size = 36, this.color});
  final String name;
  final double size;
  final (Color, Color)? color;

  static const _light = [
    (Color(0xFFEAF0FF), Color(0xFF1F44C4)),
    (Color(0xFFE6F4EC), Color(0xFF14693E)),
    (Color(0xFFFFF1D6), Color(0xFF7A4E00)),
    (Color(0xFFF3E8FF), Color(0xFF6B2FB3)),
    (Color(0xFFFDECEA), Color(0xFF9C211A)),
  ];

  static String initials(String name) {
    final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).toList();
    return w.isEmpty ? '?' : w.map((x) => x.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pick = color ?? _light[(name.isEmpty ? 0 : name.codeUnitAt(0) + name.length) % _light.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: dark ? pick.$2.withValues(alpha: 0.22) : pick.$1),
      child: Text(
        initials(name),
        style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: dark ? pick.$1 : pick.$2),
      ),
    );
  }
}

/// Small uppercase label above a list or group.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(4, 0, 4, 8)});
  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Debounce helper for search boxes.
class Debouncer {
  Debouncer([this.delay = const Duration(milliseconds: 250)]);
  final Duration delay;
  Timer? _t;
  void run(VoidCallback f) {
    _t?.cancel();
    _t = Timer(delay, f);
  }

  void dispose() => _t?.cancel();
}

(Color, Color) _badgeColors(Tone tone, bool dark) => switch (tone) {
  Tone.good => dark ? (const Color(0x2410B981), const Color(0xFF34D399)) : (const Color(0xFFE4F7EA), const Color(0xFF13773B)),
  Tone.warn => dark ? (const Color(0x24F59E0B), const Color(0xFFFBBF24)) : (const Color(0xFFFFF4E5), const Color(0xFF9A5B00)),
  Tone.bad => dark ? (const Color(0x24F43F5E), const Color(0xFFFB7185)) : (const Color(0xFFFFEBEE), const Color(0xFFB4232C)),
  Tone.neutral => dark ? (const Color(0xFF232832), const Color(0xFFC3CAD6)) : (const Color(0xFFEEF0F4), const Color(0xFF3A3A3C)),
};

/// A status pill with a live dot: green for ready for sale, amber while in review, red for rejected, grey otherwise.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.state, {super.key, this.label});
  final String? state;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tone = toneFor(state);
    final (bg, fg) = _badgeColors(tone, dark);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg,
              boxShadow: dark && tone != Tone.neutral ? [BoxShadow(color: fg.withValues(alpha: 0.7), blurRadius: 6)] : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label ?? prettyEnum(state),
            style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

IconData platformIcon(String? platform) => switch (platform) {
  'MAC_OS' => Icons.laptop_mac,
  'TV_OS' => Icons.tv,
  'VISION_OS' => Icons.vrpano_outlined,
  _ => Icons.phone_iphone,
};

/// App icon stand-in: a squircle with a gradient picked from the app's name and the platform glyph in the corner. The
/// real icon needs a request per app, which the Apps list deliberately avoids.
class AppSquircleIcon extends StatelessWidget {
  const AppSquircleIcon({super.key, required this.name, this.platform, this.size = 48, this.imageUrl});
  final String name;
  final String? platform;
  final double size;

  /// The real icon. While it loads, or if it fails, the initials tile shows instead.
  final String? imageUrl;

  static const _gradients = [
    (Color(0xFF5AC8FA), Color(0xFF0A84FF)),
    (Color(0xFFFF9F0A), Color(0xFFFF375F)),
    (Color(0xFF30D158), Color(0xFF0A9396)),
    (Color(0xFFBF5AF2), Color(0xFF5E5CE6)),
    (Color(0xFFFFD60A), Color(0xFFFF9F0A)),
  ];

  @override
  Widget build(BuildContext context) {
    final seed = name.isEmpty ? 0 : name.codeUnits.fold<int>(0, (a, b) => a + b);
    final g = _gradients[seed % _gradients.length];
    final shape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(size * 0.28));
    final tile = _tile(g, shape);
    if (imageUrl == null) return tile;
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: shape,
        shadows: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          frameBuilder: (context, child, frame, _) => frame == null ? tile : child,
          errorBuilder: (_, _, _) => tile,
        ),
      ),
    );
  }

  Widget _tile((Color, Color) g, ShapeBorder shape) {
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: shape,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [g.$1, g.$2]),
        shadows: const [BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              Avatar.initials(name).characters.first,
              style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: FontWeight.w700),
            ),
          ),
          Positioned(
            right: size * 0.07,
            bottom: size * 0.07,
            child: Icon(platformIcon(platform), size: size * 0.24, color: Colors.white.withValues(alpha: 0.85)),
          ),
        ],
      ),
    );
  }
}

/// The window's top bar: drag area, a search box that opens the command palette (⌘K), and the light/dark switch. On macOS it
/// leaves room for the traffic-light buttons that float over its left end.
class MacTitleBar extends StatelessWidget {
  const MacTitleBar({super.key, required this.onSearch, required this.themeMode, required this.onToggleTheme, this.title});
  final VoidCallback onSearch;
  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final String? title;

  static bool get _isMac => defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = _isMac && !kIsWeb ? '⌘K' : 'Ctrl K';
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => MacWindow.startDrag(),
      onDoubleTap: MacWindow.zoom,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: k.titlebar,
          border: Border(bottom: BorderSide(color: k.line)),
        ),
        padding: EdgeInsets.only(left: MacWindow.hasOverlayTrafficLights ? 84 : 20, right: 16),
        child: Row(
          children: [
            if (title != null)
              Text(
                title!,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: k.muted),
              ),
            const Spacer(),
            Tooltip(
              message: 'Search apps and actions',
              child: MergeSemantics(
                child: Semantics(
                  button: true,
                  label: 'Search apps and actions',
                  hint: 'Opens the command palette, $hint',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onSearch,
                    child: Container(
                      width: 340,
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: k.inset,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: k.line),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 16, color: k.muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Search apps and actions', style: TextStyle(color: k.muted, fontSize: 13)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: k.surface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: k.line),
                            ),
                            child: Text(
                              hint,
                              style: TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
              visualDensity: VisualDensity.compact,
              onPressed: onToggleTheme,
              icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, size: 19, color: k.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A macOS-style segmented tab strip: an inset track with a raised selected segment. Drives [controller].
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.controller, required this.labels});
  final TabController controller;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return AnimatedBuilder(
      animation: controller.animation!,
      builder: (context, _) {
        final current = controller.animation!.value.round();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: k.inset,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: k.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < labels.length; i++)
                  Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                    child: Material(
                      color: i == current ? k.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      elevation: 0,
                      child: MergeSemantics(
                        child: Semantics(
                          button: true,
                          selected: i == current,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => controller.animateTo(i),
                            child: Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              alignment: Alignment.center,
                              decoration: i == current
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: k.line),
                                      boxShadow: k.shadow,
                                    )
                                  : null,
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: i == current ? FontWeight.w600 : FontWeight.w500,
                                  color: i == current ? k.ink : k.muted,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Asks for one line of text. Returns it, or null on Cancel. The text field's controller is disposed with the dialog.
Future<String?> askText(BuildContext context, {required String title, required String label, String initial = '', String? helper}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(title: title, label: label, initial: initial, helper: helper),
    );

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({required this.title, required this.label, required this.initial, this.helper});
  final String title;
  final String label;
  final String initial;
  final String? helper;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      decoration: InputDecoration(labelText: widget.label, helperText: widget.helper),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}
