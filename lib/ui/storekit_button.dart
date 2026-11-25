import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api/asc_client.dart';
import '../api/export.dart';
import '../api/storekit.dart';
import '../api/territories.dart';

/// Saves the app's in-app purchases and subscriptions as an Xcode StoreKit Configuration File (.storekit), priced in
/// the products' base storefront, for testing purchases locally in Xcode.
class StoreKitButton extends StatefulWidget {
  const StoreKitButton({super.key, required this.client, required this.appId, required this.appName});
  final AscClient client;
  final String appId;
  final String appName;

  @override
  State<StoreKitButton> createState() => _StoreKitButtonState();
}

class _StoreKitButtonState extends State<StoreKitButton> {
  bool _busy = false;

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final x = await loadStoreKitExport(widget.client, widget.appId);
      if (x.count == 0) {
        messenger.showSnackBar(const SnackBar(content: Text('No in-app purchases or subscriptions to export.')));
        return;
      }
      final text = storeKitJson(storeKitConfig(appId: widget.appId, storefront: x.storefront, products: x.products, groups: x.groups));
      final name = exportFileName(widget.appName, 'storekit').replaceFirst(RegExp(r'_\d{4}-\d{2}-\d{2}\.storekit$'), '.storekit');
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save StoreKit configuration',
        fileName: name,
        bytes: Uint8List.fromList(utf8.encode(text)),
        mimeType: 'application/json',
      );
      if (saved == null) return;
      final missing = x.unpriced == 0 ? '' : ' ${x.unpriced} have no price there and are set to 0.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${x.count} products, priced for ${territoryName(x.storefront)}.$missing '
            'In Xcode: add the file to the project, then Edit Scheme › Run › Options › StoreKit Configuration.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } on AscException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save the file ($e).')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: _busy ? null : _export,
    icon: _busy
        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.integration_instructions_outlined, size: 17),
    label: const Text('Export .storekit'),
  );
}
