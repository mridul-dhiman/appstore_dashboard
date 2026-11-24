import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/asc_client.dart';
import '../../api/iap_creator.dart';
import '../theme.dart';

const _csvTemplate =
    'product_id,reference_name,display_name,description,price,type\n'
    'com.example.app.gold,Gold plan,Gold Plan,Unlocks all courses for life,499,non_consumable\n'
    'com.example.app.coins100,100 coins,100 Coins,A pack of 100 coins,79,consumable\n';

class _TerritoryField extends StatelessWidget {
  const _TerritoryField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textCapitalization: TextCapitalization.characters,
    decoration: const InputDecoration(labelText: 'Price territory', helperText: '3-letter code the prices are in: USA, IND, GBR…'),
  );
}

String _resultLine(IapResult r) => r.ok
    ? '✓ ${r.spec.productId}  (${r.done.join(', ')})'
    : '✗ ${r.spec.productId}  ${r.partial ? '(created but unfinished: ${r.done.join(', ')}) ' : ''}${r.error}';

/// Create one in-app purchase.
class NewIapDialog extends StatefulWidget {
  const NewIapDialog({super.key, required this.client, required this.appId, required this.appName});
  final AscClient client;
  final String appId;
  final String appName;

  @override
  State<NewIapDialog> createState() => _NewIapDialogState();
}

class _NewIapDialogState extends State<NewIapDialog> {
  final _product = TextEditingController();
  final _ref = TextEditingController();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _locale = TextEditingController(text: 'en-US');
  final _price = TextEditingController();
  final _territory = TextEditingController(text: 'USA');
  final _note = TextEditingController();
  String _type = 'NON_CONSUMABLE';
  bool _family = false;
  bool _allTerritories = true;
  bool _busy = false;
  List<String> _problems = const [];
  IapResult? _result;

