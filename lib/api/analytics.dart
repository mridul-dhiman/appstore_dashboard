import 'asc_client.dart';
import 'models.dart';

const reportCategories = {
  'APP_STORE_ENGAGEMENT': 'App Store Engagement',
  'APP_USAGE': 'App Usage',
  'COMMERCE': 'Commerce',
  'FRAMEWORK_USAGE': 'Framework Usage',
  'PERFORMANCE': 'Performance',
};

class AnalyticsReport {
  AnalyticsReport({required this.id, required this.category, required this.name});
  final String id;
  final String category;
  final String name;

  String get prettyCategory => reportCategories[category] ?? category;
}

class ReportInstance {
  ReportInstance({required this.id, required this.granularity, required this.processingDate, this.url});
  final String id;
  final String granularity;
  final String processingDate;
  final String? url;
}

Future<Resource> createReportRequest(AscClient c, String appId) async {
  final p = await c.post('/v1/analyticsReportRequests', {
    'data': {
      'type': 'analyticsReportRequests',
      'attributes': {'accessType': 'ONE_TIME_SNAPSHOT'},
      'relationships': {
        'app': {
          'data': {'type': 'apps', 'id': appId},
        },
      },
    },
  });
  return p.data.first;
}

Future<List<Resource>> loadReportRequests(AscClient c, String appId) async =>
    (await c.all('/v1/apps/$appId/analyticsReportRequests', {'limit': '10'}, 1)).data;

Future<List<AnalyticsReport>> loadReports(AscClient c, String requestId) async {
  final p = await c.all('/v1/analyticsReportRequests/$requestId/reports', {'limit': '200'}, 3);
  return [for (final r in p.data) AnalyticsReport(id: r.id, category: r.str('category') ?? '', name: r.str('name') ?? '')];
}

Future<List<ReportInstance>> loadReportInstances(AscClient c, String reportId) async {
  final p = await c.all('/v1/analyticsReports/$reportId/instances', {
    'limit': '30',
    'fields[analyticsReportInstances]': 'granularity,processingDate',
  }, 1);
  return [
    for (final r in p.data)
      ReportInstance(id: r.id, granularity: r.str('granularity') ?? '', processingDate: r.str('processingDate') ?? ''),
  ];
}

/// Fetches the download URL for a report segment. The URL is a pre-signed CDN link the caller opens directly.
Future<String?> reportSegmentUrl(AscClient c, String instanceId) async {
  final p = await c.page('/v1/analyticsReportInstances/$instanceId/segments', {'limit': '1'});
  return p.data.isEmpty ? null : p.data.first.str('url');
}
