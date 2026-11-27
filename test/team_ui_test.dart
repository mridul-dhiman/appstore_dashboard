import 'package:appstore_dashboard/ui/pages/team_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> a) => {'type': type, 'id': id, 'attributes': a, 'relationships': {}};

void main() {
  testWidgets('inviting, revoking and refreshing all update the lists', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final users = [
      res('users', 'U1', {
        'username': 'me@x.com',
        'firstName': 'Me',
        'lastName': 'Owner',
        'roles': ['ADMIN'],
        'allAppsVisible': true,
      }),
    ];
    final invites = <Map<String, dynamic>>[];
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (r.method == 'GET' && p == '/v1/users') return json({'data': users});
      if (r.method == 'GET' && p == '/v1/userInvitations') return json({'data': invites});
      if (r.method == 'GET' && p == '/v1/apps') return json({'data': []});
      if (r.method == 'POST' && p == '/v1/userInvitations') {
        invites.add(res('userInvitations', 'INV1', {...r.body!['data']['attributes'] as Map<String, dynamic>}));
        return json({'data': invites.last}, 201);
      }
      if (r.method == 'DELETE' && p == '/v1/userInvitations/INV1') {
        invites.clear();
        return noContent();
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TeamPage(client: fake.client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Me Owner'), findsOneWidget);
    expect(find.text('PENDING INVITATIONS'), findsNothing);

    await tester.tap(find.text('Invite user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email address'), 'new@x.com');
    await tester.tap(find.text('Developer').last); // the drawer's role card is the last one on screen
    await tester.pump();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();

    expect(find.text('PENDING INVITATIONS'), findsOneWidget, reason: 'the invitation should appear after sending');
    expect(find.text('new@x.com'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(find.text('PENDING INVITATIONS'), findsNothing, reason: 'a revoked invitation should disappear');

    users.add(
      res('users', 'U2', {
        'username': 'two@x.com',
        'firstName': 'Two',
        'roles': ['DEVELOPER'],
      }),
    );
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Two'), findsOneWidget, reason: 'Refresh should pick up a new user');
    await tester.pump(const Duration(seconds: 4)); // let the follow-up reloads finish
    await tester.pumpAndSettle();
  });

  testWidgets('when Apple\'s lists lag behind, a change still shows at once and stays', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Apple\'s GETs never change: the writes succeed but the lists have not caught up.
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (r.method == 'GET' && p == '/v1/users') {
        return json({
          'data': [
            res('users', 'U1', {
              'username': 'me@x.com',
              'firstName': 'Me',
              'roles': ['ADMIN'],
            }),
            res('users', 'U2', {
              'username': 'dev@x.com',
              'firstName': 'Dev',
              'roles': ['DEVELOPER'],
            }),
          ],
        });
      }
      if (r.method == 'GET' && p == '/v1/userInvitations') return json({'data': []});
      if (r.method == 'GET' && p == '/v1/apps') return json({'data': []});
      if (r.method == 'POST' && p == '/v1/userInvitations') {
        return json({
          'data': res('userInvitations', 'INV1', {'email': 'new@x.com'}),
        }, 201);
      }
      if (r.method == 'DELETE' && p == '/v1/users/U2') return noContent();
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TeamPage(client: fake.client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dev'), findsOneWidget);

    await tester.tap(find.text('Invite user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email address'), 'new@x.com');
    await tester.tap(find.text('Developer').last);
    await tester.pump();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();
    expect(find.text('PENDING INVITATIONS'), findsOneWidget);
    expect(find.text('new@x.com'), findsWidgets);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Remove').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Dev'), findsNothing, reason: 'a removed user must not come back from a stale list');

    await tester.pump(const Duration(seconds: 4)); // the follow-up reload still returns the stale lists
    await tester.pumpAndSettle();
    expect(find.text('Dev'), findsNothing);
    expect(find.text('PENDING INVITATIONS'), findsOneWidget);
  });

  testWidgets('after a change the page keeps reloading until Apple shows it, then stops', (tester) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var caughtUp = false;
    var userLoads = 0;
    final fake = FakeAsc((r) {
      final p = r.path.split('?').first;
      if (r.method == 'GET' && p == '/v1/users') {
        userLoads++;
        return json({
          'data': [
            res('users', 'U1', {
              'username': 'me@x.com',
              'firstName': 'Me',
              'roles': ['ADMIN'],
            }),
          ],
        });
      }
      if (r.method == 'GET' && p == '/v1/userInvitations') {
        // Apple lists the new invitation from the second reload after it was sent.
        return json({
          'data': [
            if (caughtUp)
              res('userInvitations', 'INV1', {
                'email': 'new@x.com',
                'roles': ['DEVELOPER'],
              }),
          ],
        });
      }
      if (r.method == 'GET' && p == '/v1/apps') return json({'data': []});
      if (r.method == 'POST' && p == '/v1/userInvitations') {
        return json({
          'data': res('userInvitations', 'INV1', {'email': 'new@x.com'}),
        }, 201);
      }
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TeamPage(client: fake.client)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invite user'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Email address'), 'new@x.com');
    await tester.tap(find.text('Developer').last);
    await tester.pump();
    await tester.tap(find.text('Send invitation'));
    await tester.pumpAndSettle();
    final afterSend = userLoads;

    await tester.pump(const Duration(seconds: 2)); // first catch-up reload: Apple still behind
    await tester.pumpAndSettle();
    expect(userLoads, afterSend + 1);
    caughtUp = true;
    await tester.pump(const Duration(seconds: 5)); // second: Apple shows it
    await tester.pumpAndSettle();
    expect(userLoads, afterSend + 2);
    await tester.pump(const Duration(seconds: 30)); // nothing left to wait for: no more reloads
    await tester.pumpAndSettle();
    expect(userLoads, afterSend + 2);
    expect(find.text('new@x.com'), findsWidgets);
  });
}
