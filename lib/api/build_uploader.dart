import 'dart:async';

import 'asc_client.dart';
import 'asset_upload.dart';

export 'asset_upload.dart';

// ---- Request bodies (field names checked against Apple's OpenAPI spec, App Store Connect API 4.1) -----------------

Map<String, dynamic> buildUploadBody({required String appId, required String version, required String build, String platform = 'IOS'}) => {
      'data': {
        'type': 'buildUploads',
        'attributes': {'cfBundleShortVersionString': version, 'cfBundleVersion': build, 'platform': platform},
        'relationships': {
          'app': {'data': {'type': 'apps', 'id': appId}},
        },
      },
    };

Map<String, dynamic> buildUploadFileBody({required String uploadId, required String fileName, required int fileSize}) => {
      'data': {
        'type': 'buildUploadFiles',
        'attributes': {'fileName': fileName, 'fileSize': fileSize, 'uti': 'com.apple.ipa', 'assetType': 'ASSET'},
        'relationships': {
          'buildUpload': {'data': {'type': 'buildUploads', 'id': uploadId}},
        },
      },
    };

Map<String, dynamic> commitBody({required String fileId, required String md5Hex}) => {
      'data': {
        'type': 'buildUploadFiles',
        'id': fileId,
        'attributes': {
          'uploaded': true,
          'sourceFileChecksums': {
            'file': {'hash': md5Hex, 'algorithm': 'MD5'},
          },
        },
      },
    };

// ---- Running it ---------------------------------------------------------------------------------------------------

enum UploadPhase { reserving, uploading, committing, processing, done, failed }

class UploadProgress {
  UploadProgress(this.phase, {this.sentBytes = 0, this.totalBytes = 0, this.message});
  final UploadPhase phase;
  final int sentBytes;
  final int totalBytes;
  final String? message;
}

class BuildUploader {
  BuildUploader(this.client);
  final AscClient client;

  /// Uploads [source] as a new build and waits for Apple to finish processing it.
  /// Throws [AscException] on any failure, or [UploadCancelled] if [cancel] fires before the file is committed (after
  /// that the build is Apple's: cancelling only stops waiting). [onProgress] is called as it moves through the phases.
  Future<void> upload({
    required String appId,
    required String version,
    required String build,
    required UploadSource source,
    String platform = 'IOS',
    required void Function(UploadProgress) onProgress,
    UploadCancel? cancel,
    Duration pollEvery = const Duration(seconds: 6),
    Duration giveUpAfter = const Duration(minutes: 20),
  }) async {
    final total = source.length;
    onProgress(UploadProgress(UploadPhase.reserving, totalBytes: total));
    final checksum = source.md5Hex(); // in the background while the upload is reserved and sent

    final upload = (await client.post('/v1/buildUploads', buildUploadBody(appId: appId, version: version, build: build, platform: platform))).data.first;
    cancel?.check();
    final file = (await client.post('/v1/buildUploadFiles', buildUploadFileBody(uploadId: upload.id, fileName: source.name, fileSize: total))).data.first;

    final ops = [for (final o in (file.attributes['uploadOperations'] as List? ?? const [])) UploadOp.fromJson((o as Map).cast<String, dynamic>())];
    final bad = validateOps(ops, total);
    if (bad != null) throw AscException(bad);

    onProgress(UploadProgress(UploadPhase.uploading, totalBytes: total));
    await putSourceParts(ops, source, (sent) => onProgress(UploadProgress(UploadPhase.uploading, sentBytes: sent, totalBytes: total)), cancel: cancel);
    cancel?.check();

    onProgress(UploadProgress(UploadPhase.committing, sentBytes: total, totalBytes: total));
    await client.patch('/v1/buildUploadFiles/${file.id}', commitBody(fileId: file.id, md5Hex: await checksum));

    onProgress(UploadProgress(UploadPhase.processing, sentBytes: total, totalBytes: total));
    final deadline = DateTime.now().add(giveUpAfter);
    while (true) {
      if (cancel?.cancelled ?? false) return; // committed: Apple carries on; we just stop watching
      final cur = (await client.page('/v1/buildUploads/${upload.id}')).data.first;
      final state = cur.attributes['state'] as Map?;
      final name = state?['state'] as String?;
      if (name == 'COMPLETE') {
        onProgress(UploadProgress(UploadPhase.done, sentBytes: total, totalBytes: total, message: _details(state)));
        return;
      }
      if (name == 'FAILED') {
        throw AscException('Apple rejected the build:\n${_details(state) ?? 'no details given'}');
      }
      if (DateTime.now().isAfter(deadline)) {
        throw AscException('Still processing after ${giveUpAfter.inMinutes} minutes. Check App Store Connect for the result.');
      }
      await Future<void>.delayed(pollEvery);
    }
  }

  static String? _details(Map? state) {
    if (state == null) return null;
    final lines = <String>[
      for (final k in ['errors', 'warnings', 'infos'])
        for (final e in (state[k] as List? ?? const [])) '${k == 'errors' ? 'Error' : k == 'warnings' ? 'Warning' : 'Info'}: ${(e as Map)['description'] ?? e['code']}',
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }
}
