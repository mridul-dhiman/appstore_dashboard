import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/asc_client.dart';
import '../api/export.dart';

/// A menu button that builds a table and saves it as CSV or JSON through the system save dialog.
class ExportButton extends StatelessWidget {
  const ExportButton({super.key, required this.items, this.label = 'Export'});

  /// Menu entries: a title and a way to produce its table (may load data first).
  final Map<String, Future<ExportTable> Function()> items;
  final String label;

  Future<void> _save(BuildContext context, Future<ExportTable> Function() build, String format) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final t = await build();
      if (t.rows.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('Nothing to export yet.')));
        return;
      }
      final isCsv = format == 'csv';
      final bytes = Uint8List.fromList(utf8.encode(isCsv ? toCsv(t) : toJsonText(t)));
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save ${t.name}',
        fileName: exportFileName(t.name, format),
        bytes: bytes,
        mimeType: isCsv ? 'text/csv' : 'application/json',
      );
      if (saved != null) messenger.showSnackBar(SnackBar(content: Text('Saved ${t.rows.length} rows.')));
    } on AscException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the file ($e).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final e in items.entries) ...[
          MenuItemButton(onPressed: () => _save(context, e.value, 'csv'), child: Text('${e.key} as CSV')),
          MenuItemButton(onPressed: () => _save(context, e.value, 'json'), child: Text('${e.key} as JSON')),
        ],
      ],
      builder: (context, c, _) => OutlinedButton.icon(
        onPressed: () => c.isOpen ? c.close() : c.open(),
        icon: const Icon(Icons.file_download_outlined, size: 17),
        label: Text(label),
      ),
    );
  }
}
