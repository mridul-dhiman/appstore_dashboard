import 'dart:typed_data';

import 'package:appstore_dashboard/api/build_uploader.dart';
import 'package:appstore_dashboard/api/ipa_info.dart';
import 'package:appstore_dashboard/state/upload_jobs.dart';
import 'package:appstore_dashboard/ui/pages/upload_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_asc.dart';

void main() {
  testWidgets('a running upload is still shown after leaving the tab and coming back', (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeAsc((r) {
      if (r.method == 'GET') return json({'data': []});
      return null;
    });
    final jobs = UploadJobs();
    final job = UploadJob(
      appId: 'A1',
      info: IpaInfo(bundleId: 'com.x', version: '3.1', build: '42'),
      source: BytesSource('x.ipa', Uint8List(4)),
    );
    // A job part-way through, without touching the network.
    job.progress = UploadProgress(UploadPhase.uploading, sentBytes: 2, totalBytes: 4);

    Widget tab() => MaterialApp(
      home: Scaffold(
        body: UploadTab(client: fake.client, appId: 'A1', bundleId: 'com.x', uploads: jobs),
      ),
    );
    expect(jobs.forApp('A1'), isNull);
    jobs.debugAdd(job);

    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    expect(find.textContaining('Uploading'), findsOneWidget);
    expect(find.text('x.ipa'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('elsewhere'))));
    await tester.pumpWidget(tab());
    await tester.pumpAndSettle();
    expect(find.textContaining('Uploading'), findsOneWidget, reason: 'the job outlives the tab');
    expect(find.text('Stop'), findsOneWidget);
  });
}
