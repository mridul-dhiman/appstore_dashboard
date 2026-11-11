import 'package:appstore_dashboard/api/asc_client.dart';
import 'package:appstore_dashboard/api/models.dart';
import 'package:appstore_dashboard/api/reviews.dart';
import 'package:appstore_dashboard/services/prefs.dart';
import 'package:appstore_dashboard/state/reply_templates.dart';
import 'package:appstore_dashboard/ui/pages/reviews_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';

Map<String, dynamic> res(String type, String id, Map<String, dynamic> a, [Map<String, dynamic> rel = const {}]) => {
  'type': type,
  'id': id,
  'attributes': a,
  'relationships': rel,
};

Map<String, dynamic> review(String id, int rating, String title, {String? response, String nick = 'Asha'}) => res(
  'customerReviews',
  id,
  {
    'rating': rating,
    'title': title,
    'body': 'body of $title',
    'reviewerNickname': nick,
    'territory': 'IND',
    'createdDate': '2026-11-03T02:05:58-08:00',
  },
  {
    'response': {
      'data': response == null ? null : {'type': 'customerReviewResponses', 'id': response},
    },
  },
);

Map<String, dynamic> reviewsJson() => {
  'data': [
    review('R1', 5, 'Great'),
    review('R2', 2, 'Crashes', nick: 'Bhuvan'),
    review('R3', 1, 'Bad', response: 'S3'),
    review('R4', 3, 'Okay'),
  ],
  'included': [
    res('customerReviewResponses', 'S3', {'responseBody': 'Sorry about that', 'state': 'PUBLISHED'}),
  ],
  'meta': {
    'paging': {'total': 4, 'limit': 200},
  },
};

FakeAsc account({void Function(Recorded)? onWrite}) => FakeAsc((r) {
  final p = r.path.split('?').first;
  if (r.method == 'GET' && p == '/v1/apps/APP/customerReviews') return json(reviewsJson());
  if (r.method == 'POST' && p == '/v1/customerReviewResponses') {
    onWrite?.call(r);
    return json({
      'data': res('customerReviewResponses', 'NEW', {
        'responseBody': r.body!['data']['attributes']['responseBody'],
        'state': 'PENDING_PUBLISH',
      }),
    }, 201);
  }
  if (r.method == 'DELETE' && p == '/v1/customerReviewResponses/S3') {
    onWrite?.call(r);
    return noContent();
  }
  return null;
});

