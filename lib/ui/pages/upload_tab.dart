
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/build_uploader.dart';
import '../../api/ipa_info.dart';
import '../../api/models.dart';
import '../widgets.dart';

/// Upload an .ipa to App Store Connect (it lands in TestFlight once processed), and see earlier uploads.
class UploadTab extends StatefulWidget {
  const UploadTab({super.key, required this.client, required this.appId, required this.bundleId});
  final AscClient client;
  final String appId;
  final String bundleId;

  @override
  State<UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<UploadTab> {
  final _history = ReloadController();
  String? _fileName;
  Uint8List? _bytes;
  IpaInfo? _info;
  String? _pickError;

  UploadProgress? _progress;
  String? _failure;
  bool get _running => _progress != null && _progress!.phase != UploadPhase.done && _failure == null;

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _pickError = null);
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['ipa']);
    if (f == null) return;
    try {
      final bytes = await f.readAsBytes();
      final info = readIpaInfo(bytes);
      setState(() {
        _fileName = f.name;
        _bytes = bytes;
        _info = info;
        _progress = null;
        _failure = null;
      });
    } on IpaException catch (e) {
      setState(() {
        _bytes = null;
        _info = null;
        _pickError = e.message;
      });
    }
  }

  Future<void> _upload() async {
    final info = _info!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upload ${info.version} (${info.build})?'),
        content: Text('This sends ${(_bytes!.length / 1048576).toStringAsFixed(1)} MB to App Store Connect now. Once it is processed the build appears in TestFlight, '
            'and a build can never be deleted, only left to expire.\n\nA build number that already exists for this version will be refused.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _failure = null;
      _progress = UploadProgress(UploadPhase.reserving, totalBytes: _bytes!.length);
    });
    try {
      await BuildUploader(widget.client).upload(
        appId: widget.appId,
        version: info.version,
        build: info.build,
        fileName: _fileName!,
        bytes: _bytes!,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      _history.reload();
    } on AscException catch (e) {
      if (mounted) setState(() => _failure = e.message);
      _history.reload();
    } catch (e) {
      if (mounted) setState(() => _failure = '$e');
    }
  }

  String _phaseLabel(UploadProgress p) => switch (p.phase) {
        UploadPhase.reserving => 'Reserving the upload…',
        UploadPhase.uploading => 'Uploading ${(p.sentBytes / 1048576).toStringAsFixed(1)} / ${(p.totalBytes / 1048576).toStringAsFixed(1)} MB',
        UploadPhase.committing => 'Finishing the upload…',
        UploadPhase.processing => 'Apple is processing the build…',
        UploadPhase.done => 'Processed. The build is on its way to TestFlight.',
        UploadPhase.failed => 'Failed',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final info = _info;
    final mismatch = info != null && info.bundleId != widget.bundleId;
    return ListView(padding: const EdgeInsets.all(40), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Upload a build', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Pick the .ipa from your archive export. The version and build number are read from the file.',
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (kIsWeb)
              Text(
                'Uploading builds needs the desktop app: Apple\'s upload servers cannot be reached from a browser page. The upload history below still works here.',
                style: TextStyle(color: t.colorScheme.error),
              )
            else ...[
              Row(children: [
                OutlinedButton.icon(onPressed: _running ? null : _pick, icon: const Icon(Icons.upload_file), label: const Text('Choose .ipa')),
                const SizedBox(width: 12),
                if (_fileName != null) Flexible(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
              ]),
              if (_pickError != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_pickError!, style: TextStyle(color: t.colorScheme.error))),
              if (info != null) ...[
                const SizedBox(height: 16),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  SizedBox(width: 200, child: Stat(label: 'Version', value: info.version, icon: Icons.sell_outlined)),
                  SizedBox(width: 200, child: Stat(label: 'Build', value: info.build, icon: Icons.tag)),
                  SizedBox(width: 200, child: Stat(label: 'Minimum iOS', value: info.minOs ?? '—', icon: Icons.phone_iphone)),
                ]),
                const SizedBox(height: 10),
                if (mismatch)
                  Text('This .ipa is for ${info.bundleId}, but this app is ${widget.bundleId}. Apple will reject it.', style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600))
                else
                  Text('Bundle ID ${info.bundleId} matches this app.', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: (_running || mismatch || _progress?.phase == UploadPhase.done) ? null : _upload,
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text('Upload ${info.version} (${info.build})'),
                ),
              ],
              if (_progress != null) ...[
                const SizedBox(height: 18),
                if (_running)
                  LinearProgressIndicator(
                    value: _progress!.phase == UploadPhase.uploading && _progress!.totalBytes > 0 ? _progress!.sentBytes / _progress!.totalBytes : null,
                  ),
                const SizedBox(height: 8),
                Text(_failure != null ? 'Upload failed' : _phaseLabel(_progress!), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: _failure != null ? t.colorScheme.error : null)),
                if (_failure != null) SelectableText(_failure!, style: TextStyle(color: t.colorScheme.error)),
                if (_progress!.message != null) SelectableText(_progress!.message!),
              ],
            ],
          ]),
        ),
      ),
      const SizedBox(height: 24),
      Row(children: [
        Expanded(child: Text('Upload history', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
        IconButton(tooltip: 'Refresh', onPressed: _history.reload, icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 360,
        child: LoadView<ResourcePage>(
          controller: _history,
          load: () => widget.client.page('/v1/apps/${widget.appId}/buildUploads', {'limit': '25'}),
          builder: (context, p) {
            if (p.data.isEmpty) return const EmptyView('No uploads made through the API yet.\nBuilds sent from Xcode or Transporter are in the Builds tab.', icon: Icons.cloud_upload_outlined);
            final rows = [...p.data]..sort((a, b) => (b.date('createdDate') ?? DateTime(0)).compareTo(a.date('createdDate') ?? DateTime(0)));
            return ListView(children: [
              RowsCard(children: [
                for (final u in rows)
                  ListTile(
                    leading: const Icon(Icons.cloud_done_outlined),
                    title: Text('${u.str('cfBundleShortVersionString')} (${u.str('cfBundleVersion')})', style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${prettyPlatform(u.str('platform'))} · created ${fmtDateTime(u.date('createdDate'))}'),
                    trailing: StateChip((u.attributes['state'] as Map?)?['state'] as String?),
                  ),
              ]),
            ]);
          },
        ),
      ),
    ]);
  }
}
