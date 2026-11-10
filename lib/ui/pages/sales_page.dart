import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/asc_client.dart';
import '../../api/sales.dart';
import '../../state/app_state.dart';
import '../widgets.dart';

class _Day {
  _Day(this.day, this.rows);
  final DateTime day;
  final List<SalesRow>? rows; // null = Apple has no report for that day (yet)
}

class SalesPage extends StatefulWidget {
  const SalesPage({super.key, required this.client, required this.credentials, required this.state});
  final AscClient client;
  final Credentials credentials;
  final AppState state;

  @override
  State<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends State<SalesPage> {
  final _reload = ReloadController();
  int _days = 14;

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  /// Apple cuts report days on Pacific time; yesterday there is the newest day that can exist.
  DateTime get _latestDay {
    final pacific = DateTime.now().toUtc().subtract(const Duration(hours: 8));
    return DateTime.utc(pacific.year, pacific.month, pacific.day).subtract(const Duration(days: 1));
  }

  Future<List<_Day>> _load() async {
    final vendor = widget.credentials.vendorNumber;
    final days = [for (var i = 0; i < _days; i++) _latestDay.subtract(Duration(days: i))];
    final out = <_Day>[];
    // A few at a time: each day is its own request.
    for (var i = 0; i < days.length; i += 4) {
      final chunk = days.sublist(i, (i + 4).clamp(0, days.length));
      out.addAll(await Future.wait(chunk.map((d) async {
        final tsv = await widget.client.report({
          'filter[frequency]': 'DAILY',
          'filter[reportType]': 'SALES',
          'filter[reportSubType]': 'SUMMARY',
          'filter[vendorNumber]': vendor,
          'filter[reportDate]': DateFormat('yyyy-MM-dd').format(d),
          'filter[version]': '1_0',
        });
        return _Day(d, tsv == null ? null : parseSalesReport(tsv, d));
      })));
    }
    return out..sort((a, b) => a.day.compareTo(b.day));
  }

  Future<void> _askVendor() async {
    final c = TextEditingController(text: widget.credentials.vendorNumber);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vendor number'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Vendor number', helperText: 'App Store Connect → Payments and Financial Reports, top left.'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (v != null) await widget.state.setVendorNumber(v);
  }

  @override
  Widget build(BuildContext context) {
    final hasVendor = widget.credentials.vendorNumber.isNotEmpty;
    return Column(children: [
      PageHeader(
        title: 'Sales & Trends',
        subtitle: 'Daily units and proceeds, Pacific time',
        reload: hasVendor ? _reload : null,
        actions: [
          if (hasVendor) ...[
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [ButtonSegment(value: 7, label: Text('7d')), ButtonSegment(value: 14, label: Text('14d')), ButtonSegment(value: 30, label: Text('30d'))],
              selected: {_days},
              onSelectionChanged: (s) {
                setState(() => _days = s.first);
                _reload.reload();
              },
            ),
            IconButton(tooltip: 'Vendor number', onPressed: _askVendor, icon: const Icon(Icons.tag)),
          ],
        ],
      ),
      Expanded(
        child: !hasVendor
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const EmptyView('Sales reports need your vendor number.\nIt is not part of the API key.', icon: Icons.tag),
                  FilledButton(onPressed: _askVendor, child: const Text('Enter vendor number')),
                ]),
              )
            : LoadView<List<_Day>>(controller: _reload, load: _load, builder: (context, days) => _Report(days: days)),
      ),
    ]);
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.days});
  final List<_Day> days;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = days.expand((d) => d.rows ?? const <SalesRow>[]).toList();
    if (all.isEmpty) {
      return const EmptyView('No sales in this period, or Apple has not published these days yet.', icon: Icons.bar_chart_outlined);
    }
    int sum(Iterable<SalesRow> rows) => rows.fold(0, (a, r) => a + r.units);
    final proceeds = <String, double>{};
    for (final r in all) {
      if (r.proceeds != 0) proceeds[r.currency] = (proceeds[r.currency] ?? 0) + r.proceeds;
    }
    final daily = [for (final d in days) (d.day, d.rows == null ? null : sum((d.rows!).where((r) => r.isDownload)))];
    final maxDay = daily.map((e) => e.$2 ?? 0).fold(0, (a, b) => a > b ? a : b);

    final byTitle = <String, List<SalesRow>>{};
    for (final r in all) {
      (byTitle[r.title] ??= []).add(r);
    }

    return ListView(padding: const EdgeInsets.fromLTRB(40, 0, 40, 40), children: [
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 760 ? 4 : 2;
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          SizedBox(width: w, child: Stat(label: 'Downloads', value: fmtNum(sum(all.where((r) => r.isDownload))), icon: Icons.download_outlined)),
          SizedBox(width: w, child: Stat(label: 'Updates', value: fmtNum(sum(all.where((r) => r.isUpdate))), icon: Icons.system_update_alt)),
          SizedBox(width: w, child: Stat(label: 'In-app purchases', value: fmtNum(sum(all.where((r) => r.isPurchase))), icon: Icons.shopping_bag_outlined)),
          SizedBox(
            width: w,
            child: Stat(
              label: 'Proceeds',
              value: proceeds.isEmpty ? '—' : proceeds.entries.map((e) => '${NumberFormat.compact().format(e.value)} ${e.key}').join(' · '),
              icon: Icons.payments_outlined,
            ),
          ),
        ]);
      }),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Downloads per day', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final (day, n) in daily)
                  Expanded(
                    child: Tooltip(
                      message: '${DateFormat.MMMd().format(day)}: ${n == null ? 'no report yet' : fmtNum(n)}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                          if (n != null && daily.length <= 14) Text('$n', style: t.textTheme.labelSmall),
                          const SizedBox(height: 2),
                          Container(
                            height: n == null ? 2 : (maxDay == 0 ? 2 : (n / maxDay * 110).clamp(2, 110)).toDouble(),
                            decoration: BoxDecoration(
                              color: n == null ? t.colorScheme.outlineVariant : t.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(DateFormat.MMMd().format(days.first.day), style: t.textTheme.bodySmall),
              Text(DateFormat.MMMd().format(days.last.day), style: t.textTheme.bodySmall),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      RowsCard(children: [
        for (final e in byTitle.entries)
          ListTile(
            title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${fmtNum(sum(e.value.where((r) => r.isDownload)))} downloads · ${fmtNum(sum(e.value.where((r) => r.isUpdate)))} updates · ${fmtNum(sum(e.value.where((r) => r.isPurchase)))} purchases'),
            trailing: Text(_proceedsOf(e.value), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ]),
    ]);
  }

  String _proceedsOf(List<SalesRow> rows) {
    final m = <String, double>{};
    for (final r in rows) {
      if (r.proceeds != 0) m[r.currency] = (m[r.currency] ?? 0) + r.proceeds;
    }
    return m.isEmpty ? '—' : m.entries.map((e) => '${e.value.toStringAsFixed(2)} ${e.key}').join(' · ');
  }
}
