import 'asc_client.dart';
import 'listing.dart';
import 'models.dart';

// ---- Request bodies (shapes checked against Apple's OpenAPI spec) ---------------------------------------------------

const releaseTypes = {
  'MANUAL': 'Manually release after approval',
  'AFTER_APPROVAL': 'Automatically release after approval',
  'SCHEDULED': 'Release on a date',
};

Map<String, dynamic> versionCreateBody({
  required String appId,
  required String versionString,
  String platform = 'IOS',
  String releaseType = 'MANUAL',
  String? buildId,
}) => {
  'data': {
    'type': 'appStoreVersions',
    'attributes': {'versionString': versionString, 'platform': platform, 'releaseType': releaseType},
    'relationships': {
      'app': {
        'data': {'type': 'apps', 'id': appId},
      },
      'build': ?(buildId == null
          ? null
          : {
              'data': {'type': 'builds', 'id': buildId},
            }),
    },
  },
};

/// PATCH /v1/appStoreVersions/{id}/relationships/build
Map<String, dynamic> buildLinkBody(String buildId) => {
  'data': {'type': 'builds', 'id': buildId},
};

Map<String, dynamic> exportComplianceBody(String buildId, bool usesNonExemptEncryption) => {
  'data': {
    'type': 'builds',
    'id': buildId,
    'attributes': {'usesNonExemptEncryption': usesNonExemptEncryption},
  },
};

Map<String, dynamic> releaseTypeBody(String versionId, String releaseType, {DateTime? earliest}) => {
  'data': {
    'type': 'appStoreVersions',
    'id': versionId,
    'attributes': {
      'releaseType': releaseType,
      if (releaseType == 'SCHEDULED' && earliest != null) 'earliestReleaseDate': earliest.toUtc().toIso8601String(),
    },
  },
};

const reviewDetailFields = [
  'contactFirstName',
  'contactLastName',
  'contactPhone',
  'contactEmail',
  'demoAccountName',
  'demoAccountPassword',
  'notes',
];

Map<String, dynamic> reviewDetailBody({
  String? existingId,
  required String versionId,
  required Map<String, String> fields,
  required bool demoAccountRequired,
}) => {
  'data': {
    'type': 'appStoreReviewDetails',
    'id': ?existingId,
    'attributes': {...fields, 'demoAccountRequired': demoAccountRequired},
    if (existingId == null)
      'relationships': {
        'appStoreVersion': {
          'data': {'type': 'appStoreVersions', 'id': versionId},
        },
      },
  },
};

Map<String, dynamic> submissionCreateBody(String appId, String platform) => {
  'data': {
    'type': 'reviewSubmissions',
    'attributes': {'platform': platform},
    'relationships': {
      'app': {
        'data': {'type': 'apps', 'id': appId},
      },
    },
  },
};

Map<String, dynamic> submissionItemBody(String submissionId, String versionId) => {
  'data': {
    'type': 'reviewSubmissionItems',
    'relationships': {
      'reviewSubmission': {
        'data': {'type': 'reviewSubmissions', 'id': submissionId},
      },
      'appStoreVersion': {
        'data': {'type': 'appStoreVersions', 'id': versionId},
      },
    },
  },
};

Map<String, dynamic> submitBody(String submissionId) => {
  'data': {
    'type': 'reviewSubmissions',
    'id': submissionId,
    'attributes': {'submitted': true},
  },
};

Map<String, dynamic> cancelSubmissionBody(String submissionId) => {
  'data': {
    'type': 'reviewSubmissions',
    'id': submissionId,
    'attributes': {'canceled': true},
  },
};

// ---- Preflight: everything Apple will refuse, found before asking ------------------------------------------------------

enum CheckLevel { pass, warn, fail }

/// Which action on the Submit tab can repair a failed check.
enum CheckFix { build, compliance, review, release, listing, version }

class Check {
  const Check(this.level, this.title, [this.detail, this.fix]);
  final CheckLevel level;
  final String title;
  final String? detail;

  final CheckFix? fix;
}

/// An in-flight (or draft) submission and the version ids it contains.
class ActiveSubmission {
  ActiveSubmission(this.resource, this.versionIds, {int? itemCount}) : itemCount = itemCount ?? versionIds.length;
  final Resource resource;
  final List<String> versionIds;

  /// Every item in it: versions, but also in-app events, custom product pages and experiments.
  final int itemCount;

