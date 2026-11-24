import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/asc_client.dart';
import '../../api/listing.dart';
import '../../api/listing_clone.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/queries.dart';
import '../../api/screenshots.dart';
import '../theme.dart';
import '../widgets.dart';
import 'changelist_dialog.dart';

part 'listing_screenshots.dart';

class _Base {
  _Base(this.versions, this.info, this.infoLocs);
  final List<Resource> versions;
  final Resource? info;
  final List<Resource> infoLocs;
}

String? _versionState(Resource v) => v.str('appStoreState') ?? v.str('appVersionState');

/// View and edit the App Store listing. Edits are staged in [draft] (shared with the Submit tab) and only sent from the
/// changelist, so nothing changes in App Store Connect until you review and apply.
class ListingTab extends StatefulWidget {
  const ListingTab({super.key, required this.client, required this.appId, required this.draft});
  final AscClient client;
  final String appId;
  final ListingDraft draft;

  @override
  State<ListingTab> createState() => _ListingTabState();
}

class _ListingTabState extends State<ListingTab> {
  final _reload = ReloadController();
  int _epoch = 0; // bumped after applying, so every loaded list is fetched again

  @override
  void dispose() {
    _reload.dispose();
    super.dispose();
  }

  Future<_Base> _load() async {
    final c = widget.client;
    final r = await Future.wait([loadVersions(c, widget.appId), loadAppInfos(c, widget.appId)]);
    final versions = r[0].data;
    final infos = r[1].data;
    // The app info that is still editable if there is one, otherwise the live one.
    final info = infos.isEmpty
        ? null
        : infos.firstWhere((i) => isVersionEditable(i.str('appStoreState') ?? i.str('state')), orElse: () => infos.first);
    final infoLocs = info == null ? <Resource>[] : (await loadAppInfoLocalizations(c, info.id)).data;
    return _Base(versions, info, infoLocs);
  }

