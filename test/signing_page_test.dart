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

  testWidgets('Create profile sends only the chosen certificate, and devices only for development types', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic> res(String type, String id, Map<String, dynamic> a) => {'type': type, 'id': id, 'attributes': a};
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (r.method == 'GET' && p == '/v1/bundleIds') {
        return json({
          'data': [
            res('bundleIds', 'B1', {'name': 'Vidyagram', 'identifier': 'com.demo.app', 'platform': 'IOS'}),
            res('bundleIds', 'B2', {'name': 'Mac only', 'identifier': 'com.demo.mac', 'platform': 'MAC_OS'}),
          ],
        });
      }
      if (r.method == 'GET' && p == '/v1/certificates') {
        return json({
          'data': [
            res('certificates', 'CD', {'certificateType': 'DISTRIBUTION', 'displayName': 'Dist One', 'serialNumber': 'S1'}),
            res('certificates', 'CV', {'certificateType': 'DEVELOPMENT', 'displayName': 'Dev One', 'serialNumber': 'S2'}),
          ],
        });
      }
      if (r.method == 'GET' && p == '/v1/devices') {
        return json({
          'data': [
            res('devices', 'D1', {'name': 'Phone', 'udid': 'U1', 'platform': 'IOS', 'status': 'ENABLED'}),
            res('devices', 'D2', {'name': 'Mac', 'udid': 'U2', 'platform': 'MAC_OS', 'status': 'ENABLED'}),
          ],
        });
      }
      // No profileContent in the reply, so nothing is installed on the machine running the test.
      if (r.method == 'POST' && p == '/v1/profiles')
        return json({
          'data': res('profiles', 'NEW', {'name': 'X'}),
        }, 201);
      if (r.method == 'GET') return json({'data': []});
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SigningPage(client: fake.client)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create profile'));
    await tester.pumpAndSettle();

    // App Store by default: only the distribution certificate is offered, none is pre-selected, no device list.
    expect(find.textContaining('Dist One'), findsOneWidget);
    expect(find.textContaining('Dev One'), findsNothing);
    expect(find.text('Devices'), findsOneWidget, reason: 'only the tab label, not a device section');
    final create = find.widgetWithText(FilledButton, 'Create');
    expect(tester.widget<FilledButton>(create).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Profile name'), 'Vidyagram AppStore');
    await tester.tap(find.text('App ID'));
    await tester.pumpAndSettle();
    expect(find.textContaining('com.demo.mac'), findsNothing, reason: 'a macOS-only App ID cannot hold an iOS profile');
    await tester.tap(find.textContaining('com.demo.app').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Dist One'));
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();

    final post = fake.log.singleWhere((r) => r.method == 'POST');
    final data = post.body!['data'] as Map;
    expect((data['attributes'] as Map)['profileType'], 'IOS_APP_STORE');
    expect((data['attributes'] as Map)['name'], 'Vidyagram AppStore');
    final rel = data['relationships'] as Map;
    expect(((rel['bundleId'] as Map)['data'] as Map)['id'], 'B1');
    expect(((rel['certificates'] as Map)['data'] as List).map((e) => (e as Map)['id']), ['CD']);
    expect(rel.containsKey('devices'), isFalse);
    expect(find.text('Created "Vidyagram AppStore".'), findsOneWidget);
  });
}
