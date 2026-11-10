import 'asc_client.dart';
import 'models.dart';

/// Apple's limit for a developer response (App Store Connect rejects anything longer).
const maxReplyLength = 5970;

/// Ready-made replies. `{name}` becomes the reviewer's nickname.
const replyTemplates = {
  'Thanks': 'Hi {name}, thank you for the kind words. It means a lot to the whole team, and we are glad the app is helping you.',
  'Fix coming soon': 'Hi {name}, thank you for letting us know and sorry for the trouble. We are working on a fix and it will be in an upcoming update.',
  'Contact support': 'Hi {name}, we are sorry this has not worked well for you. Please write to our support team from the app (Profile → Help) with your registered number so we can look into it and put it right.',
};

enum ReviewFilter { all, needsReply, unanswered }

extension ReviewFilterLabel on ReviewFilter {
  String get label => switch (this) {
        ReviewFilter.all => 'All',
        ReviewFilter.needsReply => '1-3★ Needs Reply',
        ReviewFilter.unanswered => 'Unanswered',
      };
}

/// A customer review with the developer's response, when there is one.
class Review {
  Review(this.resource, this.response);
  final Resource resource;
  final Resource? response;

  String get id => resource.id;
  int get rating => resource.integer('rating') ?? 0;
  String get title => resource.str('title') ?? '';
  String get body => resource.str('body') ?? '';
  String get nickname => resource.str('reviewerNickname') ?? 'Anonymous';
  String get territory => resource.str('territory') ?? '';
  DateTime? get created => resource.date('createdDate');
  bool get answered => response != null;
  String? get replyText => response?.str('responseBody');
  bool get replyPending => response?.str('state') == 'PENDING_PUBLISH';

  Review withResponse(Resource? r) => Review(resource, r);
}

class ReviewsData {
  ReviewsData(this.reviews, this.total);
  final List<Review> reviews;
  final int? total;

  /// Count of 5★ … 1★ among the loaded reviews, in that order.
  List<int> get counts => [for (var s = 5; s >= 1; s--) reviews.where((r) => r.rating == s).length];
  double get average => reviews.isEmpty ? 0 : reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
  int get unansweredCount => reviews.where((r) => !r.answered).length;
}

List<Review> filterReviews(List<Review> all, ReviewFilter filter, {int? stars, String query = ''}) {
  final q = query.trim().toLowerCase();
  return [
    for (final r in all)
      if ((switch (filter) {
            ReviewFilter.all => true,
            ReviewFilter.needsReply => r.rating <= 3 && !r.answered,
            ReviewFilter.unanswered => !r.answered,
          }) &&
          (stars == null || r.rating == stars) &&
          (q.isEmpty || r.title.toLowerCase().contains(q) || r.body.toLowerCase().contains(q) || r.nickname.toLowerCase().contains(q)))
        r,
  ];
}

/// Reviews (newest first) with their responses, in one request per page.
Future<ReviewsData> loadReviews(AscClient c, String appId) async {
  final p = await c.all('/v1/apps/$appId/customerReviews', {'sort': '-createdDate', 'limit': '200', 'include': 'response'}, 3);
  return ReviewsData([for (final r in p.data) Review(r, p.inc('customerReviewResponses', r.relId('response')))], p.total);
}

/// The developer response to a review, or null when there is none.
Future<Resource?> fetchReviewResponse(AscClient c, String reviewId) async {
  try {
    final p = await c.page('/v1/customerReviews/$reviewId/response');
    return p.data.isEmpty ? null : p.data.first;
  } on AscException catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
}

Map<String, dynamic> replyBody(String reviewId, String text) => {
      'data': {
        'type': 'customerReviewResponses',
        'attributes': {'responseBody': text},
        'relationships': {
          'review': {'data': {'type': 'customerReviews', 'id': reviewId}},
        },
      },
    };

/// Why this text cannot be posted, or null when it can.
String? replyProblem(String text) {
  final t = text.trim();
  if (t.isEmpty) return 'Write a reply first.';
  if (t.length > maxReplyLength) return 'The reply is ${t.length - maxReplyLength} characters over the $maxReplyLength limit.';
  return null;
}

/// Posts a reply (it replaces an earlier one) and returns the response Apple created.
Future<Resource> postReviewResponse(AscClient c, String reviewId, String text) async {
  final problem = replyProblem(text);
  if (problem != null) throw AscException(problem);
  return (await c.post('/v1/customerReviewResponses', replyBody(reviewId, text.trim()))).data.first;
}

Future<void> deleteReviewResponse(AscClient c, String responseId) => c.delete('/v1/customerReviewResponses/$responseId');

String fillTemplate(String template, String nickname) => template.replaceAll('{name}', nickname.trim().isEmpty ? 'there' : nickname.trim());
