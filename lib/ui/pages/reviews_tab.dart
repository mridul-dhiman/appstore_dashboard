import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/reviews.dart';
import '../theme.dart';
import '../../state/reply_templates.dart';
import '../widgets.dart';

/// Customer reviews of one app: rating breakdown, filters, and replying as the developer.
class ReviewsTab extends StatefulWidget {
  const ReviewsTab({super.key, required this.client, required this.appId, this.onLoaded, this.templates});
  final AscClient client;
  final String appId;

  /// This client's reply templates. Null: the defaults, not saved.
  final ReplyTemplates? templates;

  /// Gives the page what was loaded, so Export can reuse it instead of asking Apple again.
  final void Function(ReviewsData data)? onLoaded;

  @override
  State<ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<ReviewsTab> {
  final _reload = ReloadController();
  late final _fallbackTemplates = ReplyTemplates();
  ReplyTemplates get _templates => widget.templates ?? _fallbackTemplates;

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<ReviewsData>(
      controller: _reload,
      load: () async {
        final d = await loadReviews(widget.client, widget.appId);
        widget.onLoaded?.call(d);
        return d;
      },
      builder: (context, d) {
        if (d.reviews.isEmpty) return const EmptyView('No customer reviews yet.', icon: Icons.rate_review_outlined);
        return _ReviewsBody(client: widget.client, data: d, onRefresh: _reload.reload, templates: _templates);
      },
    );
  }
}

class _ReviewsBody extends StatefulWidget {
  const _ReviewsBody({required this.client, required this.data, required this.onRefresh, required this.templates});
  final AscClient client;
  final ReplyTemplates templates;
  final ReviewsData data;
  final VoidCallback onRefresh;

  @override
  State<_ReviewsBody> createState() => _ReviewsBodyState();
}

class _ReviewsBodyState extends State<_ReviewsBody> {
  late List<Review> _reviews = [...widget.data.reviews];
  final _search = TextEditingController();
  ReviewFilter _filter = ReviewFilter.all;
  int? _stars;
  String? _composing; // review id whose composer is open

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  ReviewsData get _data => ReviewsData(_reviews, widget.data.total);