  /// Items that are not [versionId]. Submitting the draft would send them to review too.
  int otherItems(String versionId) => itemCount - (versionIds.contains(versionId) ? 1 : 0);
  String get state => resource.attributes['state'] as String? ?? '';
  bool get isDraft => state == 'READY_FOR_REVIEW';
}

class PreflightData {
  PreflightData({
    required this.version,
    this.build,
    this.localizations = const [],
    this.screenshotsByLoc = const {},
    this.reviewDetail,
    this.submissions = const [],
    this.hasPriorVersion = true,
  });
  final Resource version;
  final Resource? build;
  final List<Resource> localizations;
  final Map<String, int> screenshotsByLoc; // version localization id → screenshots
  final Resource? reviewDetail;
  final List<ActiveSubmission> submissions;
  final bool hasPriorVersion;
}

bool _blank(String? s) => s == null || s.trim().isEmpty;

List<Check> evaluatePreflight(PreflightData d) {
  final out = <Check>[];
  final state = d.version.str('appStoreState') ?? d.version.str('appVersionState');
  final label = '${d.version.str('versionString')}';

  final inFlight = d.submissions.where((s) => !s.isDraft && s.versionIds.contains(d.version.id));
  if (inFlight.isNotEmpty) {
    out.add(
      Check(CheckLevel.fail, 'Already submitted', 'Version $label is in a review submission (${prettyState(inFlight.first.state)}).'),
    );
  }
  if (isVersionEditable(state)) {
    out.add(Check(CheckLevel.pass, 'Version can be submitted', 'Version $label is ${prettyState(state)}.'));
  } else {
    out.add(
      Check(
        CheckLevel.fail,
        'Version is not submittable',
        'Version $label is ${prettyState(state)}. Only a version being prepared (or one that was rejected) can be sent for review. Create a new version.',
        CheckFix.version,
      ),
    );
  }

  final b = d.build;
  if (b == null) {
    out.add(const Check(CheckLevel.fail, 'No build selected', 'Attach a processed build to this version.', CheckFix.build));
  } else {
    final bs = b.str('processingState');
    if (b.flag('expired') == true) {
      out.add(Check(CheckLevel.fail, 'Build ${b.str('version')} has expired', 'Upload and attach a newer build.', CheckFix.build));
    } else if (bs != 'VALID') {
      out.add(
        Check(
          CheckLevel.fail,
          'Build ${b.str('version')} is ${prettyState(bs)}',
          'Wait for processing to finish, or attach another build.',
          CheckFix.build,
        ),
      );
    } else {
      out.add(Check(CheckLevel.pass, 'Build ${b.str('version')} attached', 'Processed and valid.'));
    }
    if (b.attributes['usesNonExemptEncryption'] == null) {
      out.add(
        const Check(
          CheckLevel.fail,
          'Export compliance not answered',
          'Say whether the app uses non-exempt encryption.',
          CheckFix.compliance,
        ),
      );
    } else {
      out.add(
        Check(
          CheckLevel.pass,
          'Export compliance answered',
          b.flag('usesNonExemptEncryption') == true ? 'Uses non-exempt encryption.' : 'No non-exempt encryption.',
        ),
      );
    }
  }

  if (d.localizations.isEmpty) {
    out.add(const Check(CheckLevel.fail, 'No localizations', 'The version has no store listing text at all.', CheckFix.listing));
  }
  for (final l in d.localizations) {
    final loc = l.str('locale') ?? '?';
    final missing = <String>[
      if (_blank(l.str('description'))) 'description',
      if (_blank(l.str('keywords'))) 'keywords',
      if (_blank(l.str('supportUrl'))) 'support URL',
    ];
    if (d.hasPriorVersion && _blank(l.str('whatsNew'))) missing.add("what's new");
    if (missing.isEmpty) {
      out.add(Check(CheckLevel.pass, '$loc listing text complete'));
    } else {
      out.add(Check(CheckLevel.fail, '$loc is missing ${missing.join(', ')}', 'Fill these in on the Listing tab.', CheckFix.listing));
    }
    if ((d.screenshotsByLoc[l.id] ?? 0) == 0) {
      out.add(Check(CheckLevel.fail, '$loc has no screenshots', 'Add at least one screenshot set on the Listing tab.', CheckFix.listing));
    } else {
      out.add(Check(CheckLevel.pass, '$loc has screenshots'));
    }
  }

  final r = d.reviewDetail;
  if (r == null) {
    out.add(
      const Check(CheckLevel.fail, 'App Review contact details missing', 'Apple needs a contact person and phone number.', CheckFix.review),
    );
  } else {
    final missing = <String>[
      if (_blank(r.str('contactFirstName'))) 'first name',
      if (_blank(r.str('contactLastName'))) 'last name',
      if (_blank(r.str('contactPhone'))) 'phone',
      if (_blank(r.str('contactEmail'))) 'email',
      if (r.flag('demoAccountRequired') == true && _blank(r.str('demoAccountName'))) 'demo account name',
      if (r.flag('demoAccountRequired') == true && _blank(r.str('demoAccountPassword'))) 'demo account password',
    ];
    if (missing.isEmpty) {
      out.add(const Check(CheckLevel.pass, 'App Review details complete'));
    } else {
      out.add(Check(CheckLevel.fail, 'App Review details missing ${missing.join(', ')}', null, CheckFix.review));
    }
  }

  if (d.version.str('releaseType') == null) {
    out.add(const Check(CheckLevel.warn, 'Release option not set', 'Choose how the version is released after approval.', CheckFix.release));
  } else {
    out.add(Check(CheckLevel.pass, 'Release: ${releaseTypes[d.version.str('releaseType')] ?? d.version.str('releaseType')}'));
  }
  return out;
}

