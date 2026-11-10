import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/listing.dart';
import '../../api/listing_clone.dart';
import '../../api/listing_draft.dart';
import '../../api/models.dart';
import '../../api/screenshots.dart';
import '../theme.dart';
import '../widgets.dart';
import 'changelist_dialog.dart';

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
    final r = await Future.wait([
      c.page('/v1/apps/${widget.appId}/appStoreVersions', {'limit': '20'}),
      c.page('/v1/apps/${widget.appId}/appInfos', {'limit': '10'}),
    ]);
    final versions = r[0].data;
    final infos = r[1].data;
    // The app info that is still editable if there is one, otherwise the live one.
    final info = infos.isEmpty
        ? null
        : infos.firstWhere((i) => isVersionEditable(i.str('appStoreState') ?? i.str('state')), orElse: () => infos.first);
    final infoLocs = info == null ? <Resource>[] : (await c.all('/v1/appInfos/${info.id}/appInfoLocalizations', {'limit': '200'}, 2)).data;
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
              width: double.infinity,
              color: t.colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: t.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$n pending change${n == 1 ? '' : 's'}. Nothing is sent until you apply the changelist.',
                      style: TextStyle(color: t.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(onPressed: widget.draft.discard, child: const Text('Discard all')),
                  const SizedBox(width: 6),
                  FilledButton(onPressed: _review, child: const Text('Review changelist')),
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

  Future<ResourcePage> _loadLocs() =>
      widget.client.all('/v1/appStoreVersions/${_version.id}/appStoreVersionLocalizations', {'limit': '200'}, 2);

  Future<void> _clone(Resource source, List<Resource> locs, bool editable) async {
    final staged = await showDialog<int>(
      context: context,
      builder: (_) => CloneLocalesDialog(draft: widget.draft, source: source, locales: locs, versionEditable: editable),
    );
    if (staged == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(staged == 0 ? 'Nothing to change: the other locales already match.' : 'Staged $staged change${staged == 1 ? '' : 's'}. Review them in the changelist before anything is sent.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final editable = isVersionEditable(_versionState(_version));
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('v${_version.id}'),
                initialValue: _version.id,
                decoration: const InputDecoration(labelText: 'Version'),
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
            StateChip(_versionState(_version)),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          editable ? 'This version can be edited. Changes are staged until you apply the changelist.' : 'This version is not editable. Only the promotional text can be changed; text and screenshots need a new version (Submit tab → New version).',
          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
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
                Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey('l${_version.id}'),
                      initialValue: loc.str('locale'),
                      decoration: const InputDecoration(labelText: 'Locale'),
                      items: [for (final l in locs) DropdownMenuItem(value: l.str('locale'), child: Text(l.str('locale') ?? ''))],
                      onChanged: (v) => setState(() => _locale = v),
                    ),
                  ),
                  if (locs.length > 1)
                    OutlinedButton.icon(
                      onPressed: () => _clone(loc, locs, editable),
                      icon: const Icon(Icons.copy_all_outlined, size: 17),
                      label: const Text('Clone to Other Locales'),
                    ),
                ]),
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
        text: widget.draft.textOverride('version', widget.versionLoc.id, f.key) ?? widget.versionLoc.str(f.key) ?? '',
      );
    }
    for (final f in infoFields) {
      _ctl['i.${f.key}'] = TextEditingController(
        text: widget.infoLoc == null
            ? ''
            : widget.draft.textOverride('info', widget.infoLoc!.id, f.key) ?? widget.infoLoc!.str(f.key) ?? '',
      );
    }
    widget.draft.addListener(_syncFromDraft);
  }

  /// When staged text is discarded (or applied), put the field back to what is on the server, so the form never shows an
  /// edit that is not in the draft.
  void _syncFromDraft() {
    void sync(String prefix, String target, Resource? src, List<ListingField> fields) {
      if (src == null) return;
      for (final f in fields) {
        final c = _ctl['$prefix.${f.key}'];
        final orig = src.str(f.key) ?? '';
        if (c != null && widget.draft.textOverride(target, src.id, f.key) == null && c.text != orig) {
          c.text = orig;
        }
      }
    }

    sync('v', 'version', widget.versionLoc, versionFields);
    sync('i', 'info', widget.infoLoc, infoFields);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _ctl['$prefix.${f.key}'],
        readOnly: !editable,
        minLines: f.lines,
        maxLines: f.lines == 1 ? 1 : f.lines + 4,
        maxLength: f.max,
        onChanged: (v) => widget.draft.setText(
          target: isVersion ? 'version' : 'info',
          locId: source!.id,
          locale: _locale,
          field: f,
          before: source.str(f.key) ?? '',
          after: v,
        ),
        decoration: InputDecoration(
          labelText: f.label + (editable ? '' : ' (read only)'),
          helperText: f.helper,
          alignLabelWithHint: true,
          filled: !editable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final infoLoc = widget.infoLoc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('App information', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (infoLoc == null)
                  Text('No app-info localization for this locale.', style: TextStyle(color: t.colorScheme.onSurfaceVariant))
                else ...[
                  if (!widget.infoEditable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Name and subtitle can only change in a version being prepared.',
                        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  for (final f in infoFields) _field('i', f, widget.infoEditable),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version listing', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final f in versionFields) _field('v', f, isFieldEditable(f.key, versionEditable: widget.versionEditable)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Screenshots', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
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

class _ShotsEditor extends StatelessWidget {
  const _ShotsEditor({required this.client, required this.draft, required this.versionLocId, required this.locale, required this.editable});
  final AscClient client;
  final ListingDraft draft;
  final String versionLocId;
  final String locale;
  final bool editable;

  Future<void> _add(BuildContext context, String group, ScreenshotSpecs? specs) async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
    final picked = <({String name, Uint8List bytes})>[];
    final problems = <String>[];
    for (final f in files) {
      if (!isAllowedScreenshotName(f.name)) continue;
      final bytes = await f.readAsBytes();
      final size = imageSize(bytes);
      if (size == null) {
        problems.add('${f.name} is not a readable PNG or JPEG.');
      } else if (specs != null && !specs.accepts(group, size.w, size.h)) {
        final wanted = specs.sizesLabel(group);
        problems.add('${f.name} is ${size.w}×${size.h}, but ${placementGroupLabel(group)} takes $wanted.');
      } else {
        picked.add((name: f.name, bytes: bytes));
      }
    }
    if (picked.isNotEmpty) {
      draft.addShots(ListingDraft.setKey(versionLocId, group), picked);
    }
    if (problems.isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problems.join('\n'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return LoadView<ScreenshotSpecs?>(
      load: () async {
        final results = await Future.wait<Object?>([
          client.all('/v1/appStoreVersionLocalizations/$versionLocId/placements', {
            'filter[placementType]': screenshotPlacementType,
            'include': 'image',
            'sort': 'placementGroupPosition',
            'limit': '200',
          }),
          // Only needed to validate sizes and offer more device groups; the editor still works without it.
          loadScreenshotSpecs(client).then<ScreenshotSpecs?>((x) => x).catchError((_) => null),
        ]);
        final p = results[0] as ResourcePage;
        final byGroup = <String, List<ShotItem>>{};
        for (final pl in p.data) {
          final group = pl.str('placementGroup');
          if (group == null) continue;
          final image = p.inc('appAssetLibraryImages', pl.relId('image'));
          final asset = (image?.attributes['imageAsset'] as Map?);
          (byGroup[group] ??= []).add(
            ShotItem.existing(
              id: pl.id,
              name: image?.str('fileName') ?? pl.id,
              url: thumbnailUrl(asset?['templateUrl'] as String?, asset?['width'] as int?, asset?['height'] as int?),
            ),
          );
        }
        for (final e in byGroup.entries) {
          draft.ensureShotSet(
            ListingDraft.setKey(versionLocId, e.key),
            () => ShotSetDraft(exists: true, group: e.key, versionLocId: versionLocId, locale: locale, items: e.value),
          );
        }
        return results[1] as ScreenshotSpecs?;
      },
      builder: (context, specs) => ListenableBuilder(
        listenable: draft,
        builder: (context, _) {
          final sets = draft.setsFor(versionLocId);
          final used = sets.map((s) => s.group).toSet();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sets.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('No screenshots for this locale.', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
                ),
              if (!editable && sets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Screenshots can only change in a version being prepared.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ),
              for (final s in sets) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Row(
                    children: [
                      Text('${placementGroupLabel(s.group)}  ·  ${s.liveCount}/$maxScreenshotsPerSet', style: t.textTheme.titleSmall),
                      const SizedBox(width: 12),
                      if (editable)
                        TextButton.icon(
                          onPressed: s.liveCount >= maxScreenshotsPerSet ? null : () => _add(context, s.group, specs),
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                          label: const Text('Add'),
                        ),
                      if (!s.exists) const StateChip('PENDING', label: 'New group'),
                      if (specs != null && specs.sizesByGroup.containsKey(s.group))
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            specs.sizesLabel(s.group),
                            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 262,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < s.items.length; i++)
                        _ShotTile(
                          item: s.items[i],
                          editable: editable,
                          onLeft: i == 0 ? null : () => draft.move(ListingDraft.setKey(versionLocId, s.group), i, -1),
                          onRight: i == s.items.length - 1 ? null : () => draft.move(ListingDraft.setKey(versionLocId, s.group), i, 1),
                          onDelete: () => draft.toggleDelete(ListingDraft.setKey(versionLocId, s.group), i),
                        ),
                    ],
                  ),
                ),
              ],
              if (editable && specs != null) ...[
                const SizedBox(height: 12),
                PopupMenuButton<String>(
                  tooltip: 'Add screenshots for another device size',
                  onSelected: (group) {
                    draft.ensureShotSet(
                      ListingDraft.setKey(versionLocId, group),
                      () => ShotSetDraft(exists: false, group: group, versionLocId: versionLocId, locale: locale, items: []),
                    );
                    draft.touch();
                  },
                  itemBuilder: (_) => [
                    for (final g
                        in (specs.groups.where((x) => !used.contains(x)).toList()..sort((a, b) {
                          final r = placementGroupRank(a).compareTo(placementGroupRank(b));
                          return r != 0 ? r : a.compareTo(b);
                        })))
                      PopupMenuItem(value: g, child: Text('${placementGroupLabel(g)}  ·  ${specs.sizesLabel(g)}')),
                  ],
                  child: const Chip(avatar: Icon(Icons.add, size: 18), label: Text('Add a device size')),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ShotTile extends StatelessWidget {
  const _ShotTile({required this.item, required this.editable, required this.onLeft, required this.onRight, required this.onDelete});
  final ShotItem item;
  final bool editable;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: 110,
      color: cs.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant),
    );
    final Widget image = item.bytes != null
        ? Image.memory(item.bytes!, height: 210, fit: BoxFit.fitHeight, errorBuilder: (_, _, _) => placeholder)
        : item.url == null
        ? placeholder
        : Image.network(item.url!, height: 210, fit: BoxFit.fitHeight, errorBuilder: (_, _, _) => placeholder);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Opacity(opacity: item.deleted ? 0.3 : 1, child: image),
                ),
                if (item.isNew) const Positioned(left: 6, top: 6, child: StateChip('PENDING', label: 'New')),
                if (item.deleted) const Positioned(left: 6, top: 6, child: StateChip('REJECTED', label: 'Removed')),
              ],
            ),
          ),
          if (editable)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Move left',
                  onPressed: onLeft,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: item.deleted ? 'Restore' : (item.isNew ? 'Discard' : 'Remove'),
                  onPressed: onDelete,
                  icon: Icon(item.deleted ? Icons.restore : Icons.delete_outline),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Move right',
                  onPressed: onRight,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Copies release notes and promotional text from one locale to others. It only stages edits; the changelist sends them.
class CloneLocalesDialog extends StatefulWidget {
  const CloneLocalesDialog({super.key, required this.draft, required this.source, required this.locales, required this.versionEditable});
  final ListingDraft draft;
  final Resource source;
  final List<Resource> locales;
  final bool versionEditable;

  @override
  State<CloneLocalesDialog> createState() => _CloneLocalesDialogState();
}

class _CloneLocalesDialogState extends State<CloneLocalesDialog> {
  late final Set<String> _fields = {
    for (final f in cloneableFields)
      if (isFieldEditable(f.key, versionEditable: widget.versionEditable) && _text(f.key).isNotEmpty) f.key,
  };
  final _targets = <String>{};

  /// The source text as the person currently sees it, staged edits included.
  String _text(String key) => (widget.draft.textOverride('version', widget.source.id, key) ?? widget.source.str(key) ?? '').trim();

  List<Resource> get _others => [for (final l in widget.locales) if (l.id != widget.source.id) l];

  List<CloneEdit> get _plan => planClone(
        sourceText: _text,
        targets: [for (final l in _others) if (_targets.contains(l.id)) l],
        fields: [for (final f in cloneableFields) if (_fields.contains(f.key)) f],
        versionEditable: widget.versionEditable,
      );

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final plan = _plan;
    final others = _others;
    return AlertDialog(
      title: Text('Clone ${widget.source.str('locale')} to other locales'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const SectionLabel('Copy', padding: EdgeInsets.only(bottom: 4)),
            for (final f in cloneableFields)
              Builder(builder: (context) {
                final can = isFieldEditable(f.key, versionEditable: widget.versionEditable);
                final empty = _text(f.key).isEmpty;
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _fields.contains(f.key),
                  title: Text(f.label),
                  subtitle: Text(!can ? 'Only editable on a version being prepared.' : (empty ? 'Empty in ${widget.source.str('locale')}.' : _text(f.key).replaceAll('\n', ' ')), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onChanged: !can || empty ? null : (v) => setState(() => v == true ? _fields.add(f.key) : _fields.remove(f.key)),
                );
              }),
            const SizedBox(height: 12),
            Row(children: [
              const Expanded(child: SectionLabel('To', padding: EdgeInsets.only(bottom: 4))),
              TextButton(
                onPressed: () => setState(() => _targets.length == others.length ? _targets.clear() : _targets.addAll(others.map((l) => l.id))),
                child: Text(_targets.length == others.length ? 'Clear all' : 'Select all'),
              ),
            ]),
            for (final l in others)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _targets.contains(l.id),
                title: Text(l.str('locale') ?? l.id),
                onChanged: (v) => setState(() => v == true ? _targets.add(l.id) : _targets.remove(l.id)),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: k.inset, borderRadius: BorderRadius.circular(8)),
              child: Text(
                plan.isEmpty
                    ? (_fields.isEmpty || _targets.isEmpty ? 'Pick what to copy and where to.' : 'The chosen locales already have this text.')
                    : '${plan.length} change${plan.length == 1 ? '' : 's'} will be staged${plan.any((e) => e.before.isNotEmpty) ? ', replacing existing text in ${plan.where((e) => e.before.isNotEmpty).length}' : ''}. Nothing is sent until you apply the changelist.',
                style: TextStyle(color: k.muted, fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _fields.isEmpty || _targets.isEmpty ? null : () => Navigator.pop(context, stageClone(widget.draft, plan)),
          child: const Text('Stage changes'),
        ),
      ],
    );
  }
}
