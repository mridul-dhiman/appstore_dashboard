import 'package:appstore_dashboard/ui/pages/sales_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_asc.dart';
import 'support/fake_state.dart';

const _tsv =
    'Title\tSKU\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tCurrency of Proceeds\tCountry Code\n'
    'App\tS1\t1\t5\t0\tUSD\tUS\n';

Future<FakeAsc> pumpSales(WidgetTester tester, FakeAsc Function() server) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = server();
  final h = StateHarness((_) => null);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SalesPage(
          client: fake.client,
          credentials: testCreds.copyWith(vendorNumber: '123'),
          state: h.state,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('one day failing leaves the rest of the report up, with a note', (tester) async {
    var first = true;
    await pumpSales(
      tester,
      () => FakeAsc((r) {
        if (!r.path.startsWith('/v1/salesReports')) return null;
        if (first) {
          first = false;
          return apiError(500, 'Server error', 'try later');
        }
        return http200(_tsv);
      }),
    );
    expect(find.textContaining('1 day could not be loaded'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
  });

  testWidgets('a permissions error is shown as the page error, not 14 notes', (tester) async {
    await pumpSales(tester, () => FakeAsc((r) => apiError(403, 'Forbidden', 'no access')));
    expect(find.textContaining('not allowed'), findsOneWidget);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });
}