bool canSubmit(List<Check> checks) => checks.every((c) => c.level != CheckLevel.fail);

String prettyState(String? s) => s == null ? '—' : (s.replaceAll('_', ' ').toLowerCase());

// ---- Phased release -------------------------------------------------------------------------------------------------

const phasedDayPercent = {1: 1, 2: 2, 3: 5, 4: 10, 5: 20, 6: 50, 7: 100};

String phasedReleaseLabel(Resource r) {
  final state = r.str('phasedReleaseState') ?? '';
  final day = r.integer('currentDayNumber') ?? 0;
  final pct = phasedDayPercent[day] ?? 0;
  return switch (state) {
    'INACTIVE' => 'Phased release: not started',
    'ACTIVE' => 'Day $day of 7 ($pct% of users)',
    'PAUSED' => 'Paused on day $day ($pct%)',
    'COMPLETE' => 'Released to all users',
    _ => prettyState(state),
  };
}

Map<String, dynamic> phasedReleaseCreateBody(String versionId) => {
  'data': {
    'type': 'appStoreVersionPhasedReleases',
    'attributes': {'phasedReleaseState': 'INACTIVE'},
    'relationships': {
      'appStoreVersion': {
        'data': {'type': 'appStoreVersions', 'id': versionId},
      },
    },
  },
};

Map<String, dynamic> phasedReleaseUpdateBody(String id, String state) => {
  'data': {'type': 'appStoreVersionPhasedReleases', 'id': id, 'attributes': {'phasedReleaseState': state}},
};

Future<Resource?> loadPhasedRelease(AscClient c, String versionId) async {
  final p = await nullIfMissing(c.page('/v1/appStoreVersions/$versionId/appStoreVersionPhasedRelease'));
  return p?.data.isEmpty ?? true ? null : p!.data.first;
}

Future<Resource> createPhasedRelease(AscClient c, String versionId) async =>
    (await c.post('/v1/appStoreVersionPhasedReleases', phasedReleaseCreateBody(versionId))).data.first;

Future<void> updatePhasedRelease(AscClient c, String id, String state) =>
    c.patch('/v1/appStoreVersionPhasedReleases/$id', phasedReleaseUpdateBody(id, state));

Future<void> deletePhasedRelease(AscClient c, String id) => c.delete('/v1/appStoreVersionPhasedReleases/$id');

// ---- Loading and acting ---------------------------------------------------------------------------------------------

Future<PreflightData> loadPreflight(AscClient c, String appId, Resource version, {required bool hasPriorVersion}) async {
  final r = await Future.wait<Object?>([
    nullIfMissing(c.page('/v1/appStoreVersions/${version.id}/build'))
        .then<Resource?>((p) => p == null || p.data.isEmpty ? null : p.data.first),
    c.all('/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations', {'limit': '200'}, 2),
    nullIfMissing(c.page('/v1/appStoreVersions/${version.id}/appStoreReviewDetail'))
        .then<Resource?>((p) => p == null || p.data.isEmpty ? null : p.data.first),
    listActiveSubmissions(c, appId),
  ]);
  final locs = (r[1] as ResourcePage).data;
  final shots = await Future.wait([
    for (final l in locs)
      c
          .page('/v1/appStoreVersionLocalizations/${l.id}/placements', {'filter[placementType]': 'APP_SCREENSHOT', 'limit': '1'})
          .then((p) => p.total ?? p.data.length),
  ]);
  return PreflightData(
    version: version,
    build: r[0] as Resource?,
    localizations: locs,
    screenshotsByLoc: {for (var i = 0; i < locs.length; i++) locs[i].id: shots[i]},
    reviewDetail: r[2] as Resource?,
    submissions: r[3] as List<ActiveSubmission>,
    hasPriorVersion: hasPriorVersion,
  );
}

