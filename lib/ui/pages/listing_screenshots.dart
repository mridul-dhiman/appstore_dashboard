part of 'listing_tab.dart';

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

  List<Resource> get _others => [
    for (final l in widget.locales)
      if (l.id != widget.source.id) l,
  ];

  List<CloneEdit> get _plan => planClone(
    sourceText: _text,
    targets: [
      for (final l in _others)
        if (_targets.contains(l.id)) l,
    ],
    fields: [
      for (final f in cloneableFields)
        if (_fields.contains(f.key)) f,
    ],
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SectionLabel('Copy', padding: EdgeInsets.only(bottom: 4)),
              for (final f in cloneableFields)
                Builder(
                  builder: (context) {
                    final can = isFieldEditable(f.key, versionEditable: widget.versionEditable);
                    final empty = _text(f.key).isEmpty;
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _fields.contains(f.key),
                      title: Text(f.label),
                      subtitle: Text(
                        !can
                            ? 'Only editable on a version being prepared.'
                            : (empty ? 'Empty in ${widget.source.str('locale')}.' : _text(f.key).replaceAll('\n', ' ')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: !can || empty ? null : (v) => setState(() => v == true ? _fields.add(f.key) : _fields.remove(f.key)),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(child: SectionLabel('To', padding: EdgeInsets.only(bottom: 4))),
                  TextButton(
                    onPressed: () =>
                        setState(() => _targets.length == others.length ? _targets.clear() : _targets.addAll(others.map((l) => l.id))),
                    child: Text(_targets.length == others.length ? 'Clear all' : 'Select all'),
                  ),
                ],
              ),
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
                      ? (_fields.isEmpty || _targets.isEmpty
                            ? 'Pick what to copy and where to.'
                            : 'The chosen locales already have this text.')
                      : '${plan.length} change${plan.length == 1 ? '' : 's'} will be staged${plan.any((e) => e.before.isNotEmpty) ? ', replacing existing text in ${plan.where((e) => e.before.isNotEmpty).length}' : ''}. Nothing is sent until you apply the changelist.',
                  style: TextStyle(color: k.muted, fontSize: 13),
                ),
              ),
            ],
          ),
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
