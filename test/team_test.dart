import 'package:appstore_dashboard/api/team.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

void main() {
  test('email and role checks explain what is missing', () {
    expect(accessProblems(email: '', roles: {}, allApps: true, appIds: {}), ['Enter an email address.', 'Pick at least one role.']);
    expect(accessProblems(email: 'nope', roles: {'DEVELOPER'}, allApps: true, appIds: {}), ['That does not look like an email address.']);
    expect(accessProblems(email: 'a@b.co', roles: {'DEVELOPER'}, allApps: false, appIds: {}), [
      'Choose at least one app, or allow all apps.',
    ]);
    expect(accessProblems(email: 'a@b.co', roles: {'DEVELOPER'}, allApps: false, appIds: {'1'}), isEmpty);
    expect(accessProblems(roles: {'CREATE_APPS'}, allApps: true, appIds: {}), [
      'Pick at least one role.',
    ], reason: 'an extra permission is not a role');
  });

  test('Admin and Finance see every app, so no app list is sent', () {
    final body = inviteBody(email: ' dev@example.com ', firstName: 'Dev', lastName: 'One', roles: {'ADMIN'}, allApps: false, appIds: {'1'});
    expect(body['data']['attributes']['allAppsVisible'], isTrue);
    expect(body['data'].containsKey('relationships'), isFalse);
    expect(body['data']['attributes']['email'], 'dev@example.com');
  });

  test('a restricted invitation lists its apps and orders roles', () {
    final body = inviteBody(
      email: 'a@b.co',
      firstName: 'A',
      lastName: 'B',
      roles: {'DEVELOPER', 'CREATE_APPS', 'APP_MANAGER'},
      allApps: false,
      appIds: {'11', '22'},
    );
    expect(body, {
      'data': {
        'type': 'userInvitations',
        'attributes': {
          'email': 'a@b.co',
          'firstName': 'A',
          'lastName': 'B',
          'roles': ['APP_MANAGER', 'DEVELOPER', 'CREATE_APPS'],
          'allAppsVisible': false,
          'provisioningAllowed': false,
        },
        'relationships': {
          'visibleApps': {
            'data': [
              {'type': 'apps', 'id': '11'},
              {'type': 'apps', 'id': '22'},
            ],
          },
        },
      },
    });
  });

  test('inviting posts once; revoking, changing access and removing hit the right paths', () async {
    final fake = FakeAsc((r) {
      if (r.method == 'POST') {
        return json({
          'data': {
            'type': 'userInvitations',
            'id': 'INV1',
            'attributes': {'email': 'a@b.co'},
          },
        }, 201);
      }
      if (r.method == 'PATCH') {
        return json({
          'data': {'type': 'users', 'id': 'U1'},
        });
      }
      return noContent();
    });
    final inv = await sendInvitation(
      fake.client,
      inviteBody(email: 'a@b.co', firstName: 'A', lastName: 'B', roles: {'SALES'}, allApps: true, appIds: {}),
    );
    expect(inv.id, 'INV1');
    await revokeInvitation(fake.client, 'INV1');
    await changeAccess(fake.client, 'U1', accessUpdateBody('U1', roles: {'MARKETING'}, allApps: false, appIds: {'9'}));
    await removeUser(fake.client, 'U1');
    expect(fake.log.map((r) => '${r.method} ${r.path}').toList(), [
      'POST /v1/userInvitations',
      'DELETE /v1/userInvitations/INV1',
      'PATCH /v1/users/U1',
      'DELETE /v1/users/U1',
    ]);
    expect(fake.log[2].body!['data']['relationships']['visibleApps']['data'], [
      {'type': 'apps', 'id': '9'},
    ]);
  });
}
