import 'asc_client.dart';
import 'models.dart';
import 'queries.dart';
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
  if (g.publicLink && g.limit != null && (g.limit! < 1 || g.limit! > maxPublicLinkLimit))
    'The tester limit must be between 1 and $maxPublicLinkLimit.',
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
        if (g.publicLink) ...{'publicLinkLimitEnabled': g.limit != null, if (g.limit != null) 'publicLinkLimit': g.limit},
      },
    },
    'relationships': {
      'app': {
        'data': {'type': 'apps', 'id': appId},
      },
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
Map<String, dynamic> testerCreateBody({
  required String email,
  String firstName = '',
  String lastName = '',
  required List<String> groupIds,
}) => {
  'data': {
    'type': 'betaTesters',
    'attributes': {
      'email': email.trim(),
      if (firstName.trim().isNotEmpty) 'firstName': firstName.trim(),
      if (lastName.trim().isNotEmpty) 'lastName': lastName.trim(),
    },
    'relationships': {
      'betaGroups': {
        'data': [
          for (final g in groupIds) {'type': 'betaGroups', 'id': g},
        ],
      },
    },
  },
};

Map<String, dynamic> linkageBody(String type, List<String> ids) => {
  'data': [
    for (final id in ids) {'type': type, 'id': id},
  ],
};

Map<String, dynamic> betaReviewBody(String buildId) => {
  'data': {
    'type': 'betaAppReviewSubmissions',
    'relationships': {
      'build': {
        'data': {'type': 'builds', 'id': buildId},
      },
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

Future<List<AppBuild>> loadAppBuilds(AscClient c, String appId, {int limit = 40}) async {
  // Two include sets in one request is several times slower than two parallel ones, so merge by build id.
  final r = await Future.wait<Object>([loadBuilds(c, appId, limit: limit), loadBetaDetails(c, appId, limit: limit)]);
  final page = r[0] as ResourcePage;
  final details = r[1] as Map<String, Resource>;
  return [
    for (final b in page.data)
      AppBuild(b, page.inc('preReleaseVersions', b.relId('preReleaseVersion'))?.str('version') ?? '', details[b.id]),
  ];
}

Future<List<Resource>> loadGroups(AscClient c, String appId) async => (await c.all('/v1/apps/$appId/betaGroups', {'limit': '200'})).data;

Future<List<Resource>> loadGroupTesters(AscClient c, String groupId) async =>
    (await c.all('/v1/betaGroups/$groupId/betaTesters', {'limit': '200'})).data;

Future<Set<String>> loadGroupBuildIds(AscClient c, String groupId) async =>
    (await c.all('/v1/betaGroups/$groupId/builds', {'limit': '200', 'fields[builds]': 'version'})).data.map((b) => b.id).toSet();

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

/// Apple has no endpoint that deletes a build. Expiring it is the closest thing: it leaves TestFlight and can no longer be
/// chosen for a submission. It cannot be undone.
Map<String, dynamic> expireBuildBody(String id) => {
  'data': {
    'type': 'builds',
    'id': id,
    'attributes': {'expired': true},
  },
};

Future<void> expireBuild(AscClient c, String id) async {
  await c.patch('/v1/builds/$id', expireBuildBody(id));
}

/// A delivery to App Store Connect. While Apple processes it there is no build yet, so `/v1/builds` does not list it:
/// only `/v1/apps/{id}/buildUploads` does. Without this a fresh upload is invisible until processing ends.
class BuildUpload {
  BuildUpload(this.resource);
  final Resource resource;

  String get id => resource.id;
  String get shortVersion => resource.str('cfBundleShortVersionString') ?? '—';
  String get buildNumber => resource.str('cfBundleVersion') ?? '—';
  String get label => '$shortVersion ($buildNumber)';
  DateTime? get uploaded => resource.date('uploadedDate') ?? resource.date('createdDate');

  Map<String, dynamic> get _state => (resource.attributes['state'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get state => _state['state']?.toString() ?? 'PROCESSING';
  bool get processing => state == 'PROCESSING' || state == 'AWAITING_UPLOAD';
  bool get failed => state == 'FAILED';

  /// What Apple is doing with the delivery, in words: AWAITING_UPLOAD, PROCESSING, FAILED or COMPLETE.
  String get stateLabel => switch (state) {
    'AWAITING_UPLOAD' => 'Waiting for the file',
    'PROCESSING' => 'Processing',
    'FAILED' => 'Failed',
    'COMPLETE' => 'Processed',
    final other => other[0] + other.substring(1).toLowerCase().replaceAll('_', ' '),
  };

  /// Apple's non-fatal notices (for example a missing Info.plist purpose string).
  List<String> get warnings => [
    for (final e in (_state['warnings'] as List? ?? const []))
      if (e is Map && e['description'] != null) e['description'].toString(),
  ];

  /// Apple's error descriptions, when processing failed.
  List<String> get errors => [
    for (final e in (_state['errors'] as List? ?? const []))
      if (e is Map && e['description'] != null) e['description'].toString(),
  ];
}

Future<List<BuildUpload>> loadBuildUploads(AscClient c, String appId) async {
  final page = await c.page('/v1/apps/$appId/buildUploads', {'limit': '20'});
  return [for (final r in page.data) BuildUpload(r)];
}

/// Key that ties an upload to the build Apple made from it: version (1.2.3) and build number.
String buildKey(String shortVersion, String buildNumber) => '$shortVersion|$buildNumber';

/// The uploads that deserve a row of their own: still processing, failed in the last week, or finished moments ago but not
/// yet listed as a build (Apple lags by a short while). Uploads that already became a build ([knownBuilds], by [buildKey])
/// are not repeated.
List<BuildUpload> pendingUploads(List<BuildUpload> uploads, Set<String> knownBuilds, {DateTime? now}) {
  final at = now ?? DateTime.now();
  bool within(BuildUpload u, Duration d) => u.uploaded == null || at.difference(u.uploaded!) < d;
  return [
    for (final u in uploads)
      if (!knownBuilds.contains(buildKey(u.shortVersion, u.buildNumber)) &&
          within(u, u.processing || u.failed ? const Duration(days: 7) : const Duration(hours: 1)))
        u,
  ];
}

/// Ids of the builds live on the App Store now: the build of the newest released version on each platform. (Apple
/// keeps every past release as READY_FOR_SALE, newest first, so only the first per platform is the live one.)
Future<Set<String>> loadLiveBuildIds(AscClient c, String appId) async {
  final p = await c.page('/v1/apps/$appId/appStoreVersions', {
    'filter[appStoreState]': 'READY_FOR_SALE',
    'fields[appStoreVersions]': 'build,platform',
    // Without the include Apple leaves the build relationship's data out, and no build is ever marked live.
    'include': 'build',
    'fields[builds]': 'version',
    'limit': '20',
  });
  final seen = <String>{};
  return {
    for (final v in p.data)
      if (seen.add(v.str('platform') ?? '')) ?v.relId('build'),
  };
}

/// The app's icon, from its newest build, sized [px] pixels square. One small request; null when there is no build.
Future<String?> loadAppIconUrl(AscClient c, String appId, {int px = 128}) async {
  final p = await c.page('/v1/builds', {'filter[app]': appId, 'sort': '-uploadedDate', 'limit': '1', 'fields[builds]': 'iconAssetToken'});
  if (p.data.isEmpty) return null;
  final token = (p.data.first.attributes['iconAssetToken'] as Map?)?.cast<String, dynamic>();
  final template = token?['templateUrl'] as String?;
  if (template == null) return null;
  return template.replaceAll('{w}', '$px').replaceAll('{h}', '$px').replaceAll('{f}', 'png');
}

/// TestFlight state of a build in plain words, from buildBetaDetails (internal/external build state).
String betaStateLabel(String? s) => switch (s) {
  null || '' => '',
  'PROCESSING' => 'Processing',
  'PROCESSING_EXCEPTION' => 'Processing problem',
  'MISSING_EXPORT_COMPLIANCE' => 'Missing export compliance',
  'READY_FOR_BETA_TESTING' => 'Ready to test',
  'IN_BETA_TESTING' => 'In testing',
  'EXPIRED' => 'Expired',
  'IN_EXPORT_COMPLIANCE_REVIEW' => 'Export compliance review',
  'READY_FOR_BETA_SUBMISSION' => 'Ready for beta review',
  'WAITING_FOR_BETA_REVIEW' => 'Waiting for beta review',
  'IN_BETA_REVIEW' => 'In beta review',
  'BETA_REJECTED' => 'Beta rejected',
  'BETA_APPROVED' => 'Beta approved',
  final other => other[0] + other.substring(1).toLowerCase().replaceAll('_', ' '),
};

/// Build id -> its buildBetaDetails, in one light request.
Future<Map<String, Resource>> loadBetaDetails(AscClient c, String appId, {int limit = 100}) async {
  final page = await c.page('/v1/builds', {
    'filter[app]': appId,
    'sort': '-uploadedDate',
    'limit': '$limit',
    'include': 'buildBetaDetail',
    'fields[builds]': 'buildBetaDetail',
  });
  return {for (final b in page.data) b.id: ?page.inc('buildBetaDetails', b.relId('buildBetaDetail'))};
}
