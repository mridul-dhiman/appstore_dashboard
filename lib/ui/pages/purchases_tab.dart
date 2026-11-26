part of 'app_detail_page.dart';

class _PurchaseData {
  _PurchaseData(this.iaps, this.groups);
  final ResourcePage iaps;
  final ResourcePage groups;
}

class _PurchasesTab extends StatefulWidget {
  const _PurchasesTab({required this.client, required this.appId, required this.appName});
  final AscClient client;
  final String appId;
  final String appName;

  @override
  State<_PurchasesTab> createState() => _PurchasesTabState();
}

class _PurchasesTabState extends State<_PurchasesTab> {
  final _reload = ReloadController();

  /// The in-app purchase open in the editor, or null for the list.
  String? _editing;

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<void> _open(Widget dialog) async {
    final changed = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => dialog);
    if (changed == true) _reload.reload();
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final appId = widget.appId;
    if (_editing case final id?) {
      return IapEditor(
        key: ValueKey(id),
        client: client,
        iapId: id,
        onBack: () => setState(() => _editing = null),
        onChanged: _reload.reload,
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 16, 40, 0),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () => _open(NewIapDialog(client: client, appId: appId, appName: widget.appName)),
                icon: const Icon(Icons.add),
                label: const Text('New in-app purchase'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _open(BulkIapDialog(client: client, appId: appId, appName: widget.appName)),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Bulk create'),
              ),
              const SizedBox(width: 8),
              StoreKitButton(client: client, appId: appId, appName: widget.appName),
              const Spacer(),
              IconButton(tooltip: 'Refresh', onPressed: _reload.reload, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: LoadView<_PurchaseData>(
            controller: _reload,
            load: () async {
              final r = await Future.wait([loadInAppPurchases(client, appId), loadSubscriptionGroups(client, appId)]);
              return _PurchaseData(r[0], r[1]);
            },
            builder: (context, d) {
              if (d.iaps.data.isEmpty && d.groups.data.isEmpty) {
                return const EmptyView('No in-app purchases or subscriptions yet.', icon: Icons.shopping_bag_outlined);
              }
              return ListView(
                padding: const EdgeInsets.all(40),
                children: [
                  if (d.iaps.data.isNotEmpty) ...[
                    _IapTable(page: d.iaps, onOpen: (id) => setState(() => _editing = id)),
                    TruncatedNote(d.iaps, 'in-app purchases'),
                    const SizedBox(height: 20),
                  ],
                  for (final g in d.groups.data) ...[
                    _SectionLabel('Subscription group · ${g.str('referenceName') ?? ''}'),
                    RowsCard(
                      children: [
                        for (final s in g.relIds('subscriptions').map((id) => d.groups.inc('subscriptions', id)).whereType<Resource>())
                          ListTile(
                            title: Text(s.str('name') ?? s.str('productId') ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${s.str('productId')} · ${prettyEnum(s.str('subscriptionPeriod'))}'),
                            trailing: StateChip(s.str('state')),
                          ),
                        if (g.relIds('subscriptions').isEmpty) const ListTile(title: Text('No subscriptions in this group.')),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  );
}

/// Where an in-app purchase stands, grouped the way the design summarises them.
enum _IapStage { approved, ready, review, attention }

_IapStage _stageOf(String? state) => switch (state) {
  'APPROVED' => _IapStage.approved,
  'READY_TO_SUBMIT' => _IapStage.ready,
  'WAITING_FOR_REVIEW' || 'IN_REVIEW' || 'PENDING_BINARY_APPROVAL' => _IapStage.review,
  _ => _IapStage.attention, // missing metadata, developer action needed, rejected, removed
};

const _stageLabels = {
  _IapStage.approved: 'Approved',
  _IapStage.ready: 'Ready to submit',
  _IapStage.review: 'In review',
  _IapStage.attention: 'Needs attention',
};

/// The in-app purchases as a searchable table, with a summary by state and a filter by type, as in the design.
class _IapTable extends StatefulWidget {
  const _IapTable({required this.page, required this.onOpen});
  final ResourcePage page;
  final ValueChanged<String> onOpen;

  @override
  State<_IapTable> createState() => _IapTableState();
}

class _IapTableState extends State<_IapTable> {
  final _search = TextEditingController();
  _IapStage? _stage;
  String? _type;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final all = widget.page.data;
    final q = _search.text.trim().toLowerCase();
    final types = {for (final i in all) i.str('inAppPurchaseType') ?? ''}.where((t) => t.isNotEmpty).toList()..sort();
    final shown = [
      for (final i in all)
        if ((_stage == null || _stageOf(i.str('state')) == _stage) &&
            (_type == null || i.str('inAppPurchaseType') == _type) &&
            (q.isEmpty || (i.str('name') ?? '').toLowerCase().contains(q) || (i.str('productId') ?? '').toLowerCase().contains(q)))
          i,
    ];
    int count(_IapStage s) => all.where((i) => _stageOf(i.str('state')) == s).length;
    final head = TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5);
    Widget cells(Widget name, Widget id, Widget type, Widget state) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 5, child: name),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Align(alignment: Alignment.centerLeft, child: id),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            child: Align(alignment: Alignment.centerLeft, child: type),
          ),
          SizedBox(
            width: 150,
            child: Align(alignment: Alignment.centerRight, child: state),
          ),
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'In-app purchases',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: k.ink),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 240,
                  height: 34,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Filter by name or product ID',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                ),
                // Summary chips double as a state filter; tapping the selected one clears it.
                FilterChip(
                  label: Text('All (${all.length})'),
                  selected: _stage == null,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _stage = null),
                ),
                for (final st in _IapStage.values)
                  if (count(st) > 0)
                    FilterChip(
                      avatar: Icon(
                        Icons.circle,
                        size: 8,
                        color: switch (st) {
                          _IapStage.approved => k.good,
                          _IapStage.ready => k.accent,
                          _IapStage.review => k.warn,
                          _IapStage.attention => k.bad,
                        },
                      ),
                      label: Text('${_stageLabels[st]} (${count(st)})'),
                      selected: _stage == st,
                      showCheckmark: false,
                      onSelected: (on) => setState(() => _stage = on ? st : null),
                    ),
                if (types.length > 1)
                  SegmentedButton<String?>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: null, label: Text('All (${all.length})')),
                      for (final t in types)
                        ButtonSegment(
                          value: t,
                          label: Text('${prettyEnum(t)} (${all.where((i) => i.str('inAppPurchaseType') == t).length})'),
                        ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => setState(() => _type = v.first),
                  ),
              ],
            ),
          ),
          const Divider(),
          cells(Text('PRODUCT', style: head), Text('PRODUCT ID', style: head), Text('TYPE', style: head), Text('STATE', style: head)),
          if (shown.isEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text('No in-app purchases match.', style: TextStyle(color: k.muted)),
              ),
            ),
          ],
          for (final i in shown) ...[
            const Divider(),
            InkWell(
              onTap: () => widget.onOpen(i.id),
              child: cells(
              Text(
                i.str('name') ?? i.str('productId') ?? '—',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: k.inset,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: k.line),
                ),
                child: Text(
                  i.str('productId') ?? '—',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Menlo', fontSize: 11.5, color: k.body),
                ),
              ),
              StateChip(null, label: prettyEnum(i.str('inAppPurchaseType'))),
              StateChip(i.str('state')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
