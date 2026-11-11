import 'package:appstore_dashboard/ui/pages/groups_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> a) => {'type': type, 'id': id, 'attributes': a, 'relationships': {}};

FakeAsc account() => FakeAsc((r) {
  final p = r.path.split('?').first;
  if (r.method == 'POST' && p == '/v1/betaTesters') return json({'data': res('betaTesters', 'T-new', {})}, 201);
  if (r.method != 'GET') return null;
  if (p == '/v1/apps/APP/betaGroups') {
    return json({
      'data': [
        res('betaGroups', 'G1', {'name': 'Internal crew', 'isInternalGroup': true, 'hasAccessToAllBuilds': true}),
      ],
    });
  }
  if (p == '/v1/builds') return json({'data': []});
  if (p == '/v1/betaGroups/G1/betaTesters') {
    return json({
      'data': [
        res('betaTesters', 'T1', {'email': 'ann@x.com', 'firstName': 'Ann'}),
      ],
    });
  }
  if (p == '/v1/betaGroups/G1/builds') return json({'data': []});
  if (p == '/v1/users') {
    return json({
      'data': [
        res('users', 'U1', {
          'username': 'ann@x.com',
          'firstName': 'Ann',
          'lastName': 'A',
          'roles': ['ADMIN'],
        }),
        res('users', 'U2', {
          'username': 'bob@x.com',
          'firstName': 'Bob',
          'lastName': 'B',
          'roles': ['DEVELOPER'],
        }),
      ],
    });
  }
  return null;
});

void main() {
  testWidgets('internal groups list the team; people already in the group are locked; only ticked people are added', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = account();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupsTab(client: fake.client, appId: 'APP'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add team members'));
    await tester.pumpAndSettle();
    expect(find.text('Ann A'), findsOneWidget);
    expect(find.text('Bob B'), findsOneWidget);
    expect(find.text('In group'), findsOneWidget, reason: 'Ann is already a tester');

    await tester.tap(find.text('Bob B'));
    await tester.pump();
    expect(fake.log.where((r) => r.method != 'GET'), isEmpty, reason: 'ticking must not send anything');
    await tester.tap(find.text('Add 1'));
    await tester.pumpAndSettle();

    final writes = fake.log.where((r) => r.method != 'GET').toList();
    expect(writes.single.path, '/v1/betaTesters');
    expect(writes.single.body!['data']['attributes']['email'], 'bob@x.com');
    expect(writes.single.body!['data']['relationships']['betaGroups']['data'], [
      {'type': 'betaGroups', 'id': 'G1'},
    ]);
  });
}