  Future<void> _review() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ChangelistDialog(draft: widget.draft, client: widget.client),
    );
    if (changed == true && mounted) {
      setState(() => _epoch++);
      _reload.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        ListenableBuilder(
          listenable: widget.draft,
          builder: (context, _) {
            final n = widget.draft.count;
            if (n == 0) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: t.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.colorScheme.primary.withValues(alpha: 0.18)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: t.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.edit_note_rounded, size: 18, color: t.colorScheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$n pending change${n == 1 ? '' : 's'}',
                          style: TextStyle(color: t.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        Text(
                          'Nothing is sent until you review and apply.',
                          style: TextStyle(color: t.colorScheme.onPrimaryContainer.withValues(alpha: 0.7), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  TextButton(onPressed: widget.draft.discard, child: const Text('Discard')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _review,
                    icon: const Icon(Icons.checklist, size: 16),
                    label: const Text('Review changelist'),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: LoadView<_Base>(
            controller: _reload,
            load: _load,
            builder: (context, base) {
              if (base.versions.isEmpty) {
                return const EmptyView('No App Store version to show a listing for.');
              }
              return _Editor(key: ValueKey(_epoch), client: widget.client, base: base, draft: widget.draft);
            },
          ),
        ),
      ],
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({super.key, required this.client, required this.base, required this.draft});
  final AscClient client;
  final _Base base;
  final ListingDraft draft;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  late Resource _version;
  Future<ResourcePage>? _locs;
  String? _locale;

  @override
  void initState() {
    super.initState();
    // Prefer a version that can still be edited; otherwise the newest.
    _version = widget.base.versions.firstWhere((v) => isVersionEditable(_versionState(v)), orElse: () => widget.base.versions.first);
    _locs = _loadLocs();
  }

  Future<ResourcePage> _loadLocs() => loadVersionLocalizations(widget.client, _version.id);

  Future<void> _clone(Resource source, List<Resource> locs, bool editable) async {
    final staged = await showDialog<int>(
      context: context,
      builder: (_) => CloneLocalesDialog(draft: widget.draft, source: source, locales: locs, versionEditable: editable),
    );
    if (staged == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          staged == 0
              ? 'Nothing to change: the other locales already match.'
              : 'Staged $staged change${staged == 1 ? '' : 's'}. Review them in the changelist before anything is sent.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final editable = isVersionEditable(_versionState(_version));
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
      children: [
        Row(
          children: [
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('v${_version.id}'),
                initialValue: _version.id,
                decoration: const InputDecoration(labelText: 'Version', prefixIcon: Icon(Icons.sell_outlined, size: 18)),
                items: [
                  for (final v in widget.base.versions)
                    DropdownMenuItem(
                      value: v.id,
                      child: Text('${v.str('versionString')} · ${prettyEnum(_versionState(v))}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() {
                  _version = widget.base.versions.firstWhere((v) => v.id == id);
                  _locale = null;
                  _locs = _loadLocs();
                }),
              ),
            ),
            const SizedBox(width: 12),
            StateChip(_versionState(_version)),
          ],
        ),
        const SizedBox(height: 12),
        if (!editable)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: k.inset,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: k.line),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: k.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'This version is live. Only promotional text can be changed. Other fields need a new version (Submit tab → New version).',
                    style: TextStyle(color: k.muted, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          )
        else
          Text(
            'Changes are staged locally and sent when you apply the changelist.',
            style: TextStyle(color: k.muted, fontSize: 12.5),
          ),
        const SizedBox(height: 16),
        FutureBuilder<ResourcePage>(
          future: _locs,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snap.hasError) {
              return ErrorView(error: snap.error!, onRetry: () => setState(() => _locs = _loadLocs()));
            }
            final locs = snap.requireData.data;
            if (locs.isEmpty) {
              return const EmptyView('This version has no localizations yet.');
            }
            final loc = locs.firstWhere(
              (l) => l.str('locale') == _locale,
              orElse: () => locs.firstWhere((l) => l.str('locale') == 'en-US', orElse: () => locs.first),
            );
            final infoLoc = widget.base.infoLocs.where((l) => l.str('locale') == loc.str('locale')).firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('l${_version.id}'),
                        initialValue: loc.str('locale'),
                        decoration: const InputDecoration(labelText: 'Locale', prefixIcon: Icon(Icons.language, size: 18)),
                        items: [for (final l in locs) DropdownMenuItem(value: l.str('locale'), child: Text(l.str('locale') ?? ''))],
                        onChanged: (v) => setState(() => _locale = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (locs.length > 1)
                      OutlinedButton.icon(
                        onPressed: () => _clone(loc, locs, editable),
                        icon: const Icon(Icons.copy_all_outlined, size: 17),
                        label: const Text('Clone to Other Locales'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _LocaleForm(
                  key: ValueKey('${_version.id}/${loc.id}'),
                  client: widget.client,
                  draft: widget.draft,
                  versionLoc: loc,
                  infoLoc: infoLoc,
                  versionEditable: editable,
                  infoEditable: isVersionEditable(widget.base.info?.str('appStoreState') ?? widget.base.info?.str('state')),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LocaleForm extends StatefulWidget {
  const _LocaleForm({
    super.key,
    required this.client,
    required this.draft,
    required this.versionLoc,
    required this.infoLoc,
    required this.versionEditable,
    required this.infoEditable,
  });
  final AscClient client;
  final ListingDraft draft;
  final Resource versionLoc;
  final Resource? infoLoc;
  final bool versionEditable;
  final bool infoEditable;

  @override
  State<_LocaleForm> createState() => _LocaleFormState();
}

class _LocaleFormState extends State<_LocaleForm> {
  final _ctl = <String, TextEditingController>{};

  String get _locale => widget.versionLoc.str('locale') ?? '';

  @override
  void initState() {
    super.initState();
    // Start from the staged text if this locale was edited before (the form is rebuilt when you switch locales).
    for (final f in versionFields) {
      _ctl['v.${f.key}'] = TextEditingController(
        text: widget.draft.textOverride(TextTarget.version, widget.versionLoc.id, f.key) ?? widget.versionLoc.str(f.key) ?? '',
      );
    }
    for (final f in infoFields) {
      _ctl['i.${f.key}'] = TextEditingController(
        text: widget.infoLoc == null
            ? ''
            : widget.draft.textOverride(TextTarget.info, widget.infoLoc!.id, f.key) ?? widget.infoLoc!.str(f.key) ?? '',
      );
    }
    widget.draft.addListener(_syncFromDraft);
  }

  /// When staged text is discarded (or applied), put the field back to what is on the server, so the form never shows an
  /// edit that is not in the draft.
  void _syncFromDraft() {
    void sync(String prefix, TextTarget target, Resource? src, List<ListingField> fields) {
      if (src == null) return;
      for (final f in fields) {
        final c = _ctl['$prefix.${f.key}'];
        final orig = src.str(f.key) ?? '';
        if (c != null && widget.draft.textOverride(target, src.id, f.key) == null && c.text != orig) {
          c.text = orig;
        }
      }
    }

    sync('v', TextTarget.version, widget.versionLoc, versionFields);
    sync('i', TextTarget.info, widget.infoLoc, infoFields);
  }

  @override
  void dispose() {
    widget.draft.removeListener(_syncFromDraft);
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String prefix, ListingField f, bool editable) {
    final isVersion = prefix == 'v';
    final source = isVersion ? widget.versionLoc : widget.infoLoc;
    final ctl = _ctl['$prefix.${f.key}']!;
    final isUrl = f.key.endsWith('Url');
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: ctl,
            readOnly: !editable,
            minLines: f.lines,
            maxLines: f.lines == 1 ? 1 : f.lines + 4,
            onChanged: (v) => widget.draft.setText(
              target: isVersion ? TextTarget.version : TextTarget.info,
              locId: source!.id,
              locale: _locale,
              field: f,
              before: source.str(f.key) ?? '',
              after: v,
            ),
            decoration: InputDecoration(
              labelText: f.label,
              helperText: f.helper,
              alignLabelWithHint: true,
              filled: !editable,
              prefixIcon: !editable ? const Padding(padding: EdgeInsets.only(left: 12, right: 4), child: Icon(Icons.lock_outline, size: 16)) : null,
              prefixIconConstraints: !editable ? const BoxConstraints(minWidth: 0, minHeight: 0) : null,
              suffixIcon: isUrl
                  ? IconButton(
                      icon: const Icon(Icons.open_in_new, size: 16),
                      tooltip: 'Open in browser',
                      onPressed: () => launchUrl(Uri.parse(ctl.text.trim()), mode: LaunchMode.externalApplication),
                    )
                  : null,
            ),
          ),
          if (f.max != null) _CharCount(controller: ctl, max: f.max!),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final t = Theme.of(context);
    final infoLoc = widget.infoLoc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHead(icon: Icons.info_outline, title: 'App Information', subtitle: 'Name, subtitle and privacy policy'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (infoLoc == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('No app-info localization for this locale.', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                  )
                else ...[
                  if (!widget.infoEditable)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: k.inset,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: k.line),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: k.muted),
                          const SizedBox(width: 8),
                          Text(
                            'Name and subtitle can only change in a version being prepared.',
                            style: TextStyle(color: k.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  for (final f in infoFields) _field('i', f, widget.infoEditable),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        _SectionHead(icon: Icons.description_outlined, title: 'Version Listing', subtitle: 'Description, keywords and release notes'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final f in versionFields) _field('v', f, isFieldEditable(f.key, versionEditable: widget.versionEditable)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        _SectionHead(icon: Icons.photo_library_outlined, title: 'Screenshots', subtitle: 'App Store screenshots by device'),
        _ShotsEditor(
          client: widget.client,
          draft: widget.draft,
          versionLocId: widget.versionLoc.id,
          locale: _locale,
          editable: widget.versionEditable,
        ),
      ],
    );
  }
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.icon, required this.title, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(7)),
            child: Icon(icon, size: 16, color: k.accentInk),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: k.ink)),
              if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: k.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _CharCount extends StatelessWidget {
  const _CharCount({required this.controller, required this.max});
  final TextEditingController controller;
  final int max;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final len = controller.text.length;
        final ratio = (len / max).clamp(0.0, 1.0);
        final over = len > max;
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 3,
                    backgroundColor: k.line,
                    color: over ? Theme.of(context).colorScheme.error : (ratio > 0.85 ? k.warn : k.accent),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$len / $max',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: over ? Theme.of(context).colorScheme.error : k.muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
