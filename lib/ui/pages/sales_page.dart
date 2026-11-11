import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../api/asc_client.dart';
import '../../api/export.dart';
import '../../api/sales.dart';
import '../../state/app_state.dart';
import '../export_button.dart';
import '../widgets.dart';

class _Day {
  _Day(this.day, this.rows, [this.error]);
  final DateTime day;
  final List<SalesRow>? rows; // null = Apple has no report for that day (yet), or it failed to load
  final String? error; // why the day could not be loaded; the other days still show
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
  List<_Day> _loaded = const [];

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  /// Apple cuts report days on Pacific time; yesterday there is the newest day that can exist.
  DateTime get _latestDay => latestReportDay(DateTime.now());

  Future<List<_Day>> _load() async {
    final vendor = widget.credentials.vendorNumber;
    final days = [for (var i = 0; i < _days; i++) _latestDay.subtract(Duration(days: i))];
    final out = <_Day>[];
    // A few at a time: each day is its own request.
    for (var i = 0; i < days.length; i += 4) {
      final chunk = days.sublist(i, (i + 4).clamp(0, days.length));
      out.addAll(
        await Future.wait(
          chunk.map((d) async {
            try {
              final tsv = await widget.client.report({
                'filter[frequency]': 'DAILY',
                'filter[reportType]': 'SALES',
                'filter[reportSubType]': 'SUMMARY',
                'filter[vendorNumber]': vendor,
                'filter[reportDate]': DateFormat('yyyy-MM-dd').format(d),
                'filter[version]': '1_0',
              });
              return _Day(d, tsv == null ? null : parseSalesReport(tsv, d));
            } on AscException catch (e) {
              // A wrong vendor number or a missing permission fails every day the same way: that gets the full error.
              if (e.status == 401 || e.status == 403) rethrow;
              return _Day(d, null, e.message);
            }
          }),
        ),
      );
    }
    if (out.every((d) => d.error != null)) throw AscException(out.first.error!);
    out.sort((a, b) => a.day.compareTo(b.day));
    _loaded = out;
    return out;
  }

  Future<void> _askVendor() => askVendorNumber(context, widget.state);

  @override
  Widget build(BuildContext context) {
    final hasVendor = widget.credentials.vendorNumber.isNotEmpty;
    return Column(
      children: [
        PageHeader(
          title: 'Sales & Trends',
          subtitle: 'Daily units and proceeds, Pacific time',
          reload: hasVendor ? _reload : null,
          actions: [
            if (hasVendor) ...[
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 7, label: Text('7d')),
                  ButtonSegment(value: 14, label: Text('14d')),
                  ButtonSegment(value: 30, label: Text('30d')),
                ],
                selected: {_days},
                onSelectionChanged: (s) {
                  setState(() => _days = s.first);
                  _reload.reload();
                },
              ),
              const SizedBox(width: 8),
              ExportButton(items: {'Sales report': () async => salesTable(_loaded.expand((d) => d.rows ?? const <SalesRow>[]).toList())}),
              IconButton(tooltip: 'Vendor number', onPressed: _askVendor, icon: const Icon(Icons.tag)),
            ],
          ],
        ),
        Expanded(
          child: !hasVendor
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const EmptyView('Sales reports need your vendor number.\nIt is not part of the API key.', icon: Icons.tag),
                      FilledButton(onPressed: _askVendor, child: const Text('Enter vendor number')),
                    ],
                  ),
                )
              : LoadView<List<_Day>>(
                  controller: _reload,
                  load: _load,
                  builder: (context, days) => _Report(days: days),
                ),
        ),
      ],
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.days});
  final List<_Day> days;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final all = days.expand((d) => d.rows ?? const <SalesRow>[]).toList();
    final failed = days.where((d) => d.error != null).toList();
    final failedDays = {for (final d in failed) d.day};
    final failedNote = failed.isEmpty
        ? null
        : '${failed.length} day${failed.length == 1 ? '' : 's'} could not be loaded (${failed.map((d) => DateFormat.MMMd().format(d.day)).join(', ')}). '
              'The totals leave them out. Refresh to try again.';
    if (all.isEmpty) {
      return EmptyView(failedNote ?? 'No sales in this period, or Apple has not published these days yet.', icon: Icons.bar_chart_outlined);
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      children: [
        if (failedNote != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tooltip(
              message: failed.first.error!,
              child: Text(failedNote, style: TextStyle(color: t.colorScheme.error)),
            ),
          ),
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth > 760 ? 4 : 2;
            final w = (c.maxWidth - 12 * (cols - 1)) / cols;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: w,
                  child: Stat(label: 'Downloads', value: fmtNum(sum(all.where((r) => r.isDownload))), icon: Icons.download_outlined),
                ),
                SizedBox(
                  width: w,
                  child: Stat(label: 'Updates', value: fmtNum(sum(all.where((r) => r.isUpdate))), icon: Icons.system_update_alt),
                ),
                SizedBox(
                  width: w,
                  child: Stat(
                    label: 'In-app purchases',
                    value: fmtNum(sum(all.where((r) => r.isPurchase))),
                    icon: Icons.shopping_bag_outlined,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: Stat(
                    label: 'Proceeds',
                    value: proceeds.isEmpty
                        ? '—'
                        : proceeds.entries.map((e) => '${NumberFormat.compact().format(e.value)} ${e.key}').join(' · '),
                    icon: Icons.payments_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloads per day', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                SizedBox(
                  height: 150,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (day, n) in daily)
                        Expanded(
                          child: Tooltip(
                            message:
                                '${DateFormat.MMMd().format(day)}: ${n == null ? (failedDays.contains(day) ? 'could not be loaded' : 'no report yet') : fmtNum(n)}',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (n != null && daily.length <= 14) Text('$n', style: t.textTheme.labelSmall),
                                  const SizedBox(height: 2),
                                  Container(
                                    height: n == null ? 2 : (maxDay == 0 ? 2 : (n / maxDay * 110).clamp(2, 110)).toDouble(),
                                    decoration: BoxDecoration(
                                      color: n == null ? t.colorScheme.outlineVariant : t.colorScheme.primary,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(DateFormat.MMMd().format(days.first.day), style: t.textTheme.bodySmall),
                    Text(DateFormat.MMMd().format(days.last.day), style: t.textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        RowsCard(
          children: [
            for (final e in byTitle.entries)
              ListTile(
                title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${fmtNum(sum(e.value.where((r) => r.isDownload)))} downloads · ${fmtNum(sum(e.value.where((r) => r.isUpdate)))} updates · ${fmtNum(sum(e.value.where((r) => r.isPurchase)))} purchases',
                ),
                trailing: Text(_proceedsOf(e.value), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        ),
      ],
    );
  }

  String _proceedsOf(List<SalesRow> rows) {
    final m = <String, double>{};
    for (final r in rows) {
      if (r.proceeds != 0) m[r.currency] = (m[r.currency] ?? 0) + r.proceeds;
    }
    return m.isEmpty ? '—' : m.entries.map((e) => '${e.value.toStringAsFixed(2)} ${e.key}').join(' · ');
  }
}

/// Asks for the active client's vendor number (needed only for Sales & Trends) and saves it.
Future<void> askVendorNumber(BuildContext context, AppState state) async {
  final v = await askText(
    context,
    title: 'Vendor number',
    label: 'Vendor number',
    initial: state.credentials?.vendorNumber ?? '',
    helper: 'App Store Connect → Payments and Financial Reports, top left. Used for Sales & Trends.',
  );
  if (v != null) await state.setVendorNumber(v);
}
