import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/listing_draft.dart';
import '../../api/text_diff.dart';

enum _Phase { review, applying, done }

/// Review every staged change, then apply them all. Closes with `true` if anything was changed on the server.
class ChangelistDialog extends StatefulWidget {
  const ChangelistDialog({super.key, required this.draft, required this.client});
  final ListingDraft draft;
  final AscClient client;

  @override
  State<ChangelistDialog> createState() => _ChangelistDialogState();
}

class _ChangelistDialogState extends State<ChangelistDialog> {
  _Phase _phase = _Phase.review;
  String _step = '';
  List<ApplyResult> _results = const [];

  Future<void> _apply() async {
    final n = widget.draft.count;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apply $n change${n == 1 ? '' : 's'}?'),
        content: const Text(
          'This updates your App Store Connect listing right now. Text and screenshots can be edited again afterwards, but a deleted screenshot cannot be restored.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _phase = _Phase.applying);
    final results = await widget.draft.apply(
      widget.client,
      onStep: (s) {
        if (mounted) setState(() => _step = s);
      },
    );
    if (mounted) {
      setState(() {
        _results = results;
        _phase = _Phase.done;
      });
    }
  }

  Widget _diff(Change c) {
    final t = Theme.of(context);
    final before = c.before ?? '', after = c.after ?? '';
    final multiline = before.contains('\n') || after.contains('\n') || before.length > 70 || after.length > 70;
    if (!multiline) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text(
            before.isEmpty ? '(empty)' : before,
            style: TextStyle(color: t.colorScheme.error, decoration: TextDecoration.lineThrough),
          ),
          const Icon(Icons.arrow_forward, size: 14),
          Text(
            after.isEmpty ? '(empty)' : after,
            style: const TextStyle(color: Color(0xFF1F8F45), fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    final d = diffLines(before, after);
    final stats = diffStats(d);
    final shown = d.where((l) => l.op != ' ').take(40).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '+${stats.added} −${stats.removed} lines · ${before.length} → ${after.length} characters',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        for (final l in shown)
          Container(
            width: double.infinity,
            color: l.op == '+' ? const Color(0x2230B35A) : const Color(0x22E5484D),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text('${l.op} ${l.text.isEmpty ? '(blank line)' : l.text}', style: const TextStyle(fontFamily: 'Menlo', fontSize: 12)),
          ),
        if (d.where((l) => l.op != ' ').length > shown.length)
          Text('… and ${d.where((l) => l.op != ' ').length - shown.length} more changed lines', style: t.textTheme.bodySmall),
      ],
    );
  }

  Widget _row(Change c) {
    final t = Theme.of(context);
    final icon = switch (c.kind) {
      ChangeKind.text => Icons.edit_outlined,
      ChangeKind.shotAdd => Icons.add_photo_alternate_outlined,
      ChangeKind.shotDelete => Icons.delete_outline,
      ChangeKind.shotOrder => Icons.swap_horiz,
      ChangeKind.shotSet => Icons.collections_outlined,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.kind == ChangeKind.shotDelete ? t.colorScheme.error : t.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (c.kind == ChangeKind.text) Padding(padding: const EdgeInsets.only(top: 4), child: _diff(c)),
                if (c.kind == ChangeKind.shotAdd && c.preview != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(c.preview!, height: 64, errorBuilder: (_, _, _) => const SizedBox(height: 64, width: 40)),
                        ),
                        const SizedBox(width: 10),
                        Text(c.detail ?? '', style: t.textTheme.bodySmall),
                      ],
                    ),
                  ),
                if (c.kind != ChangeKind.text && c.kind != ChangeKind.shotAdd && c.detail != null)
                  Text(c.detail!, style: t.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.draft,
      builder: (context, _) {
        final changes = widget.draft.changes();
        final byLocale = <String, List<Change>>{};
        for (final c in changes) {
          (byLocale[c.locale] ??= []).add(c);
        }
        final okCount = _results.where((r) => r.ok).length;
        return AlertDialog(
          title: Text(switch (_phase) {
            _Phase.review => 'Changelist · ${changes.length} change${changes.length == 1 ? '' : 's'}',
            _Phase.applying => 'Applying…',
            _Phase.done => 'Applied $okCount of ${_results.length}',
          }),
          content: SizedBox(
            width: 720,
            height: 520,
            child: switch (_phase) {
              _Phase.applying => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_step, textAlign: TextAlign.center),
                ],
              ),
              _Phase.done => ListView(
                children: [
                  for (final r in _results)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        r.ok ? Icons.check_circle : Icons.error_outline,
                        color: r.ok ? const Color(0xFF1F8F45) : t.colorScheme.error,
                      ),
                      title: Text(r.title),
                      subtitle: r.ok ? null : SelectableText(r.error!, style: TextStyle(color: t.colorScheme.error)),
                    ),
                  if (_results.any((r) => !r.ok))
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Failed text edits are still staged so you can retry. Screenshot sets are reloaded from App Store Connect, so check what actually changed.',
                      ),
                    ),
                ],
              ),
              _Phase.review =>
                changes.isEmpty
                    ? const Center(child: Text('Nothing to apply.'))
                    : ListView(
                        children: [
                          for (final e in byLocale.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 2),
                              child: Text(
                                e.key,
                                style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.primary),
                              ),
                            ),
                            const Divider(),
                            for (final c in e.value) _row(c),
                          ],
                        ],
                      ),
            },
          ),
          actions: switch (_phase) {
            _Phase.review => [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Close')),
              TextButton(
                onPressed: changes.isEmpty
                    ? null
                    : () {
                        widget.draft.discard();
                        Navigator.pop(context, false);
                      },
                child: const Text('Discard all'),
              ),
              FilledButton(onPressed: changes.isEmpty ? null : _apply, child: Text('Apply ${changes.length}')),
            ],
            _Phase.applying => const [],
            _Phase.done => [FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Close'))],
          },
        );
      },
    );
  }
}
