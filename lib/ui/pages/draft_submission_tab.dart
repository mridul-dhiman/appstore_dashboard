import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/draft_submission.dart';
import '../../api/models.dart';
import '../../api/submission.dart';
import '../theme.dart';
import '../widgets.dart';

const _platforms = {'IOS': 'iOS', 'MAC_OS': 'macOS', 'TV_OS': 'tvOS', 'VISION_OS': 'visionOS'};

/// App Store Connect's draft submission: one per platform, holding the version, in-app events and custom product pages
/// that go to App Review together. Items are added and removed on Apple's side straight away; nothing is reviewed
/// until Submit.
class DraftSubmissionTab extends StatefulWidget {
  const DraftSubmissionTab({super.key, required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  State<DraftSubmissionTab> createState() => _DraftSubmissionTabState();
}

class _DraftSubmissionTabState extends State<DraftSubmissionTab> {
  final _reload = ReloadController();
  String _platform = 'IOS';

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LoadView<DraftOverview>(
    key: ValueKey(_platform),
    controller: _reload,
    load: () => loadDraftOverview(widget.client, widget.appId, platform: _platform),
    builder: (context, d) => _DraftBody(
      client: widget.client,
      appId: widget.appId,
      data: d,
      onReload: _reload.reload,
      onPlatform: (p) => setState(() => _platform = p),
    ),
  );
}

class _DraftBody extends StatefulWidget {
  const _DraftBody({required this.client, required this.appId, required this.data, required this.onReload, required this.onPlatform});
  final AscClient client;
  final String appId;
  final DraftOverview data;
  final VoidCallback onReload;
  final ValueChanged<String> onPlatform;

  @override
  State<_DraftBody> createState() => _DraftBodyState();
}

class _DraftBodyState extends State<_DraftBody> {
  final _picked = <String>{};
  bool _busy = false;
  bool _showAllHistory = false;
  final _addKey = GlobalKey();

  DraftOverview get d => widget.data;
  DraftActions get _actions => DraftActions(widget.client, widget.appId);
  String get _platformLabel => _platforms[d.platform] ?? d.platform;

  @override
  void didUpdateWidget(_DraftBody old) {
    super.didUpdateWidget(old);
    _picked.removeWhere((id) => !d.addable.any((e) => e.targetId == id));
  }

  Future<void> _run(String done, Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    } on AscException catch (e) {
      if (mounted) await _alert('App Store Connect said no', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onReload();
    }
  }

  Future<void> _addPicked() async {
    final entries = [for (final e in d.addable) if (_picked.contains(e.targetId)) e];
    if (entries.isEmpty) return;
    if (d.draft == null) {
      final ok = await _confirm(
        'Create a draft?',
        'This creates a $_platformLabel draft submission in App Store Connect and adds ${entries.length} '
            'item${entries.length == 1 ? '' : 's'} to it. Nothing goes to App Review until you submit.',
        'Create and add',
      );
      if (!ok) return;
    }
    await _run('Added ${entries.length} item${entries.length == 1 ? '' : 's'} to the draft.', () async {
      final id = d.draft?.id ?? await _actions.create(d.platform);
      for (final e in entries) {
        await _actions.add(id, e);
        _picked.remove(e.targetId);
      }
    });
  }

  Future<void> _remove(DraftEntry e) => _run('Removed ${e.name} from the draft.', () => _actions.remove(e));

  Future<void> _submitIap(DraftEntry e) async {
    final ok = await _confirm(
      'Submit ${e.name}?',
      'In-app purchases go to App Review through their own submission, not the draft. If this is the app\'s first '
          'in-app purchase, Apple holds it until the next app version is submitted.',
      'Submit',
    );
    if (ok) await _run('${e.name} submitted for review.', () => _actions.submitInAppPurchase(e.targetId));
  }

  Future<void> _submit() async {
    final items = d.items;
    final ok = await _confirm(
      'Submit to App Review?',
      'These ${items.length} item${items.length == 1 ? '' : 's'} go to App Review together:\n\n'
          '${items.map((i) => '•  ${i.title}').join('\n')}\n\nYou can remove items until review starts.',
      'Submit',
    );
    if (ok) await _run('Submitted to App Review.', () => _actions.submit(d.draft!.id));
  }

  Future<void> _cancel() async {
    final ok = await _confirm(
      'Cancel this draft?',
      'The draft and its item list are discarded in App Store Connect. The versions, events and pages themselves are kept.',
      'Cancel draft',
      danger: true,
    );
    if (ok) await _run('Draft cancelled.', () => _actions.cancel(d.draft!.id));
  }

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async {
    final k = Tokens.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title),
            content: SizedBox(width: 440, child: Text(body)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Back')),
              FilledButton(
                style: danger ? FilledButton.styleFrom(backgroundColor: k.bad) : null,
                onPressed: () => Navigator.pop(c, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _alert(String title, String body) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 440, child: SelectableText(body)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final left = [_itemsCard(), const SizedBox(height: 20), _addCard()];
    final right = [_summaryCard(), const SizedBox(height: 20), if (_versionItem != null) ...[_PreflightCard(client: widget.client, appId: widget.appId, version: _versionItem!, hasPriorVersion: d.versionCount > 1), const SizedBox(height: 20)]];
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 4, 40, 40),
      children: [
        _header(),
        if (d.unresolved != null) ...[
          const SizedBox(height: 16),
          _Note(
            icon: Icons.error_outline,
            color: k.bad,
            fill: k.badSoft,
            text:
                'A $_platformLabel submission has unresolved issues from App Review. Apple accepts no new submission until it is '
                'resubmitted: fix it in App Review Preflight.',
          ),
        ] else if (d.open.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Note(
            icon: Icons.hourglass_top,
            color: k.accentInk,
            fill: k.accentSoft,
            text: 'A $_platformLabel submission is ${prettyState(d.open.first.state)}. You can still prepare the next draft.',
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 980
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: left)),
                    const SizedBox(width: 20),
                    SizedBox(width: 340, child: Column(children: right)),
                  ],
                )
              : Column(children: [...left, const SizedBox(height: 20), ...right]),
        ),
        if (d.open.isNotEmpty) ...[const SizedBox(height: 20), _withReviewCard()],
        const SizedBox(height: 20),
        _historyCard(),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Submitting sends every item to App Review together. You can remove items until review starts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: k.muted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Resource? get _versionItem => d.items.where((i) => i.kind == DraftItemKind.version).firstOrNull?.target;

  Widget _header() {
    final k = Tokens.of(context);
    final draft = d.draft;
    final blocked = d.blocked.length;
    final canSubmit = !_busy && draft != null && d.items.isNotEmpty && blocked == 0 && d.unresolved == null;
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Draft submission · $_platformLabel',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: k.ink),
                ),
                if (draft != null) const StatusBadge('PREPARE', label: 'Draft') else const StatusBadge(null, label: 'No draft'),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(draft == null ? Icons.info_outline : Icons.cloud_off_outlined, size: 15, color: draft == null ? k.muted : k.warn),
                const SizedBox(width: 6),
                Text(
                  draft == null ? 'Add items below to start one' : 'Not sent to App Review yet',
                  style: TextStyle(color: draft == null ? k.muted : k.warn, fontSize: 13),
                ),
                const SizedBox(width: 14),
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: [for (final p in _platforms.entries) ButtonSegment(value: p.key, label: Text(p.value))],
                  selected: {d.platform},
                  onSelectionChanged: _busy ? null : (v) => widget.onPlatform(v.first),
                ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (draft != null)
                  TextButton(
                    onPressed: _busy ? null : _cancel,
                    style: TextButton.styleFrom(foregroundColor: k.bad),
                    child: const Text('Cancel draft'),
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => Scrollable.ensureVisible(_addKey.currentContext!, duration: const Duration(milliseconds: 300)),
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('Add items'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: canSubmit ? _submit : null,
                  icon: _busy
                      ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_outlined, size: 16),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Submit to App Review'),
                      if (d.items.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
                          child: Text('${d.items.length}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              blocked > 0 ? 'Fix or remove $blocked item${blocked == 1 ? '' : 's'} first' : 'One open submission per platform',
              style: TextStyle(color: blocked > 0 ? k.bad : k.muted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemsCard() {
    final k = Tokens.of(context);
    final head = TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5);
    Widget row(Widget item, Widget details, Widget status, Widget action) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(flex: 5, child: item),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: details),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(fit: BoxFit.scaleDown, child: status),
            ),
          ),
          SizedBox(width: 80, child: Align(alignment: Alignment.centerRight, child: action)),
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Text(
                  'Items in this submission',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: k.ink),
                ),
                const SizedBox(width: 8),
                StateChip(null, label: '${d.items.length}'),
              ],
            ),
          ),
          Divider(height: 1, color: k.line),
          if (d.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 32, color: k.muted),
                  const SizedBox(height: 10),
                  Text(
                    d.draft == null ? 'No draft submission for $_platformLabel.' : 'The draft is empty.',
                    style: TextStyle(color: k.ink, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Pick what goes to App Review under Add items.', style: TextStyle(color: k.muted)),
                ],
              ),
            )
          else ...[
            Container(
              color: k.inset,
              child: row(Text('ITEM', style: head), Text('DETAILS', style: head), Text('STATUS', style: head), const SizedBox()),
            ),
            for (final e in d.items) ...[
              Divider(height: 1, color: k.line),
              Container(
                color: e.ready ? null : Color.alphaBlend(k.badSoft.withValues(alpha: 0.5), k.surface),
                child: row(
                  Row(
                    children: [
                      _KindIcon(e.kind, bad: !e.ready),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          e.title,
                          style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.detail != null) Text(e.detail!, style: TextStyle(color: k.body, fontSize: 13)),
                      if (e.problem != null) Text(e.problem!, style: TextStyle(color: k.bad, fontSize: 12.5)),
                    ],
                  ),
                  e.ready
                      ? StatusBadge(e.state ?? e.itemState ?? 'READY')
                      : StatusBadge('REJECTED', label: 'Needs attention'),
                  e.kind == DraftItemKind.other
                      ? const SizedBox()
                      : TextButton(
                          onPressed: _busy ? null : () => _remove(e),
                          style: TextButton.styleFrom(foregroundColor: k.bad, visualDensity: VisualDensity.compact),
                          child: const Text('Remove'),
                        ),
                ),
              ),
            ],
          ],
          if (d.blocked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _Note(
                icon: Icons.error_outline,
                color: k.bad,
                fill: k.badSoft,
                text:
                    '${d.blocked.length} item${d.blocked.length == 1 ? ' needs' : 's need'} attention. Fix or remove '
                    '${d.blocked.length == 1 ? 'it' : 'them'} before submitting to App Review.',
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _Note(
              icon: Icons.info_outline,
              color: k.muted,
              fill: k.inset,
              text: 'In-app purchases and events can only be submitted with an app version the first time.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _addCard() {
    final k = Tokens.of(context);
    final groups = <DraftItemKind, List<DraftEntry>>{};
    for (final e in d.addable) {
      (groups[e.kind] ??= []).add(e);
    }
    const titles = {
      DraftItemKind.version: 'APP STORE VERSIONS',
      DraftItemKind.event: 'IN-APP EVENTS',
      DraftItemKind.productPage: 'CUSTOM PRODUCT PAGES',
      DraftItemKind.inAppPurchase: 'IN-APP PURCHASES · SUBMITTED ON THEIR OWN',
    };
    final pickedCount = _picked.length;
    return Card(
      key: _addKey,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Add items',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: k.ink),
            ),
            const SizedBox(height: 4),
            Text('Ready items for $_platformLabel that are not in the draft yet.', style: TextStyle(color: k.muted)),
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Nothing to add. Create a new version, in-app event or custom product page first.',
                  style: TextStyle(color: k.muted),
                ),
              ),
            for (final g in titles.entries)
              if (groups[g.key] case final list?) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
                  child: Text(
                    g.value,
                    style: TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: k.inset,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: k.line),
                  ),
                  child: Column(
                    children: [
                      for (final (i, e) in list.indexed) ...[
                        if (i > 0) Divider(height: 1, color: k.line),
                        _addRow(e),
                      ],
                    ],
                  ),
                ),
              ],
            if (groups.keys.any((g) => g != DraftItemKind.inAppPurchase)) ...[
              const SizedBox(height: 16),
              Divider(color: k.line),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      pickedCount == 0
                          ? 'Select items to add'
                          : d.draft == null
                          ? '$pickedCount selected · a draft is created first'
                          : '$pickedCount selected',
                      style: TextStyle(color: k.muted, fontSize: 12.5),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: pickedCount == 0 || _busy ? null : _addPicked,
                    icon: const Icon(Icons.add_circle_outline, size: 17),
                    label: Text(pickedCount == 0 ? 'Add selected' : 'Add $pickedCount selected'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addRow(DraftEntry e) {
    final k = Tokens.of(context);
    final iap = e.kind == DraftItemKind.inAppPurchase;
    return Opacity(
      opacity: e.ready ? 1 : 0.6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            if (iap)
              const SizedBox(width: 40, child: Icon(Icons.shopping_bag_outlined, size: 18))
            else
              Checkbox(
                value: _picked.contains(e.targetId),
                onChanged: e.ready && !_busy ? (v) => setState(() => v == true ? _picked.add(e.targetId) : _picked.remove(e.targetId)) : null,
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: e.kind == DraftItemKind.version ? 'Version ${e.name}' : e.name, style: TextStyle(fontWeight: FontWeight.w600, color: k.ink)),
                    if (e.detail != null) TextSpan(text: '  ·  ${e.detail}', style: TextStyle(color: k.muted, fontSize: 12.5)),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            if (e.problem != null)
              Text(e.problem!, style: TextStyle(color: k.muted, fontSize: 12))
            else
              Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: StatusBadge(e.state ?? 'READY'))),
            if (iap) ...[
              const SizedBox(width: 8),
              TextButton(onPressed: _busy ? null : () => _submitIap(e), child: const Text('Submit…')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    final k = Tokens.of(context);
    Widget line(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(color: k.body))),
          Text(
            value,
            style: TextStyle(color: color ?? k.ink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    final ready = d.items.where((i) => i.ready).length;
    final total = d.items.length;
    return _Panel(
      title: 'Submission',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total > 0) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ready / total,
                minHeight: 5,
                backgroundColor: d.blocked.isEmpty ? k.line : k.bad.withValues(alpha: 0.5),
                color: k.good,
              ),
            ),
            const SizedBox(height: 8),
          ],
          line('Platform', _platformLabel),
          Divider(height: 1, color: k.line),
          line('Items', '$total'),
          Divider(height: 1, color: k.line),
          line('Ready', '$ready', color: k.good),
          Divider(height: 1, color: k.line),
          line('Needs attention', '${d.blocked.length}', color: d.blocked.isEmpty ? k.muted : k.bad),
          Divider(height: 1, color: k.line),
          line('State', d.draft == null ? 'No draft' : 'Draft'),
        ],
      ),
    );
  }

  Widget _withReviewCard() {
    final k = Tokens.of(context);
    return _Panel(
      title: 'With App Review',
      trailing: StateChip('IN_REVIEW', label: '${d.open.length}'),
      child: Column(
        children: [
          for (final (i, s) in d.open.indexed) ...[
            if (i > 0) Divider(height: 1, color: k.line),
            _SubmissionTile(key: ValueKey(s.id), client: widget.client, submission: s, initiallyExpanded: true),
          ],
        ],
      ),
    );
  }

  Widget _historyCard() {
    final k = Tokens.of(context);
    final all = d.history;
    final list = _showAllHistory ? all : all.take(10).toList();
    return _Panel(
      title: 'Submission history',
      trailing: all.isEmpty ? null : StateChip(null, label: '${all.length}'),
      child: all.isEmpty
          ? Text('No earlier $_platformLabel submissions.', style: TextStyle(color: k.muted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in list.indexed) ...[
                  if (i > 0) Divider(height: 1, color: k.line),
                  _SubmissionTile(key: ValueKey(s.id), client: widget.client, submission: s),
                ],
                if (all.length > list.length) ...[
                  Divider(height: 1, color: k.line),
                  TextButton(
                    onPressed: () => setState(() => _showAllHistory = true),
                    child: Text('Show all ${all.length} submissions'),
                  ),
                ],
              ],
            ),
    );
  }
}

