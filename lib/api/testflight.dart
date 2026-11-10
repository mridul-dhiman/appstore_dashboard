import 'asc_client.dart';
import 'models.dart';
import 'team.dart' show looksLikeEmail;

/// A TestFlight group: internal (App Store Connect users, no review) or external (anyone you invite, builds need beta review).
class GroupSettings {
  const GroupSettings({required this.name, this.feedback = true, this.publicLink = false, this.limit});
  final String name;
  final bool feedback;
  final bool publicLink;
  final int? limit; // null = no limit
}

const maxPublicLinkLimit = 10000;

List<String> groupProblems(GroupSettings g) => [
      if (g.name.trim().isEmpty) 'Give the group a name.',
      if (g.name.trim().length > 50) 'The name is over 50 characters.',
      if (g.publicLink && g.limit != null && (g.limit! < 1 || g.limit! > maxPublicLinkLimit)) 'The tester limit must be between 1 and $maxPublicLinkLimit.',
    ];

Map<String, dynamic> groupCreateBody(String appId, GroupSettings g, {required bool internal, bool allBuilds = true}) => {
      'data': {
        'type': 'betaGroups',
        'attributes': {
          'name': g.name.trim(),
          'isInternalGroup': internal,
          if (internal) 'hasAccessToAllBuilds': allBuilds,
          'feedbackEnabled': g.feedback,
          if (!internal) ...{
            'publicLinkEnabled': g.publicLink,
            if (g.publicLink) ...{
              'publicLinkLimitEnabled': g.limit != null,
              if (g.limit != null) 'publicLinkLimit': g.limit,
            },
          },
        },
        'relationships': {
          'app': {'data': {'type': 'apps', 'id': appId}},
        },
      },
    };

/// Only what changed, so an untouched field is never overwritten.
Map<String, dynamic> groupUpdateBody(String id, GroupSettings before, GroupSettings after, {required bool internal}) {
  final a = <String, dynamic>{
    if (after.name.trim() != before.name) 'name': after.name.trim(),
    if (after.feedback != before.feedback) 'feedbackEnabled': after.feedback,
    if (!internal) ...{
      if (after.publicLink != before.publicLink) 'publicLinkEnabled': after.publicLink,
      if (after.publicLink && (after.limit != before.limit || !before.publicLink)) ...{
        'publicLinkLimitEnabled': after.limit != null,
        if (after.limit != null) 'publicLinkLimit': after.limit,
      },
    },
  };
  return {
    'data': {'type': 'betaGroups', 'id': id, 'attributes': a},
  };
}

bool groupChanged(Map<String, dynamic> updateBody) => (updateBody['data']['attributes'] as Map).isNotEmpty;

/// Create a tester and put them in groups in one call. Apple emails an invitation to external testers.
Map<String, dynamic> testerCreateBody({required String email, String firstName = '', String lastName = '', required List<String> groupIds}) => {
      'data': {
        'type': 'betaTesters',
        'attributes': {
          'email': email.trim(),
          if (firstName.trim().isNotEmpty) 'firstName': firstName.trim(),
          if (lastName.trim().isNotEmpty) 'lastName': lastName.trim(),
        },
        'relationships': {
          'betaGroups': {'data': [for (final g in groupIds) {'type': 'betaGroups', 'id': g}]},
        },
      },
    };

Map<String, dynamic> linkageBody(String type, List<String> ids) => {
      'data': [for (final id in ids) {'type': type, 'id': id}],
    };

Map<String, dynamic> betaReviewBody(String buildId) => {
      'data': {
        'type': 'betaAppReviewSubmissions',
        'relationships': {
          'build': {'data': {'type': 'builds', 'id': buildId}},
        },
      },
    };

GroupSettings settingsOf(Resource g) => GroupSettings(
      name: g.str('name') ?? '',
      feedback: g.flag('feedbackEnabled') ?? true,
      publicLink: g.flag('publicLinkEnabled') ?? false,
      limit: g.flag('publicLinkLimitEnabled') == true ? g.integer('publicLinkLimit') : null,
    );