void main() {
  group('api', () {
    test('reviews load with their responses in one request', () async {
      final fake = account();
      final d = await loadReviews(fake.client, 'APP');
      expect(fake.log, hasLength(1));
      expect(fake.log.single.path, contains('include=response'));
      expect(d.reviews.map((r) => r.answered), [false, false, true, false]);
      expect(d.reviews[2].replyText, 'Sorry about that');
      expect(d.counts, [1, 0, 1, 1, 1]); // 5★ … 1★
      expect(d.average, closeTo(2.75, 0.001));
      expect(d.unansweredCount, 3);
    });

    test('filters: needs reply is 1-3★ with no response; unanswered is any rating with none', () async {
      final d = await loadReviews(account().client, 'APP');
      List<String> ids(ReviewFilter f, {int? stars, String q = ''}) =>
          filterReviews(d.reviews, f, stars: stars, query: q).map((r) => r.id).toList();
      expect(ids(ReviewFilter.all), ['R1', 'R2', 'R3', 'R4']);
      expect(ids(ReviewFilter.needsReply), ['R2', 'R4'], reason: 'R3 is 1★ but already answered; R1 is 5★');
      expect(ids(ReviewFilter.unanswered), ['R1', 'R2', 'R4']);
      expect(ids(ReviewFilter.all, stars: 2), ['R2']);
      expect(ids(ReviewFilter.all, q: 'bhuvan'), ['R2']);
    });

    test('a reply posts the documented body, trimmed', () async {
      final fake = account();
      final res = await postReviewResponse(fake.client, 'R2', '  Thanks for telling us.  ');
      expect(res.id, 'NEW');
      expect(fake.log.single.path, '/v1/customerReviewResponses');
      expect(fake.log.single.body, {
        'data': {
          'type': 'customerReviewResponses',
          'attributes': {'responseBody': 'Thanks for telling us.'},
          'relationships': {
            'review': {
              'data': {'type': 'customerReviews', 'id': 'R2'},
            },
          },
        },
      });
    });

    test('empty or over-long replies never reach Apple', () async {
      final fake = account();
      await expectLater(postReviewResponse(fake.client, 'R2', '   '), throwsA(isA<AscException>()));
      await expectLater(postReviewResponse(fake.client, 'R2', 'x' * (maxReplyLength + 1)), throwsA(isA<AscException>()));
      expect(postReviewResponse(fake.client, 'R2', 'x' * maxReplyLength), completes);
      expect(replyProblem('x' * (maxReplyLength + 3)), contains('3 characters over'));
    });

    test('fetching a missing response is null, deleting hits the response id', () async {
      final none = FakeAsc((r) => apiError(404, 'Not found', 'no response'));
      expect(await fetchReviewResponse(none.client, 'R2'), isNull);
      final fake = account();
      await deleteReviewResponse(fake.client, 'S3');
      expect(fake.log.single.path, '/v1/customerReviewResponses/S3');
    });

    test('templates fill in the reviewer name', () {
      expect(fillTemplate(defaultReplyTemplates['Fix coming soon']!, 'Asha'), startsWith('Hi Asha,'));
      expect(fillTemplate('Hi {name}', '  '), 'Hi there');
    });
  });

  group('tab', () {
    Future<FakeAsc> pump(WidgetTester tester, {void Function(Recorded)? onWrite}) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final fake = account(onWrite: onWrite);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewsTab(client: fake.client, appId: 'APP'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    testWidgets('shows the breakdown, an existing reply, and the filters', (tester) async {
      await pump(tester);
      expect(find.text('2.8'), findsOneWidget);
      expect(find.text('Your response'), findsOneWidget);
      expect(find.text('Sorry about that'), findsOneWidget);
      await tester.tap(find.textContaining('1-3★ Needs Reply'));
      await tester.pump();
      expect(find.text('Crashes'), findsOneWidget);
      expect(find.text('Okay'), findsOneWidget);
      expect(find.text('Great'), findsNothing);
      expect(find.text('Bad'), findsNothing);
    });

    testWidgets('nothing is posted until the reply is confirmed', (tester) async {
      final writes = <Recorded>[];
      final fake = await pump(tester, onWrite: writes.add);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reply').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fix coming soon'));
      await tester.pump();
      await tester.tap(find.text('Post Reply to App Store'));
      await tester.pumpAndSettle();
      expect(find.text('Post this reply to the App Store?'), findsOneWidget);
      expect(writes, isEmpty, reason: 'the confirmation dialog is open but nothing was sent');

      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(writes, isEmpty);

      await tester.tap(find.text('Post Reply to App Store'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post reply'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      final sent = writes.single.body!['data'];
      expect(sent['relationships']['review']['data']['id'], 'R1');
      expect(sent['attributes']['responseBody'], startsWith('Hi Asha,'));
      expect(fake.log.where((r) => r.method == 'POST'), hasLength(1));
      expect(find.text('Publishing'), findsOneWidget, reason: 'the new reply shows as pending straight away');
    });

    testWidgets('deleting asks first, then removes the reply', (tester) async {
      final writes = <Recorded>[];
      await pump(tester, onWrite: writes.add);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(find.text('Delete reply'));
      await tester.pumpAndSettle();
      expect(writes.single.method, 'DELETE');
      expect(find.text('Your response'), findsNothing);
    });
  });

  test('Resource helper sanity', () {
    expect(Resource.fromJson(review('R9', 4, 'x')).integer('rating'), 4);
  });

  test('templates are per client, saved, and blank ones are dropped', () async {
    final prefs = Prefs.memory();
    final a = ReplyTemplates(prefs: prefs, clientId: 'c1');
    expect(a.items.keys, defaultReplyTemplates.keys);
    await a.save({'Hello': 'Hi {name}!', ' ': 'x', 'Empty': '  '});
    expect(ReplyTemplates(prefs: prefs, clientId: 'c1').items, {'Hello': 'Hi {name}!'});
    expect(
      ReplyTemplates(prefs: prefs, clientId: 'c2').items.keys,
      defaultReplyTemplates.keys,
      reason: 'another client keeps its own',
    );
  });

  test('the default templates mention no particular app', () {
    for (final t in defaultReplyTemplates.values) {
      expect(t, isNot(contains('Profile')));
      expect(t, isNot(contains('registered number')));
    }
  });

  testWidgets('the templates dialog adds, removes and saves', (tester) async {
    final t = ReplyTemplates(prefs: Prefs.memory(), clientId: 'c1');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (_) => TemplatesDialog(templates: t),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove').first); // drop "Thanks"
    await tester.pump();
    await tester.ensureVisible(find.text('Add template'));
    await tester.tap(find.text('Add template'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Name'), findsNWidgets(3));
    final names = find.widgetWithText(TextField, 'Name');
    await tester.enterText(names.last, 'Refund');
    await tester.enterText(find.widgetWithText(TextField, 'Reply').last, 'Hi {name}, refunds go through Apple.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(t.items.keys, ['Fix coming soon', 'Contact support', 'Refund']);
  });
}