const _activeStates = 'READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES';

Future<List<ActiveSubmission>> listActiveSubmissions(AscClient c, String appId, {String? platform, String states = _activeStates}) async {
  final subs = await c.page('/v1/reviewSubmissions', {
    'filter[app]': appId,
    'filter[state]': states,
    'filter[platform]': ?platform,
    'limit': '20',
  });
  return Future.wait(
    subs.data.map((s) async {
      // Not swallowed: an unreadable draft must not look empty, or submitting it could send items nobody saw.
      final items = await c.page('/v1/reviewSubmissions/${s.id}/items', {'include': 'appStoreVersion', 'limit': '50'});
      return ActiveSubmission(s, [
        for (final i in items.data)
          if (i.relId('appStoreVersion') != null) i.relId('appStoreVersion')!,
      ], itemCount: items.data.length);
    }),
  );
}

class SubmitOutcome {
  SubmitOutcome(this.submissionId, this.state);
  final String submissionId;
  final String? state;
}

class SubmissionFlow {
  SubmissionFlow(this.client, this.appId);
  final AscClient client;
  final String appId;

  Future<Resource> createVersion({
    required String versionString,
    String platform = 'IOS',
    String releaseType = 'MANUAL',
    String? buildId,
  }) async => (await client.post(
    '/v1/appStoreVersions',
    versionCreateBody(appId: appId, versionString: versionString, platform: platform, releaseType: releaseType, buildId: buildId),
  )).data.first;

  Future<void> attachBuild(String versionId, String buildId) =>
      client.patch('/v1/appStoreVersions/$versionId/relationships/build', buildLinkBody(buildId));

  Future<void> setExportCompliance(String buildId, bool usesNonExemptEncryption) =>
      client.patch('/v1/builds/$buildId', exportComplianceBody(buildId, usesNonExemptEncryption));

  Future<void> setReleaseType(String versionId, String releaseType, {DateTime? earliest}) =>
      client.patch('/v1/appStoreVersions/$versionId', releaseTypeBody(versionId, releaseType, earliest: earliest));

  Future<void> saveReviewDetail(
    String versionId, {
    String? existingId,
    required Map<String, String> fields,
    required bool demoAccountRequired,
  }) async {
    final body = reviewDetailBody(existingId: existingId, versionId: versionId, fields: fields, demoAccountRequired: demoAccountRequired);
    if (existingId == null) {
      await client.post('/v1/appStoreReviewDetails', body);
    } else {
      await client.patch('/v1/appStoreReviewDetails/$existingId', body);
    }
  }

  /// Reuses the app's draft submission if there is one, makes sure it contains [versionId], then submits it.
  /// Apple allows one draft per platform and submits it whole, so a draft that already holds anything else (another
  /// version, an in-app event, a product page) is refused rather than sending those to review unasked.
  Future<SubmitOutcome> submit(String versionId, {String platform = 'IOS'}) async {
    final drafts = await listActiveSubmissions(client, appId, platform: platform, states: 'READY_FOR_REVIEW');
    final String id;
    final List<String> contained;
    if (drafts.isNotEmpty) {
      final others = drafts.first.otherItems(versionId);
      if (others > 0) {
        throw AscException(
          'There is already a draft review submission for this app with $others other item${others == 1 ? '' : 's'} in it '
          '(another version, an in-app event or a product page). Submitting would send those to App Review too. '
          'Remove them from the draft, or submit it, in App Store Connect first.',
        );
      }
      id = drafts.first.resource.id;
      contained = drafts.first.versionIds;
    } else {
      id = (await client.post('/v1/reviewSubmissions', submissionCreateBody(appId, platform))).data.first.id;
      contained = const [];
    }
    if (!contained.contains(versionId)) await client.post('/v1/reviewSubmissionItems', submissionItemBody(id, versionId));
    await client.patch('/v1/reviewSubmissions/$id', submitBody(id));
    final state = (await client.page('/v1/reviewSubmissions/$id')).data.first.attributes['state'] as String?;
    return SubmitOutcome(id, state);
  }

  Future<void> cancel(String submissionId) => client.patch('/v1/reviewSubmissions/$submissionId', cancelSubmissionBody(submissionId));
}
