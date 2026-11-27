import 'asc_client.dart';
import 'iap_editor.dart' show iapSubmissionBody;
import 'models.dart';
import 'submission.dart';

/// What a review submission item is. Apple's API names four kinds; anything else (it also lists in-app purchases that
/// went with a version, without saying which) is [other].
enum DraftItemKind { version, event, productPage, experiment, inAppPurchase, other }

const draftKindLabels = {
  DraftItemKind.version: 'App Store Version',
  DraftItemKind.event: 'In-App Event',
  DraftItemKind.productPage: 'Custom Product Page',
  DraftItemKind.experiment: 'Product Page Optimization',
  DraftItemKind.inAppPurchase: 'In-App Purchase',
  DraftItemKind.other: 'Other item',
};

/// The relationship on a review submission item for each kind that can be added, and its resource type.
const _itemRelationship = {
  DraftItemKind.version: ('appStoreVersion', 'appStoreVersions'),
  DraftItemKind.event: ('appEvent', 'appEvents'),
  DraftItemKind.productPage: ('appCustomProductPageVersion', 'appCustomProductPageVersions'),
};

/// One row: an item in the draft, or something that could be added to it.
class DraftEntry {
  DraftEntry({
    required this.kind,
    required this.targetId,
    required this.name,
    this.detail,
    this.state,
    this.itemId,
    this.itemState,
    this.problem,
    this.target,
  });

  final DraftItemKind kind;

  /// The version, event or product page version this is about.
  final String targetId;
  final String name;
  final String? detail;

  /// The target's own state (version, event or page state).
  final String? state;

  /// The review submission item, when this is in a submission.
  final String? itemId;
  final String? itemState;

  /// Why it cannot go to review yet, or null when it can.
  final String? problem;
  final Resource? target;

  bool get ready => problem == null;
  String get title => '${draftKindLabels[kind]} · $name';
}

/// A submission other than the draft: with App Review now, or in the history.
class PastSubmission {
  PastSubmission({required this.id, required this.state, this.submitted, this.by, this.items});
  final String id;
  final String state;
  final DateTime? submitted;
  final String? by;

  /// Loaded up front for submissions with App Review; null for the history, which loads them when opened.
  final List<DraftEntry>? items;

  bool get withReview => const {'WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES'}.contains(state);
}

/// Everything the Draft Submission tab shows for one platform.
class DraftOverview {
  DraftOverview({
    required this.platform,
    this.draft,
    this.items = const [],
    this.addable = const [],
    this.open = const [],
    this.history = const [],
    this.versionCount = 0,
  });

  final String platform;

  /// The draft (state READY_FOR_REVIEW), if there is one. Apple allows one per platform.
  final Resource? draft;
  final List<DraftEntry> items;

  /// Things that could be added: versions, events and product pages Apple would take, plus ready in-app purchases,
  /// which go to review through their own submission instead.
  final List<DraftEntry> addable;

  /// Submissions with App Review now (waiting, in review, or sent back with unresolved issues), with their items.
  /// While one has unresolved issues Apple takes no new submission on the platform.
  final List<PastSubmission> open;

  /// Every finished submission (complete, cancelled …), newest first.
  final List<PastSubmission> history;
  final int versionCount;

  PastSubmission? get unresolved => open.where((s) => s.state == 'UNRESOLVED_ISSUES').firstOrNull;
  List<DraftEntry> get blocked => [
    for (final i in items)
      if (!i.ready) i,
  ];
}

const _editableVersionStates = 'PREPARE_FOR_SUBMISSION,DEVELOPER_REJECTED,REJECTED,METADATA_REJECTED,INVALID_BINARY';

String? _versionProblem(Resource v, Resource? build) {
  if (build == null) return 'No build attached';
  final processing = build.str('processingState');
  if (processing != null && processing != 'VALID') return 'Build ${build.str('version')} is ${prettyState(processing)}';
  return null;
}

String? _eventProblem(Resource e) => switch (e.str('eventState')) {
  'READY_FOR_REVIEW' || 'REJECTED' => null,
  'DRAFT' => 'Draft — complete it first',
  final s => 'Event is ${prettyState(s)}',
};

String? _pageProblem(Resource v) => switch (v.str('state')) {
  'PREPARE_FOR_SUBMISSION' || 'READY_FOR_REVIEW' || 'REJECTED' => null,
  final s => 'Page is ${prettyState(s)}',
};

String _actorName(Resource? a) {
  if (a == null) return '';
  final name = [a.str('userFirstName'), a.str('userLastName')].whereType<String>().join(' ').trim();
  return name.isNotEmpty ? name : (a.str('apiKeyId') != null ? 'API key' : prettyState(a.str('actorType')));
}