  @override
  void dispose() {
    for (final c in [_product, _ref, _name, _desc, _locale, _price, _territory, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  IapSpec _spec() => IapSpec(
    productId: _product.text.trim(),
    referenceName: _ref.text.trim().isEmpty ? _name.text.trim() : _ref.text.trim(),
    type: _type,
    displayName: _name.text.trim(),
    description: _desc.text.trim().isEmpty ? _name.text.trim() : _desc.text.trim(),
    locale: _locale.text.trim().isEmpty ? 'en-US' : _locale.text.trim(),
    price: _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim()),
    reviewNote: _note.text,
    familySharable: _family,
  );

  Future<void> _create() async {
    final spec = _spec();
    final problems = spec.validate();
    if (_price.text.trim().isNotEmpty && spec.price == null) {
      problems.add('Price is not a number.');
    }
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    setState(() {
      _problems = const [];
      _busy = true;
    });
    final result = await IapCreator(
      widget.client,
      widget.appId,
      IapOptions(baseTerritory: _territory.text.trim().toUpperCase(), allTerritories: _allTerritories),
    ).create(spec);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final r = _result;
    return AlertDialog(
      title: Text('New in-app purchase · ${widget.appName}'),
      content: SizedBox(
        width: 520,
        child: r != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    r.ok ? Icons.check_circle : Icons.error_outline,
                    color: r.ok ? Tokens.of(context).good : t.colorScheme.error,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  SelectableText(_resultLine(r)),
                  if (r.ok)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('It still needs a review screenshot before it can be submitted.'),
                    ),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _product,
                      decoration: const InputDecoration(
                        labelText: 'Product ID',
                        hintText: 'com.example.app.gold',
                        helperText: 'Permanent: cannot be reused or changed later.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      items: [for (final e in iapTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setState(() => _type = v ?? _type),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      maxLength: iapNameMax,
                      decoration: const InputDecoration(labelText: 'Display name (shown to customers)'),
                    ),
                    TextField(
                      controller: _desc,
                      maxLength: iapDescriptionMax,
                      decoration: const InputDecoration(labelText: 'Description', helperText: 'Defaults to the display name.'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ref,
                      decoration: const InputDecoration(
                        labelText: 'Reference name (internal)',
                        helperText: 'Defaults to the display name.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _price,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              helperText: 'Next Apple price tier at or above this. Blank = no price.',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _TerritoryField(controller: _territory)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _locale,
                      decoration: const InputDecoration(labelText: 'Locale'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Note for App Review (optional)'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _family,
                      onChanged: (v) => setState(() => _family = v ?? false),
                      title: const Text('Family Sharing'),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _allTerritories,
                      onChanged: (v) => setState(() => _allTerritories = v ?? true),
                      title: const Text('Available in all territories'),
                    ),
                    if (_problems.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(_problems.join('\n'), style: TextStyle(color: t.colorScheme.error)),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, r?.id != null), child: Text(r == null ? 'Cancel' : 'Close')),
        if (r == null)
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create'),
          ),
      ],
    );
  }
}

/// Create many in-app purchases from CSV.
class BulkIapDialog extends StatefulWidget {
  const BulkIapDialog({super.key, required this.client, required this.appId, required this.appName});
  final AscClient client;
  final String appId;
  final String appName;

  @override
  State<BulkIapDialog> createState() => _BulkIapDialogState();
}

class _BulkIapDialogState extends State<BulkIapDialog> {
  final _csv = TextEditingController();
  final _territory = TextEditingController(text: 'USA');
  bool _allTerritories = true;
  BulkParse? _parsed;
  bool _running = false;
  int _done = 0;
  final _results = <IapResult>[];
  bool _finished = false;

  @override
  void dispose() {
    _csv.dispose();
    _territory.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['csv', 'txt']);
    if (f == null) return;
    final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    setState(() => _csv.text = text);
    _parse();
  }

  void _parse() => setState(() => _parsed = parseIapCsv(_csv.text));

  Future<void> _run() async {
    final specs = _parsed!.specs;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create ${specs.length} in-app purchase${specs.length == 1 ? '' : 's'}?'),
        content: Text(
          'This creates them in ${widget.appName} on your real App Store Connect account right now. '
          'Product IDs can never be reused, even if you delete them afterwards.'
          '${_parsed!.errors.isEmpty ? '' : '\n\n${_parsed!.errors.length} row(s) with errors will be skipped.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _running = true;
      _done = 0;
      _results.clear();
    });
    final creator = IapCreator(
      widget.client,
      widget.appId,
      IapOptions(baseTerritory: _territory.text.trim().toUpperCase(), allTerritories: _allTerritories),
    );
    // One at a time: Apple rate-limits writes, and a failure should not race the next item.
    for (final s in specs) {
      final r = await creator.create(s);
      if (!mounted) return;
      setState(() {
        _results.add(r);
        _done++;
      });
    }
    if (mounted) {
      setState(() {
        _running = false;
        _finished = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final p = _parsed;
    final okCount = _results.where((r) => r.ok).length;
    return AlertDialog(
      title: Text('Bulk create in-app purchases · ${widget.appName}'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: (_running || _finished)
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_running) LinearProgressIndicator(value: _done / p!.specs.length),
                  const SizedBox(height: 8),
                  Text(
                    _finished
                        ? '$okCount of ${_results.length} created${okCount == _results.length ? '' : ' · ${_results.length - okCount} need attention'}'
                        : 'Creating $_done / ${p!.specs.length}…',
                    style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final r in _results)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: SelectableText(_resultLine(r), style: TextStyle(color: r.ok ? null : t.colorScheme.error, fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_file), label: const Text('Choose CSV')),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _csv.text = _csvTemplate;
                          _parse();
                        }),
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Insert example'),
                      ),
                      TextButton.icon(
                        onPressed: () => Clipboard.setData(const ClipboardData(text: _csvTemplate)),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy template'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Columns: product_id, display_name (required) · reference_name, description, price, type, locale, review_note, family_sharable.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _csv,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 12),
                      decoration: const InputDecoration(hintText: 'Paste CSV here, header row first', alignLabelWithHint: true),
                      onChanged: (_) => _parse(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(width: 140, child: _TerritoryField(controller: _territory)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _allTerritories,
                          onChanged: (v) => setState(() => _allTerritories = v ?? true),
                          title: const Text('Available in all territories'),
                        ),
                      ),
                    ],
                  ),
                  if (p != null) ...[
                    Text(
                      '${p.specs.length} ready${p.errors.isEmpty ? '' : ' · ${p.errors.length} with errors'}',
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (p.errors.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 90),
                        child: SingleChildScrollView(
                          child: Text(p.errors.join('\n'), style: TextStyle(color: t.colorScheme.error, fontSize: 12)),
                        ),
                      ),
                  ],
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.pop(context, _results.any((r) => r.id != null)),
          child: Text(_finished ? 'Close' : 'Cancel'),
        ),
        if (!_running && !_finished)
          FilledButton(
            onPressed: (p == null || p.specs.isEmpty) ? null : _run,
            child: Text('Create${p == null || p.specs.isEmpty ? '' : ' ${p.specs.length}'}'),
          ),
      ],
    );
  }
}
