import 'package:appstore_dashboard/api/export.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/api/reviews.dart';
import 'package:appstore_dashboard/api/sales.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CSV quotes commas, quotes and newlines', () {
    final t = ExportTable(
      't',
      ['a', 'b'],
      [
        {'a': 'plain', 'b': 'one, two'},
        {'a': 'say "hi"', 'b': 'line1\nline2'},
      ],
    );
    expect(toCsv(t), 'a,b\r\nplain,"one, two"\r\n"say ""hi""","line1\nline2"\r\n');
  });

  test('text that would run as a spreadsheet formula is defused; numbers are not touched', () {
    expect(csvCell('=HYPERLINK("http://evil")'), startsWith("\"'=HYPERLINK"));
    expect(csvCell('+1'), "'+1");
    expect(csvCell('-2 stars'), "'-2 stars");
    expect(csvCell('@SUM(A1)'), "'@SUM(A1)");
    expect(csvCell(-3), '-3');
    expect(csvCell(-3.5), '-3.5');
    expect(csvCell(null), '');
    expect(csvCell('fine'), 'fine');
  });

  test('JSON keeps the column order and ISO dates', () {
    final t = ExportTable(
      't',
      ['when', 'n'],
      [
        {'when': DateTime.utc(2026, 1, 2), 'n': 3, 'ignored': 'x'},
      ],
    );
    expect(toJsonText(t), contains('"when": "2026-01-02T00:00:00.000Z"'));
    expect(toJsonText(t), isNot(contains('ignored')));
  });

  test('file names are made safe and dated', () {
    expect(exportFileName('My App/Reviews?', 'csv'), matches(RegExp(r'^My_App_Reviews_\d{4}-\d{2}-\d{2}\.csv$')));
  });

  test('reviews, purchases and sales become tables', () {
    final r = Review(
      Resource.fromJson({
        'type': 'customerReviews',
        'id': 'R1',
        'attributes': {
          'rating': 4,
          'title': 'T',
          'body': 'B',
          'reviewerNickname': 'N',
          'territory': 'IND',
          'createdDate': '2026-11-03T02:05:58-08:00',
        },
      }),
      null,
    );
    final rt = reviewsTable('App', [r]);
    expect(rt.rows.single['rating'], 4);
    expect(rt.rows.single['replied'], false);
    expect(toCsv(rt).split('\r\n').first, 'id,rating,title,body,reviewer,territory,date,replied,reply');

    final pt = purchasesTable('App', [
      Resource.fromJson({
        'type': 'inAppPurchases',
        'id': 'I',
        'attributes': {'name': 'Pro', 'productId': 'p.pro', 'inAppPurchaseType': 'NON_CONSUMABLE', 'state': 'APPROVED'},
      }),
    ]);
    expect(pt.rows.single['productId'], 'p.pro');

    final st = salesTable([
      SalesRow(
        day: DateTime.utc(2026, 11, 1),
        title: 'App',
        sku: 'S',
        type: '1F',
        units: 3,
        proceedsPerUnit: 2.5,
        currency: 'USD',
        country: 'IN',
      ),
    ]);
    expect(st.rows.single['proceeds'], 7.5);
    expect(st.rows.single['date'], '2026-11-01');
  });
}