Future<DraftOverview> loadDraftOverview(AscClient c, String appId, {String platform = 'IOS'}) async {
  final r = await Future.wait<Object?>([
    // Every submission, not just the latest page: the history lists them all.
    c.all('/v1/reviewSubmissions', {'filter[app]': appId, 'filter[platform]': platform, 'limit': '200', 'include': 'submittedByActor'}, 5),
    c.page('/v1/apps/$appId/appStoreVersions', {'filter[platform]': platform, 'limit': '20', 'include': 'build'}),
    c.all('/v1/apps/$appId/appEvents', {'limit': '50'}, 2).then<ResourcePage?>((p) => p).catchError((_) => null),
    c
        .page('/v1/apps/$appId/appCustomProductPages', {'limit': '50', 'include': 'appCustomProductPageVersions'})
        .then<ResourcePage?>((p) => p)
        .catchError((_) => null),
    c
        .all('/v1/apps/$appId/inAppPurchasesV2', {'limit': '200', 'filter[state]': 'READY_TO_SUBMIT'}, 2)
        .then<ResourcePage?>((p) => p)
        .catchError((_) => null),
  ]);
  final subs = r[0] as ResourcePage;
  final versions = r[1] as ResourcePage;
  final events = (r[2] as ResourcePage?)?.data ?? const <Resource>[];
  final pages = r[3] as ResourcePage?;
  final iaps = (r[4] as ResourcePage?)?.data ?? const <Resource>[];

  Resource? buildOf(Resource v) => versions.inc('builds', v.relId('build'));
  final pageNameByVersion = <String, String>{};
  final pageVersions = <Resource>[];
  for (final p in pages?.data ?? const <Resource>[]) {
    for (final vid in p.relIds('appCustomProductPageVersions')) {
      pageNameByVersion[vid] = p.str('name') ?? 'Product page';
      if (pages!.inc('appCustomProductPageVersions', vid) case final v?) pageVersions.add(v);
    }
  }

  final draft = subs.data.where((s) => s.str('state') == 'READY_FOR_REVIEW').firstOrNull;
  final items = draft == null ? <DraftEntry>[] : await loadSubmissionItems(c, draft.id, versions: versions, pageNames: pageNameByVersion);

  PastSubmission past(Resource s, {List<DraftEntry>? items}) => PastSubmission(
    id: s.id,
    state: s.str('state') ?? '',
    submitted: s.date('submittedDate'),
    by: _actorName(subs.inc('actors', s.relId('submittedByActor'))),
    items: items,
  );
  final others = [
    for (final s in subs.data)
      if (s.id != draft?.id) past(s),
  ]..sort((a, b) => (b.submitted ?? DateTime(0)).compareTo(a.submitted ?? DateTime(0)));
  final open = await Future.wait([
    for (final s in others)
      if (s.withReview)
        loadSubmissionItems(
          c,
          s.id,
          versions: versions,
          pageNames: pageNameByVersion,
          checkReady: false,
        ).then((items) => past(subs.data.firstWhere((r) => r.id == s.id), items: items)),
  ]);

  final inDraft = {for (final i in items) i.targetId};
  final addable = <DraftEntry>[
    for (final v in versions.data)
      if (_editableVersionStates.split(',').contains(v.str('appStoreState')) && !inDraft.contains(v.id))
        DraftEntry(
          kind: DraftItemKind.version,
          targetId: v.id,
          name: v.str('versionString') ?? v.id,
          detail: buildOf(v) == null ? 'No build' : 'Build ${buildOf(v)!.str('version')}',
          state: v.str('appStoreState'),
          problem: _versionProblem(v, buildOf(v)),
          target: v,
        ),
    for (final e in events)
      if (!inDraft.contains(e.id) && const {'DRAFT', 'READY_FOR_REVIEW', 'REJECTED'}.contains(e.str('eventState')))
        DraftEntry(
          kind: DraftItemKind.event,
          targetId: e.id,
          name: e.str('referenceName') ?? e.id,
          state: e.str('eventState'),
          problem: _eventProblem(e),
          target: e,
        ),
    for (final v in pageVersions)
      if (!inDraft.contains(v.id) && const {'PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW', 'REJECTED'}.contains(v.str('state')))
        DraftEntry(
          kind: DraftItemKind.productPage,
          targetId: v.id,
          name: pageNameByVersion[v.id] ?? 'Product page',
          detail: v.str('version') == null ? null : 'Version ${v.str('version')}',
          state: v.str('state'),
          problem: _pageProblem(v),
          target: v,
        ),
    for (final i in iaps)
      DraftEntry(
        kind: DraftItemKind.inAppPurchase,
        targetId: i.id,
        name: i.str('name') ?? i.str('productId') ?? i.id,
        detail: '${i.str('productId')} · ${prettyState(i.str('inAppPurchaseType'))}',
        state: i.str('state'),
        target: i,
      ),
  ];

  return DraftOverview(
    platform: platform,
    draft: draft,
    items: items,
    addable: addable,
    open: open,
    history: [
      for (final s in others)
        if (!s.withReview) s,
    ],
    versionCount: versions.data.length,
  );
}

