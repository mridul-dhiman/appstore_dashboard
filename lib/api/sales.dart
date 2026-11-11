/// Parsing for the Sales & Trends daily SUMMARY report (a tab-separated table with a header row).
class SalesRow {
  SalesRow({
    required this.day,
    required this.title,
    required this.sku,
    required this.type,
    required this.units,
    required this.proceedsPerUnit,
    required this.currency,
    required this.country,
  });

  final DateTime day;
  final String title;
  final String sku;
  final String type; // Product Type Identifier
  final int units;
  final double proceedsPerUnit;
  final String currency;
  final String country;

  // https://developer.apple.com/help/app-store-connect/reference/product-type-identifiers
  bool get isDownload => const {'1', '1F', '1T', 'F1', '1E', '1EP', '1EU'}.contains(type);
  bool get isUpdate => const {'7', '7F', '7T', 'F7'}.contains(type);
  bool get isPurchase => type.startsWith('IA') || type == 'FI1';

  double get proceeds => units * proceedsPerUnit;
}

List<SalesRow> parseSalesReport(String tsv, DateTime day) {
  final lines = tsv.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return const [];
  final header = lines.first.split('\t').map((h) => h.trim()).toList();
  int col(String name) => header.indexOf(name);
  final iTitle = col('Title'), iSku = col('SKU'), iType = col('Product Type Identifier');
  final iUnits = col('Units'), iProceeds = col('Developer Proceeds'), iCur = col('Currency of Proceeds'), iCountry = col('Country Code');
  if ([iTitle, iType, iUnits, iProceeds].contains(-1)) return const [];
  final rows = <SalesRow>[];
  for (final line in lines.skip(1)) {
    final f = line.split('\t');
    String at(int i) => i >= 0 && i < f.length ? f[i].trim() : '';
    rows.add(
      SalesRow(
        day: day,
        title: at(iTitle),
        sku: at(iSku),
        type: at(iType),
        units: int.tryParse(at(iUnits)) ?? 0,
        proceedsPerUnit: double.tryParse(at(iProceeds)) ?? 0,
        currency: at(iCur),
        country: at(iCountry),
      ),
    );
  }
  return rows;
}

/// Wall-clock time in US Pacific for [utc], with daylight saving: UTC−7 from 2:00 on the second Sunday of March to 2:00
/// on the first Sunday of November, otherwise UTC−8. Apple cuts Sales & Trends days on this clock. (No timezone
/// database is needed for one fixed rule; it has held since 2007.)
DateTime pacificTime(DateTime utc) {
  final u = utc.toUtc();
  DateTime nthSunday(int year, int month, int n) {
    final first = DateTime.utc(year, month, 1);
    final offset = (DateTime.sunday - first.weekday) % 7;
    return DateTime.utc(year, month, 1 + offset + 7 * (n - 1));
  }

  // 2:00 PST = 10:00 UTC (March); 2:00 PDT = 9:00 UTC (November).
  final start = nthSunday(u.year, 3, 2).add(const Duration(hours: 10));
  final end = nthSunday(u.year, 11, 1).add(const Duration(hours: 9));
  final dst = !u.isBefore(start) && u.isBefore(end);
  return u.subtract(Duration(hours: dst ? 7 : 8));
}

/// The newest day Apple can have a daily report for: yesterday on the Pacific calendar.
DateTime latestReportDay(DateTime now) {
  final p = pacificTime(now);
  return DateTime.utc(p.year, p.month, p.day).subtract(const Duration(days: 1));
}
