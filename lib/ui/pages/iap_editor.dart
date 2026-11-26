import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../api/asc_client.dart';
import '../../api/iap_creator.dart';
import '../../api/iap_editor.dart';
import '../../api/listing.dart' show thumbnailUrl;
import '../../api/models.dart';
import '../../api/screenshots.dart' show imageSize;
import '../../api/territories.dart';
import '../theme.dart';
import '../widgets.dart';

/// Edit one in-app purchase: its metadata, localizations, price, availability and App Review screenshot. Edits are
/// kept on the page and sent together with Save changes.
class IapEditor extends StatefulWidget {
  const IapEditor({super.key, required this.client, required this.iapId, required this.onBack, this.onChanged, this.onDirtyChanged});
  final AscClient client;
  final String iapId;

  /// Back to the list. The editor asks first when there are unsaved edits.
  final VoidCallback onBack;

  /// Something was saved, submitted or deleted, so the list should reload.
  final VoidCallback? onChanged;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<IapEditor> createState() => _IapEditorState();
}

class _IapEditorState extends State<IapEditor> {
  IapDraft? _draft;
  Object? _error;
  bool _busy = false;
  String? _step;
  String _locale = '';

  final _name = TextEditingController();
  final _note = TextEditingController();
  final _locName = TextEditingController();
  final _locDesc = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in [_name, _note, _locName, _locDesc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = IapDraft(await loadIapDetails(widget.client, widget.iapId));
      if (!mounted) return;
      setState(() {
        _draft = d;
        _name.text = d.name;
        _note.text = d.note;
        if (!d.locs.any((l) => l.locale == _locale)) _locale = d.locs.isEmpty ? '' : _defaultLocale(d);
        _syncLocale();
      });
      widget.onDirtyChanged?.call(false);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _defaultLocale(IapDraft d) => d.locs.any((l) => l.locale == 'en-US') ? 'en-US' : d.locs.first.locale;

  IapLocDraft? get _loc => _draft?.locs.where((l) => l.locale == _locale).firstOrNull;

  void _syncLocale() {
    _locName.text = _loc?.name ?? '';
    _locDesc.text = _loc?.description ?? '';
  }

  void _changed(VoidCallback f) {
    setState(f);
    widget.onDirtyChanged?.call(_draft?.dirty ?? false);
  }

  void _discard() {
    _changed(() {
      _draft!.discard();
      _name.text = _draft!.name;
      _note.text = _draft!.note;
      if (_loc == null) _locale = _draft!.locs.isEmpty ? '' : _defaultLocale(_draft!);
      _syncLocale();
    });
  }

  Future<void> _back() async {
    if (_draft?.dirty ?? false) {
      final ok = await _confirm(
        title: 'Discard unsaved changes?',
        body: 'You have ${_draft!.changes.length} unsaved change(s) to this in-app purchase. Nothing has been sent to Apple.',
        action: 'Discard',
        danger: true,
      );
      if (!ok) return;
    }
    widget.onDirtyChanged?.call(false);
    widget.onBack();
  }

  Future<void> _save() async {
    final d = _draft!;
    setState(() => _busy = true);
    try {
      await IapSaver(widget.client).save(d, onStep: (s) => setState(() => _step = s));
      widget.onChanged?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to App Store Connect.')));
      await _load();
    } on AscException catch (e) {
      widget.onChanged?.call();
      if (mounted) await _alert('Not everything was saved', '${e.message}\n\nChanges still marked as unsaved were not sent.');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _step = null;
        });
        widget.onDirtyChanged?.call(_draft?.dirty ?? false);
      }
    }
  }

  Future<void> _submit() async {
    final d = _draft!;
    final ok = await _confirm(
      title: 'Submit for review?',
      body:
          'This sends ${d.name} to App Review on its own. A first in-app purchase has to be submitted together with an app '
          'version instead; Apple will refuse it here if that applies.',
      action: 'Submit',
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await IapSaver(widget.client).submit(widget.iapId);
      widget.onChanged?.call();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted for review.')));
      await _load();
    } on AscException catch (e) {
      if (mounted) await _alert('Could not submit', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final d = _draft!;
    final typed = await askText(
      context,
      title: 'Delete ${d.name}?',
      label: 'Type the product ID to confirm',
      helper: 'Deleting is permanent and ${d.details.productId} can never be used again.',
    );
    if (typed == null) return;
    if (typed.trim() != d.details.productId) {
      if (mounted) await _alert('Not deleted', 'The product ID you typed does not match.');
      return;
    }
    setState(() => _busy = true);
    try {
      await IapSaver(widget.client).delete(widget.iapId);
      widget.onChanged?.call();
      widget.onDirtyChanged?.call(false);
      widget.onBack();
    } on AscException catch (e) {
      if (mounted) await _alert('Could not delete', e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLocale() async {
    final code = await askText(context, title: 'Add locale', label: 'Locale code', helper: 'For example de-DE, ja, fr-FR');
    final c = code?.trim() ?? '';
    if (c.isEmpty) return;
    if (!RegExp(r'^[a-z]{2,3}(-[A-Za-z]{2,4})?$').hasMatch(c)) {
      if (mounted) await _alert('Not a locale', '"$c" is not a locale code like de-DE or ja.');
      return;
    }
    final d = _draft!;
    if (d.locs.any((l) => l.locale == c)) {
      setState(() {
        _locale = c;
        _syncLocale();
      });
      return;
    }
    final removed = d.removedLocs.where((l) => l.locale == c).firstOrNull;
    _changed(() {
      if (removed != null) {
        d.removedLocs.remove(removed);
        d.locs.add(removed);
      } else {
        d.locs.add(IapLocDraft(locale: c, savedName: '', savedDescription: ''));
      }
      d.locs.sort((a, b) => a.locale.compareTo(b.locale));
      _locale = c;
      _syncLocale();
    });
  }

  void _removeLocale() {
    final d = _draft!;
    final l = _loc;
    if (l == null) return;
    _changed(() {
      d.locs.remove(l);
      if (!l.isNew) d.removedLocs.add(l);
      _locale = d.locs.isEmpty ? '' : _defaultLocale(d);
      _syncLocale();
    });
  }

  Future<void> _pickShot() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['png', 'jpg', 'jpeg']);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (imageSize(bytes) == null) {
      if (mounted) await _alert('Not an image', '${f.name} is not a readable PNG or JPEG.');
      return;
    }
    _changed(() => _draft!.shot = PickedShot(f.name, bytes));
  }

  Future<void> _changePrice() async {
    final d = _draft!;
    final picked = await showDialog<Resource>(
      context: context,
      builder: (_) => _PricePointDialog(client: widget.client, iapId: widget.iapId, territory: d.details.baseTerritory ?? 'USA', currency: d.details.currency),
    );
    if (picked == null) return;
    _changed(() => d.newPrice = picked.str('customerPrice') == d.savedPrice?.customerPrice ? null : picked);
  }

  Future<void> _editTerritories() async {
    final d = _draft!;
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _TerritoriesDialog(all: d.details.allTerritories, selected: d.territories ?? const {}),
    );
    if (picked != null) _changed(() => d.territories = picked);
  }

  Future<bool> _confirm({required String title, required String body, required String action, bool danger = false}) async {
    final k = Tokens.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title),
            content: SizedBox(width: 420, child: Text(body)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(
                style: danger ? FilledButton.styleFrom(backgroundColor: k.bad) : null,
                onPressed: () => Navigator.pop(c, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _alert(String title, String body) => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: SizedBox(width: 440, child: SelectableText(body)),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
    ),
  );

  Future<void> _reviewChanges() => _alert('Unsaved changes', _draft!.changes.map((c) => '•  $c').join('\n'));

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(error: _error!, onRetry: _load);
    final d = _draft;
    if (d == null) return const Center(child: CircularProgressIndicator());
    final k = Tokens.of(context);
    final editable = !d.details.locked && !_busy;
    final left = [_general(d, editable), const SizedBox(height: 20), _localizations(d, editable), const SizedBox(height: 20), _screenshot(d, editable)];
    final right = [_price(d, editable), const SizedBox(height: 20), _availability(d, editable), const SizedBox(height: 20), _readiness(d)];
    return ListView(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 40),
      children: [
        _header(d),
        if (d.details.locked) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: Icons.lock_outline,
            color: k.accentInk,
            fill: k.accentSoft,
            text: '${prettyEnum(d.details.state)}: Apple does not accept edits until review finishes.',
          ),
        ] else if (d.dirty) ...[
          const SizedBox(height: 16),
          _Banner(
            icon: Icons.warning_amber_rounded,
            color: k.warn,
            fill: k.warnSoft,
            text: '${d.changes.length} unsaved change${d.changes.length == 1 ? '' : 's'} · nothing is sent to Apple until you save',
            action: TextButton.icon(
              onPressed: _reviewChanges,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Review changes'),
              style: TextButton.styleFrom(foregroundColor: k.warn),
            ),
          ),
        ],
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 980
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: left)),
                    const SizedBox(width: 20),
                    SizedBox(width: 340, child: Column(children: right)),
                  ],
                )
              : Column(children: [...left, const SizedBox(height: 20), ...right]),
        ),
        const SizedBox(height: 24),
        Divider(color: k.line),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: k.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Deleting an in-app purchase is permanent and its product ID can never be reused.',
                style: TextStyle(color: k.muted),
              ),
            ),
            OutlinedButton(
              onPressed: _busy ? null : _delete,
              style: OutlinedButton.styleFrom(foregroundColor: k.bad, side: BorderSide(color: k.bad.withValues(alpha: 0.4))),
              child: const Text('Delete in-app purchase…'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _header(IapDraft d) {
    final k = Tokens.of(context);
    final issues = d.issueCount;
    final canSubmit = !_busy && !d.dirty && issues == 0 && d.details.state == 'READY_TO_SUBMIT';
    final submitHint = d.dirty
        ? 'Save changes first'
        : issues > 0
        ? 'Fix $issues issue${issues == 1 ? '' : 's'} first'
        : d.details.state != 'READY_TO_SUBMIT'
        ? prettyEnum(d.details.state)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: _back,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, size: 18, color: k.accent),
                    Text('In-App Purchases', style: TextStyle(color: k.accent, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            Text('  ›  ', style: TextStyle(color: k.muted)),
            Flexible(
              child: Text(
                d.savedName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: k.ink, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: k.accentSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: k.line),
              ),
              child: Icon(Icons.shopping_bag_outlined, color: k.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        d.savedName.isEmpty ? d.details.productId : d.savedName,
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: k.ink),
                      ),
                      StateChip(null, label: iapTypes[d.details.iap.str('inAppPurchaseType')] ?? prettyEnum(d.details.iap.str('inAppPurchaseType'))),
                      StatusBadge(d.details.state),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: k.inset,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: k.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline, size: 12, color: k.muted),
                            const SizedBox(width: 6),
                            SelectableText(d.details.productId, style: TextStyle(fontFamily: 'Menlo', fontSize: 11.5, color: k.body)),
                          ],
                        ),
                      ),
                      Text("Product ID and type can't change after creation", style: TextStyle(color: k.muted, fontSize: 12.5)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (submitHint != null && !d.details.locked)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: issues > 0 ? k.badSoft : k.neutralSoft,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: (issues > 0 ? k.bad : k.neutralInk).withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      submitHint,
                      style: TextStyle(color: issues > 0 ? k.bad : k.neutralInk, fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: d.dirty && !_busy ? _discard : null, child: const Text('Discard')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: d.dirty && !_busy ? _save : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_busy && _step != null) ...[
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(width: 8),
                            Text('Saving $_step…'),
                          ] else
                            const Text('Save changes'),
                          if (d.dirty && !_busy) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(10)),
                              child: Text('${d.changes.length}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: canSubmit ? _submit : null,
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: const Text('Submit for review'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _general(IapDraft d, bool editable) {
    final k = Tokens.of(context);
    return _Panel(
      icon: Icons.tune,
      title: 'General',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            label: 'Reference name',
            controller: _name,
            max: iapReferenceMax,
            helper: 'Only you see this in App Store Connect',
            enabled: editable,
            modified: d.name != d.savedName,
            onChanged: (v) => _changed(() => d.name = v),
          ),
          Divider(height: 32, color: k.line),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Family Sharing', style: TextStyle(fontWeight: FontWeight.w600, color: k.ink)),
                    const SizedBox(height: 2),
                    Text(
                      d.savedFamily
                          ? 'On. Up to five family members can use this purchase. Apple does not let it be turned off.'
                          : "Let up to five family members use this purchase. Once turned on it can't be turned off.",
                      style: TextStyle(color: k.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Switch(value: d.family, onChanged: editable && !d.savedFamily ? (v) => _changed(() => d.family = v) : null),
            ],
          ),
          Divider(height: 32, color: k.line),
          _Field(
            label: 'Review notes',
            controller: _note,
            max: iapReviewNoteMax,
            lines: 4,
            hint: 'Enter credentials or instructions for testing this in-app purchase…',
            helper: 'Anything App Review needs to test this purchase',
            enabled: editable,
            modified: d.note != d.savedNote,
            onChanged: (v) => _changed(() => d.note = v),
          ),
        ],
      ),
    );
  }

  Widget _localizations(IapDraft d, bool editable) {
    final k = Tokens.of(context);
    final loc = _loc;
    return _Panel(
      icon: Icons.language,
      title: 'Localizations',
      trailing: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: k.inset,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: k.line),
        ),
        child: Wrap(
          spacing: 2,
          children: [
            for (final l in d.locs)
              InkWell(
                onTap: () => setState(() {
                  _locale = l.locale;
                  _syncLocale();
                }),
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: l.locale == _locale ? k.surface : null,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: l.locale == _locale ? k.shadow : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (l.modified) ...[Icon(Icons.circle, size: 7, color: k.warn), const SizedBox(width: 5)],
                      Text(
                        l.locale,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: l.locale == _locale ? k.ink : k.body,
                          fontWeight: l.locale == _locale ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (editable)
              TextButton.icon(
                onPressed: _addLocale,
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: const TextStyle(fontSize: 12.5)),
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Add locale'),
              ),
          ],
        ),
      ),
      child: loc == null
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text('No localizations. Add one: Apple needs a display name to review this purchase.', style: TextStyle(color: k.muted)),
            )
          : Column(
              key: ValueKey(loc.locale),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Field(
                  label: 'Display name',
                  controller: _locName,
                  max: iapNameMax,
                  enabled: editable,
                  modified: loc.isNew || loc.name != loc.savedName,
                  onChanged: (v) => _changed(() => loc.name = v),
                ),
                const SizedBox(height: 16),
                _Field(
                  label: 'Description',
                  controller: _locDesc,
                  max: iapDescriptionMax,
                  enabled: editable,
                  modified: loc.isNew || loc.description != loc.savedDescription,
                  onChanged: (v) => _changed(() => loc.description = v),
                ),
                Divider(height: 32, color: k.line),
                Row(
                  children: [
                    if (loc.isNew) StatusBadge('PREPARE', label: 'New · not saved') else if (loc.state != null) StatusBadge(loc.state),
                    const Spacer(),
                    TextButton(
                      onPressed: editable && d.locs.length > 1 ? _removeLocale : null,
                      style: TextButton.styleFrom(foregroundColor: k.bad),
                      child: const Text('Remove locale'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _screenshot(IapDraft d, bool editable) {
    final k = Tokens.of(context);
    final existing = d.details.screenshot;
    final asset = existing?.attributes['imageAsset'] as Map?;
    final url = thumbnailUrl(asset?['templateUrl'] as String?, asset?['width'] as int?, asset?['height'] as int?, width: 240);
    final missing = existing == null && d.shot == null;
    return _Panel(
      icon: Icons.photo_camera_outlined,
      title: 'App Review screenshot',
      trailing: missing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: k.badSoft,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: k.bad.withValues(alpha: 0.3)),
              ),
              child: Text(
                'REQUIRED',
                style: TextStyle(color: k.bad, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5),
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.shot != null || existing != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 72,
                    height: 120,
                    color: k.inset,
                    child: d.shot != null
                        ? Image.memory(d.shot!.bytes, fit: BoxFit.cover)
                        : url != null
                        ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.image_outlined, color: k.muted))
                        : Icon(Icons.image_outlined, color: k.muted),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.shot?.name ?? 'Uploaded screenshot',
                        style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.shot != null
                            ? 'Uploads when you save${existing != null ? ', replacing the current one' : ''}.'
                            : '${asset?['width']}×${asset?['height']} · ${prettyEnum((existing!.attributes['assetDeliveryState'] as Map?)?['state'] as String?)}',
                        style: TextStyle(color: d.shot != null ? k.warn : k.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                if (d.shot != null) TextButton(onPressed: () => _changed(() => d.shot = null), child: const Text('Undo')),
                OutlinedButton(onPressed: editable ? _pickShot : null, child: const Text('Replace…')),
              ],
            )
          else
            InkWell(
              onTap: editable ? _pickShot : null,
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _DashedBorder(color: k.line, radius: 12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: k.accentSoft, shape: BoxShape.circle),
                        child: Icon(Icons.cloud_upload_outlined, color: k.accent, size: 20),
                      ),
                      const SizedBox(height: 12),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Add a screenshot  ', style: TextStyle(color: k.ink, fontWeight: FontWeight.w600)),
                            TextSpan(text: 'Choose file', style: TextStyle(color: k.accent, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Required before review. Shows the purchase in your app, at any iPhone or iPad size.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: k.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (missing) ...[
            const SizedBox(height: 14),
            _Banner(icon: Icons.error_outline, color: k.bad, fill: k.badSoft, text: "Missing — Apple won't review this purchase without it."),
          ],
        ],
      ),
    );
  }

  Widget _price(IapDraft d, bool editable) {
    final k = Tokens.of(context);
    final cur = d.details.currency ?? '';
    final shown = d.newPrice;
    final price = shown?.str('customerPrice') ?? d.savedPrice?.customerPrice;
    final proceeds = shown?.str('proceeds') ?? d.savedPrice?.proceeds;
    final now = DateTime.now();
    return _Panel(
      icon: Icons.payments_outlined,
      title: 'Price',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (price == null)
            Text('No price set', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: k.bad))
          else
            Text(money(cur, price), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: k.ink, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          if (d.details.baseTerritory != null)
            Text('Base territory · ${territoryName(d.details.baseTerritory!)}', style: TextStyle(color: k.muted, fontSize: 12.5)),
          if (proceeds != null) ...[
            const SizedBox(height: 4),
            Text('You receive ${money(cur, proceeds)}', style: TextStyle(color: k.good, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
          if (shown != null) ...[
            const SizedBox(height: 8),
            Text(
              'Unsaved. Was ${d.savedPrice == null ? 'not set' : money(cur, d.savedPrice!.customerPrice)}. Saving starts the new price today and '
              'replaces any scheduled change.',
              style: TextStyle(color: k.warn, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: editable ? _changePrice : null,
                  child: Text(price == null ? 'Set price…' : 'Change price…'),
                ),
              ),
              if (shown != null) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: () => _changed(() => d.newPrice = null), child: const Text('Undo')),
              ],
            ],
          ),
          if (d.details.schedule.isNotEmpty) ...[
            Divider(height: 32, color: k.line),
            Text(
              'SCHEDULE',
              style: TextStyle(color: k.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6),
            ),
            const SizedBox(height: 10),
            for (final p in d.details.schedule)
              if (p.end == null || p.end!.isAfter(now))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.startsAfter(now) ? 'From ${fmtDate(p.start)} · ${money(cur, p.customerPrice)}' : 'Now · ${money(cur, p.customerPrice)}',
                          style: TextStyle(color: k.ink, fontSize: 13),
                        ),
                      ),
                      p.startsAfter(now) ? const StateChip('PENDING', label: 'Scheduled') : const StateChip('ACTIVE', label: 'Current'),
                    ],
                  ),
                ),
          ],
          const SizedBox(height: 6),
          _Banner(
            icon: Icons.info_outline,
            color: k.accentInk,
            fill: k.accentSoft,
            text: "Other territories follow Apple's equalisation unless set manually.",
          ),
          const SizedBox(height: 12),
          Text(
            '${d.details.allTerritories.length} territories · ${d.details.manualPriceCount} manual price${d.details.manualPriceCount == 1 ? '' : 's'}',
            style: TextStyle(color: k.accent, fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _availability(IapDraft d, bool editable) {
    final k = Tokens.of(context);
    final all = d.details.allTerritories;
    final on = d.territories ?? const <String>{};
    final missing = [for (final t in all) if (!on.contains(t)) t];
    // Name whichever side is shorter: "only in India" says more than 174 places it is not sold.
    final onlyIn = on.length < missing.length;
    final ratio = all.isEmpty ? 0.0 : on.length / all.length;
    return _Panel(
      icon: Icons.public,
      title: 'Availability',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.territories == null ? 'Availability not set' : 'Available in ${on.length} of ${all.length} territories',
                  style: TextStyle(fontWeight: FontWeight.w600, color: k.ink),
                ),
              ),
              Text('${(ratio * 100).toStringAsFixed(ratio == 1 || ratio == 0 ? 0 : 1)}%', style: TextStyle(color: k.muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: ratio, minHeight: 5, backgroundColor: k.line, color: k.accent),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text('Make available in new territories', style: TextStyle(color: k.body))),
              Switch(value: d.inNew, onChanged: editable ? (v) => _changed(() => d.inNew = v) : null),
            ],
          ),
          if (d.territories != null && missing.isNotEmpty && on.isNotEmpty) ...[
            const SizedBox(height: 8),
            _territoryChips(onlyIn ? on.toList() : missing, available: onlyIn),
          ],
          const SizedBox(height: 14),
          OutlinedButton(onPressed: editable ? _editTerritories : null, child: const Text('Edit territories…')),
        ],
      ),
    );
  }

  Widget _territoryChips(List<String> codes, {required bool available}) {
    final k = Tokens.of(context);
    final names = [for (final t in codes) territoryName(t)]..sort();
    final color = available ? k.good : k.bad;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final n in names.take(4))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: available ? k.goodSoft : k.badSoft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(available ? Icons.check_circle_outline : Icons.cancel_outlined, size: 13, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${available ? 'Only in' : 'Not available'}: $n',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        if (names.length > 4) Text('+${names.length - 4} more', style: TextStyle(color: k.muted, fontSize: 12)),
      ],
    );
  }

  Widget _readiness(IapDraft d) {
    final k = Tokens.of(context);
    final checks = d.checks;
    final issues = d.issueCount;
    return _Panel(
      icon: Icons.fact_check_outlined,
      title: 'Ready for review',
      trailing: issues == 0
          ? const StateChip('READY', label: 'Ready')
          : StateChip('REJECTED', label: '$issues issue${issues == 1 ? '' : 's'}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (c.level) {
                      IapCheckLevel.ok => Icons.check_circle_outline,
                      IapCheckLevel.warn => Icons.warning_amber_rounded,
                      IapCheckLevel.bad => Icons.cancel_outlined,
                    },
                    size: 16,
                    color: switch (c.level) {
                      IapCheckLevel.ok => k.good,
                      IapCheckLevel.warn => k.warn,
                      IapCheckLevel.bad => k.bad,
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: switch (c.level) {
                          IapCheckLevel.ok => k.body,
                          IapCheckLevel.warn => k.warn,
                          IapCheckLevel.bad => k.bad,
                        },
                        fontWeight: c.level == IapCheckLevel.ok ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Divider(height: 24, color: k.line),
          Text('Submit with the next app version or on its own.', style: TextStyle(color: k.muted, fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Apple's price strings ("650.0", "9.99") as people write them: no ".0" on whole amounts, else two decimals.
String money(String? cur, String? amount) {
  final v = double.tryParse(amount ?? '');
  final n = v == null ? (amount ?? '') : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));
  return [if (cur != null && cur.isNotEmpty) cur, n].join(' ');
}

/// A titled card section, as in the design.
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.child, this.trailing});
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: k.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: k.ink),
                  ),
                ),
                ?trailing,
              ],
            ),
            Divider(height: 28, color: k.line),
            child,
          ],
        ),
      ),
    );
  }
}