/// One submission that is not the draft: when it was sent, by whom, its state, and on opening, what was in it.
class _SubmissionTile extends StatefulWidget {
  const _SubmissionTile({super.key, required this.client, required this.submission, this.initiallyExpanded = false});
  final AscClient client;
  final PastSubmission submission;
  final bool initiallyExpanded;

  @override
  State<_SubmissionTile> createState() => _SubmissionTileState();
}

class _SubmissionTileState extends State<_SubmissionTile> {
  late bool _open = widget.initiallyExpanded;

  /// Started as soon as the row shows, so its title can name the version without opening it. One small request per
  /// row; the history shows ten rows until asked for more.
  late final Future<List<DraftEntry>> _items = s.items != null
      ? Future.value(s.items)
      : loadSubmissionItems(widget.client, s.id, checkReady: false);
  List<DraftEntry>? _loaded;

  PastSubmission get s => widget.submission;

  @override
  void initState() {
    super.initState();
    _loaded = s.items;
    _items.then((v) {
      if (mounted) setState(() => _loaded = v);
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final versions = _loaded?.where((i) => i.kind == DraftItemKind.version).map((i) => i.name).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                Icon(_open ? Icons.expand_more : Icons.chevron_right, size: 20, color: k.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          s.submitted == null ? 'Not submitted' : 'Submitted ${fmtDateTime(s.submitted)}',
                          if (versions != null && versions.isNotEmpty) 'Version ${versions.join(', ')}',
                        ].join(' · '),
                        style: TextStyle(color: k.ink, fontWeight: FontWeight.w600),
                      ),
                      if (s.by != null && s.by!.isNotEmpty) Text('by ${s.by}', style: TextStyle(color: k.muted, fontSize: 12)),
                    ],
                  ),
                ),
                StatusBadge(s.state),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 4, 12),
            child: FutureBuilder<List<DraftEntry>>(
              future: _items,
              builder: (context, snap) {
                if (snap.hasError) return Text('Could not load the items: ${snap.error}', style: TextStyle(color: k.bad, fontSize: 12.5));
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
                // Items the API does not identify (in-app purchases that went with the version, usually) are folded
                // into one line: a row each says nothing more and can run to dozens.
                final unknown = [for (final e in snap.data!) if (e.kind == DraftItemKind.other) e];
                final byState = <String, int>{};
                for (final e in unknown) {
                  byState.update(prettyEnum(e.itemState), (n) => n + 1, ifAbsent: () => 1);
                }
                final items = [
                  for (final e in snap.data!) if (e.kind != DraftItemKind.other) e,
                  if (unknown.isNotEmpty)
                    DraftEntry(
                      kind: DraftItemKind.other,
                      targetId: 'other',
                      name: '${unknown.length} item${unknown.length == 1 ? '' : 's'} not identified by the API',
                      detail: 'Usually in-app purchases that went with the version · '
                          '${byState.entries.map((e) => '${e.value} ${e.key.toLowerCase()}').join(', ')}',
                      itemState: unknown.every((e) => e.itemState == unknown.first.itemState) ? unknown.first.itemState : null,
                    ),
                ];
                if (items.isEmpty) return Text('No items.', style: TextStyle(color: k.muted, fontSize: 12.5));
                return Container(
                  decoration: BoxDecoration(
                    color: k.inset,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: k.line),
                  ),
                  child: Column(
                    children: [
                      for (final (i, e) in items.indexed) ...[
                        if (i > 0) Divider(height: 1, color: k.line),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              _KindIcon(e.kind),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.kind == DraftItemKind.other ? e.name : e.title, style: TextStyle(color: k.ink, fontWeight: FontWeight.w600, fontSize: 13)),
                                    if (e.detail != null) Text(e.detail!, style: TextStyle(color: k.muted, fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (e.itemState != null) StatusBadge(e.itemState),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The App Review Preflight checks for the version in the draft.
class _PreflightCard extends StatefulWidget {
  const _PreflightCard({required this.client, required this.appId, required this.version, required this.hasPriorVersion});
  final AscClient client;
  final String appId;
  final Resource version;
  final bool hasPriorVersion;

  @override
  State<_PreflightCard> createState() => _PreflightCardState();
}

class _PreflightCardState extends State<_PreflightCard> {
  late Future<List<Check>> _checks = _load();

  Future<List<Check>> _load() =>
      loadPreflight(widget.client, widget.appId, widget.version, hasPriorVersion: widget.hasPriorVersion).then(evaluatePreflight);

  @override
  void didUpdateWidget(_PreflightCard old) {
    super.didUpdateWidget(old);
    if (old.version.id != widget.version.id) _checks = _load();
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final version = widget.version;
    return _Panel(
      title: 'Preflight checks',
      child: FutureBuilder<List<Check>>(
        future: _checks,
        builder: (context, s) {
          if (s.hasError) return Text('Could not run the checks: ${s.error}', style: TextStyle(color: k.bad));
          if (!s.hasData) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
          final checks = s.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Version ${version.str('versionString')} · ${checks.where((c) => c.level == CheckLevel.pass).length}/${checks.length} pass',
                style: TextStyle(color: k.muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              for (final c in checks)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.level == CheckLevel.fail ? Color.alphaBlend(k.badSoft, k.surface) : k.inset,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.level == CheckLevel.fail ? k.bad.withValues(alpha: 0.3) : k.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        switch (c.level) {
                          CheckLevel.pass => Icons.check_circle_outline,
                          CheckLevel.warn => Icons.warning_amber_rounded,
                          CheckLevel.fail => Icons.cancel_outlined,
                        },
                        size: 17,
                        color: switch (c.level) {
                          CheckLevel.pass => k.good,
                          CheckLevel.warn => k.warn,
                          CheckLevel.fail => k.bad,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.title,
                              style: TextStyle(
                                color: c.level == CheckLevel.fail ? k.bad : k.ink,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (c.detail != null) Text(c.detail!, style: TextStyle(color: k.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: k.ink),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.fill, required this.text});
  final IconData icon;
  final Color color, fill;
  final String text;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Color.alphaBlend(fill, k.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _KindIcon extends StatelessWidget {
  const _KindIcon(this.kind, {this.bad = false});
  final DraftItemKind kind;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: bad ? Color.alphaBlend(k.badSoft, k.surface) : (kind == DraftItemKind.version ? k.accentSoft : k.inset),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: bad ? k.bad.withValues(alpha: 0.3) : k.line),
      ),
      child: Icon(
        switch (kind) {
          DraftItemKind.version => Icons.edit_note,
          DraftItemKind.event => Icons.event_outlined,
          DraftItemKind.productPage => Icons.description_outlined,
          DraftItemKind.experiment => Icons.science_outlined,
          DraftItemKind.inAppPurchase => Icons.shopping_bag_outlined,
          DraftItemKind.other => Icons.help_outline,
        },
        size: 19,
        color: bad ? k.bad : (kind == DraftItemKind.version ? k.accent : k.body),
      ),
    );
  }
}
