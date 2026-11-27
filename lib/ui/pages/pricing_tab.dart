import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../api/asc_client.dart';
import '../../api/pricing.dart';
import '../../api/territories.dart';
import '../theme.dart';
import '../widgets.dart';

class _PricingData {
  _PricingData(this.price, this.availability);
  final AppPriceInfo price;
  final TerritoryAvailability availability;
}

class PricingTab extends StatefulWidget {
  const PricingTab({super.key, required this.client, required this.appId});
  final AscClient client;
  final String appId;

  @override
  State<PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends State<PricingTab> {
  final _reload = ReloadController();

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<_PricingData> _load() async {
    final r = await Future.wait<Object>([
      loadAppPriceSchedule(widget.client, widget.appId),
      loadAppAvailability(widget.client, widget.appId),
    ]);
    return _PricingData(r[0] as AppPriceInfo, r[1] as TerritoryAvailability);
  }

  @override
  Widget build(BuildContext context) {
    return LoadView<_PricingData>(
      controller: _reload,
      load: _load,
      builder: (context, d) => _Body(client: widget.client, appId: widget.appId, data: d, onReload: _reload.reload),
    );
  }
}

enum _Filter { all, available, unavailable, manual }

class _Body extends StatefulWidget {
  const _Body({required this.client, required this.appId, required this.data, required this.onReload});
  final AscClient client;
  final String appId;
  final _PricingData data;
  final VoidCallback onReload;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  int _shown = 25;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_basePrice(context), const SizedBox(height: 16), _availability(context)],
    );
    final right = _territories(context);
    return ListView(
      padding: const EdgeInsets.all(40),
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 380, child: left),
              const SizedBox(width: 16),
              Expanded(child: right),
            ],
          )
        else ...[
          left,
          const SizedBox(height: 16),
          right,
        ],
      ],
    );
  }

  Widget _cardHead(BuildContext context, IconData icon, String title, String? subtitle, {Widget? trailing}) {
    final k = Tokens.of(context);
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 18, color: k.accentInk),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: k.ink),
              ),
              if (subtitle != null) Text(subtitle, style: TextStyle(color: k.muted, fontSize: 12.5)),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  static bool _free(String? amount) => amount != null && double.tryParse(amount) == 0;

  /// "USD 4.99", or "Free" for a zero price.
  static String _money(TerritoryPrice? p) {
    final a = p?.customerPrice;
    if (a == null) return '—';
    return _free(a) ? 'Free' : '${p!.currency ?? ''} $a'.trim();
  }

  /// A small blue pill, for the base territory.
  static Widget _accentPill(BuildContext context, String label) {
    final k = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label,
        style: TextStyle(color: k.accentInk, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _basePrice(BuildContext context) {
    final k = Tokens.of(context);
    final price = widget.data.price;
    final today = DateTime.now();
    final base = price.baseTerritory;
    final now = base == null ? null : price.priceIn(base, today);
    final schedule = [
      for (final p in price.baseSchedule)
        if (p.activeOn(today) || p.startsAfter(today)) p,
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHead(context, Icons.payments_outlined, 'Base price', base == null ? 'No price set' : 'Base territory · $base'),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: k.inset,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: k.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT PRICE',
                    style: TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    now == null ? (base == null ? 'Free or not set' : '—') : _money(now),
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: k.ink),
                  ),
                  if (now?.proceeds != null && !_free(now!.customerPrice))
                    Text('You receive ${now.currency ?? ''} ${now.proceeds}', style: TextStyle(color: k.muted, fontSize: 12.5)),
                ],
              ),
            ),
            if (schedule.isNotEmpty) ...[
              const SizedBox(height: 16),
              const SectionLabel('Price schedule', padding: EdgeInsets.fromLTRB(2, 0, 2, 8)),
              for (final p in schedule)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: k.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: p.activeOn(today) ? k.good : k.warn),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.activeOn(today) ? 'Now' : 'From ${fmtDate(p.start)}',
                              style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                            ),
                            if (p.activeOn(today) && p.start != null)
                              Text('Since ${fmtDate(p.start)}', style: TextStyle(color: k.muted, fontSize: 12)),
                            if (p.end != null) Text('Until ${fmtDate(p.end)}', style: TextStyle(color: k.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text(
                        _money(p),
                        style: TextStyle(fontWeight: FontWeight.w700, color: k.ink),
                      ),
                      const SizedBox(width: 10),
                      StateChip(p.activeOn(today) ? 'ACTIVE' : 'PENDING', label: p.activeOn(today) ? 'Current' : 'Scheduled'),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: k.accentInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Other territories follow Apple's automatic equalisation from the base price, unless a price is set there manually.",
                      style: TextStyle(color: k.accentInk, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _availability(BuildContext context) {
    final k = Tokens.of(context);
    final a = widget.data.availability;
    final total = a.territories.length;
    final on = a.availableCount;
    final off = [
      for (final r in a.territories)
        if (!TerritoryAvailability.isAvailable(r)) TerritoryAvailability.territoryOf(r),
    ]..sort();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardHead(context, Icons.public, 'Availability', 'Where the app is on sale'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto-available in new territories',
                        style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                      ),
                      Text('When Apple adds a territory, the app goes on sale there.', style: TextStyle(color: k.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StateChip(a.availableInNewTerritories ? 'ENABLED' : null, label: a.availableInNewTerritories ? 'On' : 'Off'),
              ],
            ),
            if (total > 0) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Coverage',
                      style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                    ),
                  ),
                  Text('$on / $total territories', style: TextStyle(color: k.muted, fontSize: 12.5)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: on / total, minHeight: 6, color: k.accent, backgroundColor: k.inset),
              ),
            ],
            if (off.isNotEmpty) ...[
              const SizedBox(height: 16),
              SectionLabel('Not available (${off.length})', padding: const EdgeInsets.fromLTRB(2, 0, 2, 8)),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in off.take(40)) StateChip('REMOVED', label: territoryName(t)),
                  if (off.length > 40) Text('+${off.length - 40} more'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _territories(BuildContext context) {
    final k = Tokens.of(context);
    final price = widget.data.price;
    final today = DateTime.now();
    final rows =
        [
          for (final r in widget.data.availability.territories)
            (
              territory: TerritoryAvailability.territoryOf(r),
              available: TerritoryAvailability.isAvailable(r),
              price: price.priceIn(TerritoryAvailability.territoryOf(r), today),
            ),
        ]..sort(
          (a, b) => a.territory == price.baseTerritory ? -1 : (b.territory == price.baseTerritory ? 1 : a.territory.compareTo(b.territory)),
        );
    int count(_Filter f) => rows.where((r) => _matches(r.available, r.price, f)).length;
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final r in rows)
        if (_matches(r.available, r.price, _filter) &&
            (q.isEmpty ||
                r.territory.toLowerCase().contains(q) ||
                territoryName(r.territory).toLowerCase().contains(q) ||
                (r.price?.currency ?? '').toLowerCase().contains(q)))
          r,
    ];
    final head = TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5);
    Widget cells(List<Widget> c) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: c[0]),
          Expanded(flex: 2, child: c[1]),
          Expanded(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: c[2]),
          ),
          Expanded(
            flex: 3,
            child: Align(alignment: Alignment.centerRight, child: c[3]),
          ),
          const SizedBox(width: 20),
          Expanded(flex: 3, child: c[4]),
          SizedBox(width: 56, child: Center(child: c[5])),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _cardHead(
                context,
                Icons.table_chart_outlined,
                'Territory pricing & availability',
                'What customers pay in each territory today',
                trailing: StateChip(null, label: '${rows.length} total'),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 34,
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() => _shown = 25),
                      decoration: const InputDecoration(
                        hintText: 'Search territories',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                    ),
                  ),
                  SegmentedButton<_Filter>(
                    showSelectedIcon: false,
                    segments: [
                      for (final (f, label) in [
                        (_Filter.all, 'All'),
                        (_Filter.available, 'Available'),
                        (_Filter.unavailable, 'Unavailable'),
                        (_Filter.manual, 'Manual price'),
                      ])
                        ButtonSegment(value: f, label: Text('$label (${count(f)})')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) => setState(() {
                      _filter = v.first;
                      _shown = 25;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            cells([
              Text('TERRITORY', style: head),
              Text('CURRENCY', style: head),
              Text('PRICE', style: head),
              Text('YOU RECEIVE', style: head),
              Text('STRATEGY', style: head),
              Text('ON SALE', style: head),
            ]),
            const Divider(),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Center(
                  child: Text('No territories match.', style: TextStyle(color: k.muted)),
                ),
              ),
            for (final r in shown.take(_shown)) ...[
              cells([
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${r.territory}  ',
                        style: TextStyle(color: k.muted, fontSize: 11.5, fontFamily: 'Menlo'),
                      ),
                      TextSpan(
                        text: territoryName(r.territory),
                        style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(r.price?.currency ?? '—', style: TextStyle(color: k.muted, fontSize: 13)),
                Text(
                  _free(r.price?.customerPrice) ? 'Free' : r.price?.customerPrice ?? '—',
                  style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                ),
                Text(_free(r.price?.proceeds) ? '—' : r.price?.proceeds ?? '—', style: TextStyle(color: k.muted, fontSize: 13)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: r.territory == price.baseTerritory
                      ? _accentPill(context, 'Base')
                      : r.price?.manual ?? false
                      ? const StateChip('PENDING', label: 'Manual')
                      : Text(r.price == null ? '—' : 'Equalised', style: TextStyle(color: k.muted, fontSize: 13)),
                ),
                Icon(
                  r.available ? Icons.check_circle_outline : Icons.block,
                  size: 18,
                  color: r.available ? k.good : k.muted,
                  semanticLabel: r.available ? 'On sale' : 'Not on sale',
                ),
              ]),
              const Divider(),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Showing ${shown.length < _shown ? shown.length : _shown} of ${shown.length}',
                      style: TextStyle(color: k.muted, fontSize: 12.5),
                    ),
                  ),
                  if (shown.length > _shown) TextButton(onPressed: () => setState(() => _shown += 50), child: const Text('Show more')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _matches(bool available, TerritoryPrice? p, _Filter f) => switch (f) {
    _Filter.all => true,
    _Filter.available => available,
    _Filter.unavailable => !available,
    _Filter.manual => p?.manual ?? false,
  };
}
