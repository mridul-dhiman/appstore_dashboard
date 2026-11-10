import 'dart:convert';

import 'package:intl/intl.dart';

import 'reviews.dart';
import 'sales.dart';
import 'models.dart';

/// A table to hand to a spreadsheet or another tool.
class ExportTable {
  ExportTable(this.name, this.columns, this.rows);
  final String name; // file name without extension
  final List<String> columns;
  final List<Map<String, Object?>> rows;
}

/// One CSV cell. Text that starts with `= + - @` (or a tab / CR) would run as a formula when the file is opened in a
/// spreadsheet, and review text comes from strangers, so such text gets a leading apostrophe. Numbers are left alone.
String csvCell(Object? v) {
  if (v == null) return '';
  var s = v is DateTime ? v.toIso8601String() : '$v';
  if (v is String && s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  if (s.contains(RegExp(r'[",\n\r]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}

String toCsv(ExportTable t) {
  final b = StringBuffer()..write('${t.columns.map(csvCell).join(',')}\r\n');
  for (final r in t.rows) {
    b.write('${t.columns.map((c) => csvCell(r[c])).join(',')}\r\n');
  }
  return b.toString();
}

String toJsonText(ExportTable t) => const JsonEncoder.withIndent('  ').convert([
      for (final r in t.rows) {for (final c in t.columns) c: r[c] is DateTime ? (r[c] as DateTime).toIso8601String() : r[c]},
    ]);

String exportFileName(String base, String ext) {
  final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return '${safe.isEmpty ? 'export' : safe}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.$ext';
}

ExportTable reviewsTable(String appName, List<Review> reviews) => ExportTable(
      '${appName}_reviews',
      const ['id', 'rating', 'title', 'body', 'reviewer', 'territory', 'date', 'replied', 'reply'],
      [
        for (final r in reviews)
          {'id': r.id, 'rating': r.rating, 'title': r.title, 'body': r.body, 'reviewer': r.nickname, 'territory': r.territory, 'date': r.created, 'replied': r.answered, 'reply': r.replyText ?? ''},
      ],
    );

ExportTable purchasesTable(String appName, List<Resource> iaps) => ExportTable(
      '${appName}_in_app_purchases',
      const ['name', 'productId', 'type', 'state'],
      [
        for (final i in iaps) {'name': i.str('name'), 'productId': i.str('productId'), 'type': i.str('inAppPurchaseType'), 'state': i.str('state')},
      ],
    );

ExportTable salesTable(List<SalesRow> rows) => ExportTable(
      'sales_report',
      const ['date', 'title', 'sku', 'productType', 'units', 'proceedsPerUnit', 'proceeds', 'currency', 'country'],
      [
        for (final r in rows)
          {
            'date': DateFormat('yyyy-MM-dd').format(r.day),
            'title': r.title,
            'sku': r.sku,
            'productType': r.type,
            'units': r.units,
            'proceedsPerUnit': r.proceedsPerUnit,
            'proceeds': r.proceeds,
            'currency': r.currency,
            'country': r.country,
          },
      ],
    );
