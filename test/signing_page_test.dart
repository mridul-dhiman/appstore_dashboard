import 'package:appstore_dashboard/ui/pages/signing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

void main() {
  testWidgets('Signing lists certificates with expiry, and never asks for certificate contents', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final soon = DateTime.now().add(const Duration(days: 10)).toUtc().toIso8601String();
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (p == '/v1/certificates') {
        return json({
          'data': [
            {
              'type': 'certificates',
              'id': 'C1',
              'attributes': {
                'certificateType': 'DISTRIBUTION',
                'displayName': 'Team Dist',
                'name': 'Apple Distribution',
                'serialNumber': 'ABC',
                'expirationDate': soon,
              },
            },
          ],
        });
      }
      if (r.method == 'GET') return json({'data': []});
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SigningPage(client: fake.client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Team Dist'), findsOneWidget);
    expect(find.textContaining('Expires'), findsOneWidget);
    final certs = fake.log.firstWhere((r) => r.path.startsWith('/v1/certificates'));
    expect(certs.path, contains('fields%5Bcertificates%5D='));
    expect(certs.path, isNot(contains('certificateContent')));

    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    expect(find.text('No registered devices.'), findsOneWidget);
  });
}