/// A labelled text field with a character count, marked when it differs from what Apple has.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.max,
    required this.onChanged,
    this.helper,
    this.hint,
    this.lines = 1,
    this.enabled = true,
    this.modified = false,
  });
  final String label;
  final TextEditingController controller;
  final int max;
  final ValueChanged<String> onChanged;
  final String? helper, hint;
  final int lines;
  final bool enabled, modified;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final over = controller.text.length > max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: k.ink)),
            if (modified) ...[
              const SizedBox(width: 8),
              Text('Modified', style: TextStyle(color: k.warn, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ],
            const Spacer(),
            Text(
              '${controller.text.length} / $max',
              style: TextStyle(color: over ? k.bad : k.muted, fontSize: 11.5, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 4,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            errorText: over ? 'Over $max characters' : null,
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(helper!, style: TextStyle(color: k.muted, fontSize: 12.5)),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.fill, required this.text, this.action});
  final IconData icon;
  final Color color, fill;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Color.alphaBlend(fill, k.surface),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 13)),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 10) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Pick one of Apple's price points for the base territory.
class _PricePointDialog extends StatefulWidget {
  const _PricePointDialog({required this.client, required this.iapId, required this.territory, this.currency});
  final AscClient client;
  final String iapId, territory;
  final String? currency;

