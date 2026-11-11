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
              const Spacer(),
              IconButton(tooltip: 'Refresh', onPressed: _reload.reload, icon: const Icon(Icons.refresh)),
            ],
          ),
        ),
        Expanded(
          child: LoadView<_PurchaseData>(
            controller: _reload,
            load: () async {
              final r = await Future.wait([
                client.all('/v1/apps/$appId/inAppPurchasesV2', {'limit': '200'}, 2),
                client.all('/v1/apps/$appId/subscriptionGroups', {'limit': '50', 'include': 'subscriptions'}, 1),
              ]);
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
                    _SectionLabel('In-app purchases · ${d.iaps.data.length}'),
                    RowsCard(
                      children: [
                        for (final i in d.iaps.data)
                          ListTile(
                            title: Text(i.str('name') ?? i.str('productId') ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('${i.str('productId')} · ${prettyEnum(i.str('inAppPurchaseType'))}'),
                            trailing: StateChip(i.str('state')),
                          ),
                      ],
                    ),
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