/// Builds of an app with their pre-release version and TestFlight state.
class AppBuild {
  AppBuild(this.build, this.version, this.detail);
  final Resource build;
  final String version; // 1.2.3
  final Resource? detail; // buildBetaDetails: internalBuildState / externalBuildState

  String get id => build.id;
  String get label => '$version (${build.str('version')})';
  String? get externalState => detail?.str('externalBuildState');
  String? get internalState => detail?.str('internalBuildState');
  bool get usable => build.str('processingState') == 'VALID' && build.flag('expired') != true;
}

Future<List<AppBuild>> loadAppBuilds(AscClient c, String appId) async {
  const base = {'filter[app]': '', 'sort': '-uploadedDate', 'limit': '40'};
  final q = {...base, 'filter[app]': appId};
  // Two include sets in one request is several times slower than two parallel ones, so merge by build id.
  final r = await Future.wait([
    c.page('/v1/builds', {...q, 'include': 'preReleaseVersion'}),
    c.page('/v1/builds', {...q, 'include': 'buildBetaDetail', 'fields[builds]': 'buildBetaDetail'}),
  ]);
  final details = {for (final b in r[1].data) b.id: r[1].inc('buildBetaDetails', b.relId('buildBetaDetail'))};
  return [
    for (final b in r[0].data)
      AppBuild(b, r[0].inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '', details[b.id]),
  ];
}

Future<List<Resource>> loadGroups(AscClient c, String appId) async => (await c.all('/v1/apps/$appId/betaGroups', {'limit': '200'})).data;

Future<List<Resource>> loadGroupTesters(AscClient c, String groupId) async => (await c.all('/v1/betaGroups/$groupId/betaTesters', {'limit': '200'})).data;

Future<Set<String>> loadGroupBuildIds(AscClient c, String groupId) async => (await c.all('/v1/betaGroups/$groupId/builds', {'limit': '200', 'fields[builds]': 'version'})).data.map((b) => b.id).toSet();

Future<Resource> createGroup(AscClient c, Map<String, dynamic> body) async => (await c.post('/v1/betaGroups', body)).data.first;

Future<void> updateGroup(AscClient c, String id, Map<String, dynamic> body) async {
  await c.patch('/v1/betaGroups/$id', body);
}

Future<void> deleteGroup(AscClient c, String id) => c.delete('/v1/betaGroups/$id');

Future<void> addBuildsToGroup(AscClient c, String groupId, List<String> buildIds) async {
  await c.write('POST', '/v1/betaGroups/$groupId/relationships/builds', linkageBody('builds', buildIds));
}

Future<void> removeBuildsFromGroup(AscClient c, String groupId, List<String> buildIds) async {
  await c.write('DELETE', '/v1/betaGroups/$groupId/relationships/builds', linkageBody('builds', buildIds));
}

Future<void> removeTestersFromGroup(AscClient c, String groupId, List<String> testerIds) async {
  await c.write('DELETE', '/v1/betaGroups/$groupId/relationships/betaTesters', linkageBody('betaTesters', testerIds));
}

Future<void> submitForBetaReview(AscClient c, String buildId) async {
  await c.post('/v1/betaAppReviewSubmissions', betaReviewBody(buildId));
}

/// Adds a person to a group. A new email creates the tester (and Apple emails them); a person Apple already knows (409) is
/// found by email and linked instead. Returns true when an existing tester was linked.
Future<bool> addTester(AscClient c, String groupId, {required String email, String firstName = '', String lastName = ''}) async {
  if (!looksLikeEmail(email)) throw AscException('That does not look like an email address.');
  try {
    await c.post('/v1/betaTesters', testerCreateBody(email: email, firstName: firstName, lastName: lastName, groupIds: [groupId]));
    return false;
  } on AscException catch (e) {
    if (e.status != 409) rethrow;
    final found = await c.page('/v1/betaTesters', {'filter[email]': email.trim(), 'limit': '1'});
    if (found.data.isEmpty) rethrow;
    await c.write('POST', '/v1/betaGroups/$groupId/relationships/betaTesters', linkageBody('betaTesters', [found.data.first.id]));
    return true;
  }
}