  @override
  State<_PricePointDialog> createState() => _PricePointDialogState();
}

class _PricePointDialogState extends State<_PricePointDialog> {
  late final Future<List<Resource>> _points = loadIapPricePoints(widget.client, widget.iapId, widget.territory);
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = Tokens.of(context);
    final cur = widget.currency ?? '';
    return AlertDialog(
      title: Text('Price in ${territoryName(widget.territory)}'),
      content: SizedBox(
        width: 420,
        height: 440,
        child: FutureBuilder<List<Resource>>(
          future: _points,
          builder: (context, s) {
            if (s.hasError) return ErrorView(error: s.error!);
            if (!s.hasData) return const Center(child: CircularProgressIndicator());
            final q = _search.text.trim();
            final shown = [for (final p in s.data!) if (q.isEmpty || (p.str('customerPrice') ?? '').startsWith(q)) p];
            return Column(
              children: [
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(hintText: 'Type a price, e.g. 9.99', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) => ListTile(
                      dense: true,
                      title: Text(money(cur, shown[i].str('customerPrice')), style: TextStyle(color: k.ink, fontWeight: FontWeight.w600)),
                      trailing: Text('you receive ${money(cur, shown[i].str('proceeds'))}', style: TextStyle(color: k.muted, fontSize: 12)),
                      onTap: () => Navigator.pop(context, shown[i]),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}

/// Choose the territories the purchase is sold in.
class _TerritoriesDialog extends StatefulWidget {
  const _TerritoriesDialog({required this.all, required this.selected});
  final List<String> all;
  final Set<String> selected;

  @override
  State<_TerritoriesDialog> createState() => _TerritoriesDialogState();
}

class _TerritoriesDialogState extends State<_TerritoriesDialog> {
  late final Set<String> _on = {...widget.selected};
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = [
      for (final t in widget.all)
        if (q.isEmpty || t.toLowerCase().contains(q) || territoryName(t).toLowerCase().contains(q)) t,
    ]..sort((a, b) => territoryName(a).compareTo(territoryName(b)));
    return AlertDialog(
      title: Text('Territories · ${_on.length} of ${widget.all.length}'),
      content: SizedBox(
        width: 460,
        height: 480,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Search territories', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: () => setState(() => _on.addAll(widget.all)), child: const Text('All')),
                TextButton(onPressed: () => setState(_on.clear), child: const Text('None')),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: shown.length,
                itemBuilder: (context, i) => CheckboxListTile(
                  dense: true,
                  value: _on.contains(shown[i]),
                  title: Text(territoryName(shown[i])),
                  subtitle: Text(shown[i]),
                  onChanged: (v) => setState(() => v == true ? _on.add(shown[i]) : _on.remove(shown[i])),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _on), child: const Text('Done')),
      ],
    );
  }
}