/// The items of one submission. [versions] (with builds included) and [pageNames] save requests when the caller has
/// them already. With [checkReady] false (submissions already sent) nothing is judged and no builds are looked up
/// beyond what [versions] holds.
Future<List<DraftEntry>> loadSubmissionItems(
  AscClient c,
  String submissionId, {
  ResourcePage? versions,
  Map<String, String> pageNames = const {},
  bool checkReady = true,
}) async {
  final p = await c.all('/v1/reviewSubmissions/$submissionId/items', {
    'include': 'appStoreVersion,appCustomProductPageVersion,appEvent,appStoreVersionExperiment',
    'limit': '50',
  }, 4);
  Resource? knownBuild(String versionId) {
    final v = versions?.data.where((x) => x.id == versionId).firstOrNull;
    return v == null ? null : versions!.inc('builds', v.relId('build'));
  }

  final items = <DraftEntry>[];
  for (final i in p.data) {
    if (i.relId('appStoreVersion') case final id?) {
      final v = p.inc('appStoreVersions', id) ?? versions?.data.where((x) => x.id == id).firstOrNull;
      var build = knownBuild(id);
      if (build == null && v != null) {
        final b = await nullIfMissing(c.page('/v1/appStoreVersions/$id/build'));
        build = b == null || b.data.isEmpty ? null : b.data.first;
      }
      items.add(
        DraftEntry(
          kind: DraftItemKind.version,
          targetId: id,
          name: v?.str('versionString') ?? id,
          detail: build == null ? 'No build' : 'Build ${build.str('version')}',
          state: v?.str('appStoreState'),
          itemId: i.id,
          itemState: i.str('state'),
          problem: v == null || !checkReady ? null : _versionProblem(v, build),
          target: v,
        ),
      );
    } else if (i.relId('appEvent') case final id?) {
      final e = p.inc('appEvents', id);
      items.add(
        DraftEntry(
          kind: DraftItemKind.event,
          targetId: id,
          name: e?.str('referenceName') ?? id,
          detail: e?.str('badge') == null ? null : prettyState(e!.str('badge')),
          state: e?.str('eventState'),
          itemId: i.id,
          itemState: i.str('state'),
          problem: e == null || !checkReady ? null : _eventProblem(e),
          target: e,
        ),
      );
    } else if (i.relId('appCustomProductPageVersion') case final id?) {
      final v = p.inc('appCustomProductPageVersions', id);
      items.add(
        DraftEntry(
          kind: DraftItemKind.productPage,
          targetId: id,
          name: pageNames[id] ?? 'Product page',
          detail: v?.str('version') == null ? null : 'Version ${v!.str('version')}',
          state: v?.str('state'),
          itemId: i.id,
          itemState: i.str('state'),
          problem: v == null || !checkReady ? null : _pageProblem(v),
          target: v,
        ),
      );
    } else if (i.relId('appStoreVersionExperiment') case final id?) {
      final x = p.inc('appStoreVersionExperiments', id);
      items.add(
        DraftEntry(
          kind: DraftItemKind.experiment,
          targetId: id,
          name: x?.str('name') ?? 'Test',
          state: x?.str('state'),
          itemId: i.id,
          itemState: i.str('state'),
          target: x,
        ),
      );
    } else {
      items.add(
        DraftEntry(
          kind: DraftItemKind.other,
          targetId: i.id,
          name: 'Not identified by the API',
          detail: 'Often an in-app purchase that goes with the version',
          itemId: i.id,
          itemState: i.str('state'),
        ),
      );
    }
  }
  return items;
}

Map<String, dynamic> draftItemBody(String submissionId, DraftItemKind kind, String targetId) {
  final rel = _itemRelationship[kind];
  if (rel == null) throw ArgumentError('${draftKindLabels[kind]} cannot be added to a review submission.');
  return {
    'data': {
      'type': 'reviewSubmissionItems',
      'relationships': {
        'reviewSubmission': {
          'data': {'type': 'reviewSubmissions', 'id': submissionId},
        },
        rel.$1: {
          'data': {'type': rel.$2, 'id': targetId},
        },
      },
    },
  };
}

/// Creating, filling and sending the draft. Every call is one request; nothing is batched behind the person's back.
class DraftActions {
  DraftActions(this.client, this.appId);
  final AscClient client;
  final String appId;

  /// Starts an empty draft for [platform]. Apple refuses a second one.
  Future<String> create(String platform) async =>
      (await client.post('/v1/reviewSubmissions', submissionCreateBody(appId, platform))).data.first.id;

  Future<void> add(String submissionId, DraftEntry e) =>
      client.post('/v1/reviewSubmissionItems', draftItemBody(submissionId, e.kind, e.targetId));

  Future<void> remove(DraftEntry e) => client.delete('/v1/reviewSubmissionItems/${e.itemId}');

  /// Sends an in-app purchase to review through its own submission. It is not part of the draft.
  Future<void> submitInAppPurchase(String iapId) => client.post('/v1/inAppPurchaseSubmissions', iapSubmissionBody(iapId));

  Future<void> submit(String submissionId) => client.patch('/v1/reviewSubmissions/$submissionId', submitBody(submissionId));

  Future<void> cancel(String submissionId) => client.patch('/v1/reviewSubmissions/$submissionId', cancelSubmissionBody(submissionId));
}
