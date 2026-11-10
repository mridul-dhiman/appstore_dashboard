import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

class _LoadViewState<T> extends State<LoadView<T>> {
  late Future<T> _future = widget.load();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_reload);
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

  void _reload() {
    final next = widget.load();
    setState(() {
      _future = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
        return widget.builder(context, snap.requireData);
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: cs.error),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
            ],
          ]),
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
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: muted),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: muted)),
        ]),
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
    final (bg, fg) = switch (toneFor(state)) {
      Tone.good => dark ? (const Color(0xFF16301F), const Color(0xFF7BD79B)) : (const Color(0xFFE6F4EC), const Color(0xFF14693E)),
      Tone.warn => dark ? (const Color(0xFF3A2C0E), const Color(0xFFF2C46B)) : (const Color(0xFFFFF1D6), const Color(0xFF7A4E00)),
      Tone.bad => dark ? (const Color(0xFF3A1714), const Color(0xFFF3A19B)) : (const Color(0xFFFDECEA), const Color(0xFF9C211A)),
      Tone.neutral => dark ? (const Color(0xFF232832), const Color(0xFFC3CAD6)) : (const Color(0xFFEEF0F4), const Color(0xFF3A4250)),
    };
    // A Row (not `alignment:`) so the chip hugs its text instead of stretching to the width it is offered.
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Text(label ?? prettyEnum(state), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600))],
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
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 26, letterSpacing: -0.5)),
            if (subtitle != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          ]),
        ),
        ...actions,
        if (reload != null) IconButton(tooltip: 'Refresh', onPressed: reload!.reload, icon: const Icon(Icons.refresh)),
      ]),
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
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(), children[i]],
      ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: tone ?? t.colorScheme.onSurface)),
        ]),
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
      child: Text(initials(name), style: TextStyle(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: dark ? pick.$1 : pick.$2)),
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
      child: Text(text.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
