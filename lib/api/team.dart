import 'asc_client.dart';
import 'models.dart';

/// Roles that can be handed to someone in App Store Connect, most powerful first. `ACCOUNT_HOLDER` is deliberately absent:
/// it belongs to one person and cannot be assigned through the API.
const assignableRoles = [
  'ADMIN',
  'APP_MANAGER',
  'DEVELOPER',
  'MARKETING',
  'SALES',
  'FINANCE',
  'CUSTOMER_SUPPORT',
  'ACCESS_TO_REPORTS',
];

/// Extra permissions that sit on top of a role.
const extraPermissions = {
  'CREATE_APPS': 'Create apps',
  'GENERATE_INDIVIDUAL_KEYS': 'Generate individual API keys',
};

const roleHelp = {
  'ADMIN': 'Full access to everything except the Account Holder’s rights.',
  'APP_MANAGER': 'Manages apps, versions, metadata and submissions.',
  'DEVELOPER': 'Builds, TestFlight and certificates; no sales or pricing.',
  'MARKETING': 'Views and edits the store page and promotional content.',
  'SALES': 'Sales and Trends reports.',
  'FINANCE': 'Payments and financial reports.',
  'CUSTOMER_SUPPORT': 'Reads and replies to customer reviews.',
  'ACCESS_TO_REPORTS': 'Read-only access to reports.',
};

/// Roles that always see every app, so the app picker does not apply.
const allAppsRoles = {'ADMIN', 'FINANCE', 'ACCOUNT_HOLDER'};

final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

bool looksLikeEmail(String s) => _email.hasMatch(s.trim());

bool rolesSeeAllApps(Iterable<String> roles) => roles.any(allAppsRoles.contains);

/// What is wrong with an invitation or an access change, in words a person can act on. Empty = fine to send.
List<String> accessProblems({String? email, required Set<String> roles, required bool allApps, required Set<String> appIds}) {
  return [
    if (email != null && email.trim().isEmpty) 'Enter an email address.',
    if (email != null && email.trim().isNotEmpty && !looksLikeEmail(email)) 'That does not look like an email address.',
    if (roles.where(assignableRoles.contains).isEmpty && !roles.contains('ACCOUNT_HOLDER')) 'Pick at least one role.',
    if (!allApps && !rolesSeeAllApps(roles) && appIds.isEmpty) 'Choose at least one app, or allow all apps.',
  ];
}

Map<String, dynamic> inviteBody({
  required String email,
  required String firstName,
  required String lastName,
  required Set<String> roles,
  required bool allApps,
  required Set<String> appIds,
  bool provisioning = false,
}) {
  final all = allApps || rolesSeeAllApps(roles);
  return {
    'data': {
      'type': 'userInvitations',
      'attributes': {
        'email': email.trim(),
        'firstName': firstName.trim(),
        'lastName': lastName.trim(),
        'roles': _ordered(roles),
        'allAppsVisible': all,
        'provisioningAllowed': provisioning,
      },
      if (!all)
        'relationships': {
          'visibleApps': {'data': [for (final id in appIds) {'type': 'apps', 'id': id}]},
        },
    },
  };
}

Map<String, dynamic> accessUpdateBody(String userId, {required Set<String> roles, required bool allApps, required Set<String> appIds, bool? provisioning}) {
  final all = allApps || rolesSeeAllApps(roles);
  return {
    'data': {
      'type': 'users',
      'id': userId,
      'attributes': {
        'roles': _ordered(roles),
        'allAppsVisible': all,
        'provisioningAllowed': ?provisioning,
      },
      if (!all)
        'relationships': {
          'visibleApps': {'data': [for (final id in appIds) {'type': 'apps', 'id': id}]},
        },
    },
  };
}

List<String> _ordered(Set<String> roles) {
  final order = [...assignableRoles, 'ACCOUNT_HOLDER', ...extraPermissions.keys];
  return [for (final r in order) if (roles.contains(r)) r];
}

/// People and pending invitations of the team.
class TeamData {
  TeamData(this.users, this.invites, this.apps, [this.invitesError]);
  final ResourcePage users;
  final ResourcePage? invites; // null when invitations could not be loaded
  final String? invitesError; // Apple's reason, shown instead of silently hiding the section
  final List<Resource> apps;
}

Future<TeamData> loadTeam(AscClient c) async {
  final users = await c.all('/v1/users', {'limit': '200', 'include': 'visibleApps', 'limit[visibleApps]': '50'});
  ResourcePage? invites;
  String? invitesError;
  try {
    invites = await c.all('/v1/userInvitations', {'limit': '200', 'include': 'visibleApps', 'limit[visibleApps]': '50'});
  } on AscException catch (e) {
    invitesError = e.message;
  }
  final apps = await c.all('/v1/apps', {'limit': '200', 'fields[apps]': 'name,bundleId'}).then((p) => p.data).catchError((_) => <Resource>[]);
  return TeamData(users, invites, apps, invitesError);
}

/// Sends the invitation. Apple emails the person; nothing else changes until they accept.
Future<Resource> sendInvitation(AscClient c, Map<String, dynamic> body) async => (await c.post('/v1/userInvitations', body)).data.first;

Future<void> revokeInvitation(AscClient c, String id) => c.delete('/v1/userInvitations/$id');

Future<void> changeAccess(AscClient c, String userId, Map<String, dynamic> body) async {
  await c.patch('/v1/users/$userId', body);
}

Future<void> removeUser(AscClient c, String userId) => c.delete('/v1/users/$userId');
