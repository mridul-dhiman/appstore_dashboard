import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/build_uploader.dart';
import '../../api/ipa_info.dart';
import '../../api/models.dart';
import '../../api/queries.dart';
import '../../services/file_source.dart';
import '../../state/upload_jobs.dart';
import '../theme.dart';
import '../widgets.dart';

/// Upload an .ipa to App Store Connect (it lands in TestFlight once processed), and see earlier uploads.
class UploadTab extends StatefulWidget {
  const UploadTab({super.key, required this.client, required this.appId, required this.bundleId, required this.uploads});
  final AscClient client;
  final String appId;
  final String bundleId;

  /// Where the running upload lives, so it survives leaving this tab.
  final UploadJobs uploads;

  @override
  State<UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<UploadTab> {
  final _history = ReloadController();
  UploadSource? _source;
  IpaInfo? _info;
  String? _pickError;
  bool _reading = false;
  UploadJob? _watched;

  UploadJob? get _job => widget.uploads.forApp(widget.appId);
  bool get _running => _job?.running ?? false;

  @override
  void initState() {
    super.initState();
    widget.uploads.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    widget.uploads.removeListener(_changed);
    _history.dispose();
    super.dispose();
  }

  void _changed() {
    final j = _job;
    // Reload the history once, when an upload stops running.
    if (_watched != null && _watched == j && !j!.running) {
      _watched = null;
      _history.reload();
    }
    if (j != null && j.running) _watched = j;
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    setState(() => _pickError = null);
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['ipa']);
    if (f == null) return;
    setState(() => _reading = true);
    try {
      final UploadSource source;
      final IpaInfo info;
      if (fileSourcesSupported && f.path != null) {
        // Read from disk in ranges, off the UI thread: the .ipa is never loaded whole.
        source = FileSource(f.path!, name: f.name);
        info = await readIpaInfoFromFile(f.path!);
      } else {
        final bytes = await f.readAsBytes();
        source = BytesSource(f.name, bytes);
        info = readIpaInfo(bytes);
      }
      setState(() {
        _source = source;
        _info = info;
        widget.uploads.clear(widget.appId);
      });
    } on IpaException catch (e) {
      setState(() {
        _source = null;
        _info = null;
        _pickError = e.message;
      });
    } catch (e) {
      setState(() => _pickError = 'Could not read the file: $e');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _upload() async {
    final info = _info!;
    final source = _source!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Upload ${info.version} (${info.build})?'),
        content: Text(
          'This sends ${(source.length / 1048576).toStringAsFixed(1)} MB to App Store Connect now. Once it is processed the build appears in TestFlight, '
          'and a build can never be deleted, only left to expire.\n\nA build number that already exists for this version will be refused.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.uploads.start(UploadJob(appId: widget.appId, info: info, source: source), widget.client);
  }

  Future<void> _cancel() async {
    final job = _job;
    if (job == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop this upload?'),
        content: Text(
          job.committed
              ? 'Apple already has the file and keeps processing it. This only stops watching here; the build still appears in the Builds tab.'
              : 'The upload stops before the file is finished. Nothing reaches TestFlight.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
        ],
      ),
    );
    if (ok == true) job.cancel();
  }

  String _phaseLabel(UploadProgress p) => switch (p.phase) {
    UploadPhase.reserving => 'Reserving the upload…',
    UploadPhase.uploading => 'Uploading ${(p.sentBytes / 1048576).toStringAsFixed(1)} / ${(p.totalBytes / 1048576).toStringAsFixed(1)} MB',
    UploadPhase.committing => 'Finishing the upload…',
    UploadPhase.processing => 'Apple is processing the build…',
    UploadPhase.stillProcessing =>
      'Uploaded. Apple is taking a while to process it; the Builds tab shows it as Processing and updates by itself.',
    UploadPhase.done => 'Processed. The build is on its way to TestFlight.',
    UploadPhase.failed => 'Failed',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final job = _job;
    // While an upload runs (or just finished) show what it is uploading, even after leaving and coming back.
    final info = job?.info ?? _info;
    final progress = job?.progress;
    final failure = job?.failure;
    final mismatch = info != null && info.bundleId != widget.bundleId;
    final k = Tokens.of(context);
    final upload = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                decoration: BoxDecoration(
                  color: k.inset,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: k.line, width: 1.5),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: k.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: k.line),
                      ),
                      child: Icon(Icons.cloud_upload_outlined, color: k.accent),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _running || _reading ? null : _pick,
                      icon: _reading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.upload_file),
                      label: const Text('Choose .ipa'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (job?.source ?? _source)?.name ?? 'An .ipa exported from an Xcode archive',
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: k.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              if (_pickError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_pickError!, style: TextStyle(color: t.colorScheme.error)),
                ),
              if (info != null) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 200,
                      child: Stat(label: 'Version', value: info.version, icon: Icons.sell_outlined),
                    ),
                    SizedBox(
                      width: 200,
                      child: Stat(label: 'Build', value: info.build, icon: Icons.tag),
                    ),
                    SizedBox(
                      width: 200,
                      child: Stat(label: 'Minimum iOS', value: info.minOs ?? '—', icon: Icons.phone_iphone),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (mismatch)
                  Text(
                    'This .ipa is for ${info.bundleId}, but this app is ${widget.bundleId}. Apple will reject it.',
                    style: TextStyle(color: t.colorScheme.error, fontWeight: FontWeight.w600),
                  )
                else
                  Text('Bundle ID ${info.bundleId} matches this app.', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: (_running || mismatch || job?.finished == true || _source == null) ? null : _upload,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text('Upload ${info.version} (${info.build})'),
                    ),
                    if (_running) ...[const SizedBox(width: 10), TextButton(onPressed: _cancel, child: const Text('Stop'))],
                  ],
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 18),
                if (_running)
                  LinearProgressIndicator(
                    value: progress.phase == UploadPhase.uploading && progress.totalBytes > 0
                        ? progress.sentBytes / progress.totalBytes
                        : null,
                  ),
                const SizedBox(height: 8),
                Text(
                  failure != null
                      ? 'Upload failed'
                      : job!.cancelled
                      ? (job.committed
                            ? 'Stopped watching. Apple is still processing it; see the Builds tab.'
                            : 'Upload stopped. Nothing was sent to TestFlight.')
                      : _phaseLabel(progress),
                  style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: failure != null ? t.colorScheme.error : null),
                ),
                if (failure != null) SelectableText(failure, style: TextStyle(color: t.colorScheme.error)),
                if (progress.message != null) SelectableText(progress.message!),
              ],
            ],
          ],
        ),
      ),
    );
    final history = Card(
      clipBehavior: Clip.antiAlias,
      child: LoadView<ResourcePage>(
        controller: _history,
        load: () => loadBuildUploadHistory(widget.client, widget.appId),
        builder: (context, p) {
          final rows = [...p.data]..sort((a, b) => (b.date('createdDate') ?? DateTime(0)).compareTo(a.date('createdDate') ?? DateTime(0)));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 12),
                child: Row(
                  children: [
                    Text(
                      'Upload history',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: k.ink),
                    ),
                    const SizedBox(width: 8),
                    if (rows.isNotEmpty) StateChip(null, label: '${rows.length} total'),
                    const Spacer(),
                    IconButton(tooltip: 'Refresh', onPressed: _history.reload, icon: const Icon(Icons.refresh, size: 18)),
                  ],
                ),
              ),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: EmptyView(
                    'No uploads made through the API yet.\nBuilds sent from Xcode or Transporter are in the Builds tab.',
                    icon: Icons.cloud_upload_outlined,
                  ),
                ),
              for (final u in rows) ...[const Divider(), _historyRow(u)],
            ],
          );
        },
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    return ListView(
      padding: const EdgeInsets.all(40),
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: upload),
              const SizedBox(width: 16),
              SizedBox(width: 400, child: history),
            ],
          )
        else ...[
          upload,
          const SizedBox(height: 16),
          history,
        ],
      ],
    );
  }

  Widget _historyRow(Resource u) {
    final k = Tokens.of(context);
    final state = (u.attributes['state'] as Map?)?.cast<String, dynamic>();
    List<String> messages(String key) => [
      for (final e in (state?[key] as List?) ?? const []) ((e as Map)['description'] ?? e['code'] ?? '').toString(),
    ];
    final errors = messages('errors');
    final warnings = messages('warnings');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: u.str('cfBundleShortVersionString') ?? '—',
                      style: TextStyle(fontWeight: FontWeight.w700, color: k.ink),
                    ),
                    TextSpan(
                      text: '  (${u.str('cfBundleVersion') ?? '—'})',
                      style: TextStyle(color: k.muted),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              StateChip(state?['state'] as String?),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${prettyPlatform(u.str('platform'))} · ${fmtDateTime(u.date('createdDate'))}',
            style: TextStyle(color: k.muted, fontSize: 12.5),
          ),
          if (errors.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: k.badSoft, borderRadius: BorderRadius.circular(8)),
              child: Text(
                errors.first,
                style: TextStyle(color: k.bad, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          if (warnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Tooltip(
                message: warnings.join('\n\n'),
                child: StateChip('WAITING', label: '${warnings.length} warning${warnings.length == 1 ? '' : 's'}'),
              ),
            ),
        ],
      ),
    );
  }
}
