import 'package:appstore_dashboard/api/sales.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Synthetic report in Apple's column layout (not a real export).
  const tsv = 'Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\tCustomer Currency\tCountry Code\tCurrency of Proceeds\n'
      'APPLE\tUS\tcom.x\tDev\tMy App\t1.0\t1F\t12\t0\t11/09/2026\t11/09/2026\tINR\tIN\tINR\n'
      'APPLE\tUS\tcom.x\tDev\tMy App\t1.0\t7\t5\t0\t11/09/2026\t11/09/2026\tINR\tIN\tINR\n'
      'APPLE\tUS\tcom.x.iap\tDev\tPro Plan\t1.0\tIAY\t2\t340.5\t11/09/2026\t11/09/2026\tINR\tIN\tINR\n';

  test('splits downloads, updates and purchases and computes proceeds', () {
    final rows = parseSalesReport(tsv, DateTime.utc(2026, 11, 9));
    expect(rows.length, 3);
    expect(rows.where((r) => r.isDownload).fold(0, (a, r) => a + r.units), 12);
    expect(rows.where((r) => r.isUpdate).fold(0, (a, r) => a + r.units), 5);
    final p = rows.firstWhere((r) => r.isPurchase);
    expect(p.proceeds, 681.0);
    expect(p.currency, 'INR');
  });

  test('empty or header-only input gives no rows', () {
    expect(parseSalesReport('', DateTime.utc(2026, 1, 1)), isEmpty);
    expect(parseSalesReport('Title\tUnits\n', DateTime.utc(2026, 1, 1)), isEmpty);
  });

  group('Pacific day boundary', () {
    test('summer is UTC-7, winter is UTC-8', () {
      expect(pacificTime(DateTime.utc(2026, 7, 1, 12)), DateTime.utc(2026, 7, 1, 5));
      expect(pacificTime(DateTime.utc(2026, 1, 15, 12)), DateTime.utc(2026, 1, 15, 4));
    });

    test('switches at 2:00 local on the second Sunday of March and the first Sunday of November', () {
      // 2026: DST starts Sun 8 Mar 10:00 UTC, ends Sun 1 Nov 09:00 UTC.
      expect(pacificTime(DateTime.utc(2026, 3, 8, 9, 59)).hour, 1);
      expect(pacificTime(DateTime.utc(2026, 3, 8, 10, 0)).hour, 3);
      expect(pacificTime(DateTime.utc(2026, 11, 1, 8, 59)).hour, 1);
      expect(pacificTime(DateTime.utc(2026, 11, 1, 9, 0)).hour, 1);
    });

    test('in summer, 07:30 UTC is already the next Pacific day (the old fixed -8 got this wrong)', () {
      // 2026-07-02 07:30 UTC = 00:30 PDT on 2 July, so yesterday is 1 July.
      expect(latestReportDay(DateTime.utc(2026, 7, 2, 7, 30)), DateTime.utc(2026, 7, 1));
    });
  });
}