  void _replace(String id, Review Function(Review) change) => setState(() => _reviews = [for (final r in _reviews) r.id == id ? change(r) : r]);

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final d = _data;
    final shown = filterReviews(_reviews, _filter, stars: _stars, query: _search.text);
    final needs = filterReviews(_reviews, ReviewFilter.needsReply).length;
    return ListView(padding: const EdgeInsets.fromLTRB(40, 8, 40, 40), children: [
      _Breakdown(data: d, stars: _stars, onStars: (s) => setState(() => _stars = _stars == s ? null : s)),
      const SizedBox(height: 18),
      Row(children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'Search reviews', prefixIcon: Icon(Icons.search, size: 18)),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in ReviewFilter.values)
              _Pill(
                label: f.label,
                count: switch (f) {
                  ReviewFilter.all => _reviews.length,
                  ReviewFilter.needsReply => needs,
                  ReviewFilter.unanswered => d.unansweredCount,
                },
                on: f == _filter,
                onTap: () => setState(() => _filter = f),
              ),
          ]),
        ),
        IconButton(tooltip: 'Refresh', onPressed: widget.onRefresh, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 14),
      if (shown.isEmpty)
        const Padding(padding: EdgeInsets.only(top: 50), child: EmptyView('No reviews match.', icon: Icons.search_off))
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) Divider(color: k.line),
              _ReviewTile(
                templates: widget.templates,
                key: ValueKey(shown[i].id),
                client: widget.client,
                review: shown[i],
                composing: _composing == shown[i].id,
                onCompose: (open) => setState(() => _composing = open ? shown[i].id : null),
                onReplied: (res) => _replace(shown[i].id, (r) => r.withResponse(res)),
              ),
            ],
          ]),
        ),
      if (widget.data.total != null && widget.data.total! > _reviews.length)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text('Showing the latest ${_reviews.length} of ${widget.data.total}.', style: TextStyle(color: k.muted))),
    ]);
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.data, required this.stars, required this.onStars});
  final ReviewsData data;
  final int? stars;
  final ValueChanged<int> onStars;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final counts = data.counts;
    final n = data.reviews.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(children: [
          SizedBox(
            width: 170,
            child: Column(children: [
              Text(data.average.toStringAsFixed(1), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 1; i <= 5; i++) Icon(i <= data.average.round() ? Icons.star : Icons.star_border, size: 16, color: const Color(0xFFFF9F0A)),
              ]),
              const SizedBox(height: 6),
              Text('${fmtNum(data.total ?? n)} reviews', style: TextStyle(color: k.muted, fontSize: 13)),
              if (data.total != null && data.total! > n) Text('average of latest $n', style: TextStyle(color: k.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(children: [
              for (var i = 0; i < 5; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onStars(5 - i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                    child: Row(children: [
                      SizedBox(width: 14, child: Text('${5 - i}', style: TextStyle(fontWeight: stars == 5 - i ? FontWeight.w700 : FontWeight.w500))),
                      const Icon(Icons.star, size: 12, color: Color(0xFFFF9F0A)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: n == 0 ? 0 : counts[i] / n,
                            minHeight: 7,
                            backgroundColor: k.inset,
                            color: stars == null || stars == 5 - i ? k.accent : k.accent.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                      SizedBox(width: 40, child: Text('${counts[i]}', textAlign: TextAlign.end, style: TextStyle(color: k.muted, fontSize: 12.5))),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.count, required this.on, required this.onTap});
  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Material(
      color: on ? k.accentSoft : k.surface,
      shape: StadiumBorder(side: BorderSide(color: on ? k.accent.withValues(alpha: 0.5) : k.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? k.accentInk : k.body)),
            const SizedBox(width: 7),
            Text('$count', style: TextStyle(fontSize: 12, color: on ? k.accentInk : k.muted)),
          ]),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatefulWidget {
  const _ReviewTile({super.key, required this.client, required this.review, required this.composing, required this.onCompose, required this.onReplied, required this.templates});
  final AscClient client;
  final ReplyTemplates templates;
  final Review review;
  final bool composing;
  final ValueChanged<bool> onCompose;
  final ValueChanged<dynamic> onReplied; // the new response resource, or null after deleting

  @override
  State<_ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<_ReviewTile> {
  late final _text = TextEditingController(text: widget.review.replyText ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final r = widget.review;
    final problem = replyProblem(_text.text);
    if (problem != null) return setState(() => _error = problem);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Post this reply to the App Store?'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Replying to ${r.nickname}', style: TextStyle(color: Tokens.of(ctx).muted)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Tokens.of(ctx).inset, borderRadius: BorderRadius.circular(8)),
              child: SelectableText(_text.text.trim()),
            ),
            const SizedBox(height: 10),
            Text(r.answered ? 'This replaces your earlier reply. The reviewer and everyone on the App Store can see it.' : 'The reviewer and everyone on the App Store can see it.', style: TextStyle(color: Tokens.of(ctx).muted, fontSize: 13)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Post reply')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await postReviewResponse(widget.client, r.id, _text.text);
      if (!mounted) return;
      setState(() => _busy = false);
      widget.onCompose(false);
      widget.onReplied(res);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reply sent. Apple may take a little while to show it on the App Store.')));
    } on AscException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _delete() async {
    final res = widget.review.response;
    if (res == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your reply?'),
        content: const Text('It is removed from the App Store. You can write a new one afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete reply')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await deleteReviewResponse(widget.client, res.id);
      if (!mounted) return;
      setState(() => _busy = false);
      _text.clear();
      widget.onReplied(null);
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
    final k = Tokens.of(context);
    final r = widget.review;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 1; i <= 5; i++) Icon(i <= r.rating ? Icons.star : Icons.star_border, size: 16, color: const Color(0xFFFF9F0A)),
          const SizedBox(width: 10),
          Expanded(child: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5), overflow: TextOverflow.ellipsis)),
          Text('${fmtDate(r.created)}  ·  ${r.nickname}${r.territory.isEmpty ? '' : '  ·  ${r.territory}'}', style: TextStyle(color: k.muted, fontSize: 12.5)),
        ]),
        const SizedBox(height: 8),
        SelectableText(r.body, style: TextStyle(color: k.body, height: 1.4)),
        if (r.answered && !widget.composing) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.reply, size: 15, color: k.accentInk),
                const SizedBox(width: 6),
                Text('Your response', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: k.accentInk)),
                if (r.replyPending) ...[const SizedBox(width: 8), const StateChip('PENDING', label: 'Publishing')],
                const Spacer(),
                TextButton(onPressed: _busy ? null : () => widget.onCompose(true), child: const Text('Edit')),
                TextButton(onPressed: _busy ? null : _delete, child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ]),
              SelectableText(r.replyText ?? '', style: TextStyle(color: k.body, height: 1.4)),
            ]),
          ),
        ],
        if (!r.answered && !widget.composing)
          Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton.icon(onPressed: () => widget.onCompose(true), icon: const Icon(Icons.reply, size: 16), label: const Text('Reply'))),
        if (widget.composing) ...[
          const SizedBox(height: 14),
          ListenableBuilder(
            listenable: widget.templates,
            builder: (context, _) => Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in widget.templates.items.entries)
                ActionChip(
                  label: Text(e.key),
                  onPressed: _busy ? null : () => setState(() => _text.text = fillTemplate(e.value, r.nickname)),
                ),
              ActionChip(
                avatar: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit templates'),
                onPressed: _busy ? null : () => showDialog<void>(context: context, builder: (_) => TemplatesDialog(templates: widget.templates)),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _text,
            minLines: 4,
            maxLines: 10,
            maxLength: maxReplyLength,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(hintText: 'Write a public reply to ${r.nickname}', helperText: 'Replies are public and attributed to your app.'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 10),
          Row(children: [
            FilledButton(
              onPressed: _busy ? null : _post,
              child: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Post Reply to App Store'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _busy ? null : () => widget.onCompose(false), child: const Text('Cancel')),
          ]),
        ],
      ]),
    );
  }
}

/// Add, rename, rewrite or remove this client's reply templates. `{name}` becomes the reviewer's nickname.
class TemplatesDialog extends StatefulWidget {
  const TemplatesDialog({super.key, required this.templates});
  final ReplyTemplates templates;

  @override
  State<TemplatesDialog> createState() => _TemplatesDialogState();
}

class _TemplatesDialogState extends State<TemplatesDialog> {
  late final _rows = [
    for (final e in widget.templates.items.entries) (TextEditingController(text: e.key), TextEditingController(text: e.value)),
  ];

  @override
  void dispose() {
    for (final (a, b) in _rows) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reply templates'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Write {name} where the reviewer\'s nickname should go. Saved on this Mac for this client.'),
            const SizedBox(height: 14),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 150, child: TextField(controller: _rows[i].$1, decoration: const InputDecoration(labelText: 'Name'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _rows[i].$2, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Reply'))),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => setState(() {
                      final (a, b) = _rows.removeAt(i);
                      a.dispose();
                      b.dispose();
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ]),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add((TextEditingController(), TextEditingController(text: 'Hi {name}, ')))),
              icon: const Icon(Icons.add),
              label: const Text('Add template'),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            await widget.templates.save({for (final (a, b) in _rows) a.text: b.text});
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
