import 'package:flutter/foundation.dart';

import '../api/asc_client.dart';
import '../api/build_uploader.dart';
import '../api/ipa_info.dart';

/// One build upload. It lives outside the Upload tab, so switching tabs or going back to the apps list does not lose it.
class UploadJob extends ChangeNotifier {
  UploadJob({required this.appId, required this.info, required this.source});
  final String appId;
  final IpaInfo info;
  final UploadSource source;

  UploadProgress? progress;
  String? failure;
  bool cancelled = false;
  final _cancel = UploadCancel();

  bool get finished => progress?.phase == UploadPhase.done || progress?.phase == UploadPhase.stillProcessing;
  bool get running => progress != null && !finished && failure == null && !cancelled;

  /// Past this point Apple has the file; cancelling only stops watching it process.
  bool get committed => progress != null && (progress!.phase == UploadPhase.processing || finished);

  /// Run the upload. [pollEvery] and [giveUpAfter] are for tests.

  void cancel() {
    _cancel.cancel();
    cancelled = true;
    notifyListeners();
  }

  Future<void> run(AscClient client, {Duration pollEvery = const Duration(seconds: 6), Duration giveUpAfter = const Duration(minutes: 30)}) async {
    progress = UploadProgress(UploadPhase.reserving, totalBytes: source.length);
    notifyListeners();
    // Its own copy of the client: renaming or locking closes the shell's client, and must not cut an upload short.
    final own = client.detached();
    try {
      await BuildUploader(own).upload(
        appId: appId,
        version: info.version,
        build: info.build,
        platform: info.platform,
        source: source,
        cancel: _cancel,
        pollEvery: pollEvery,
        giveUpAfter: giveUpAfter,
        onProgress: (p) {
          progress = p;
          notifyListeners();
        },
      );
    } on UploadCancelled {
      cancelled = true;
    } on AscException catch (e) {
      failure = e.message;
    } catch (e) {
      failure = '$e';
    } finally {
      own.close();
      notifyListeners();
    }
  }
}

/// The uploads of one client, by app.
class UploadJobs extends ChangeNotifier {
  final _jobs = <String, UploadJob>{};

  UploadJob? forApp(String appId) => _jobs[appId];

  /// Starts [job] unless one is already running for that app.
  UploadJob? start(UploadJob job, AscClient client) {
    if (_jobs[job.appId]?.running ?? false) return null;
    _jobs[job.appId] = job;
    job.addListener(notifyListeners);
    job.run(client);
    notifyListeners();
    return job;
  }

  void clear(String appId) {
    final j = _jobs[appId];
    if (j == null || j.running) return;
    _jobs.remove(appId);
    notifyListeners();
  }

  bool get anyRunning => _jobs.values.any((j) => j.running);
}
