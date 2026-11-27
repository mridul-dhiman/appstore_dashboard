import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../api/asc_client.dart';
import '../state/app_state.dart';

/// First-run screen: the whole "login" is the three parts of an App Store Connect API key.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state, this.embedded = false});
  final AppState state;

  /// True when opened from the switcher to add another client (shows Cancel and closes itself on success).
  final bool embedded;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _keyId = TextEditingController();
  final _issuer = TextEditingController();
  final _pem = TextEditingController();
  final _vendor = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _fileName;

  @override
  void dispose() {
    _keyId.dispose();
    _issuer.dispose();
    _pem.dispose();
    _vendor.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return;
    final text = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    setState(() {
      _pem.text = text.trim();
      _fileName = f.name;
      // Apple names the file AuthKey_<KEYID>.p8 (ours may carry a prefix such as Admin_).
      final m = RegExp(r'AuthKey_([A-Z0-9]{10})').firstMatch(f.name);
      if (m != null && _keyId.text.trim().isEmpty) _keyId.text = m.group(1)!;
    });
  }

  Future<void> _connect() async {
    final keyId = _keyId.text.trim();
    final issuer = _issuer.text.trim();
    final pem = normalizePem(_pem.text);
    if (keyId.isEmpty || issuer.isEmpty || pem.isEmpty) {
      setState(() => _error = 'Fill in the Key ID, Issuer ID and the private key.');
      return;
    }
    if (!pem.contains('BEGIN PRIVATE KEY')) {
      setState(() => _error = 'That does not look like a .p8 file. It should start with -----BEGIN PRIVATE KEY-----.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.state.connect(
        Credentials(keyId: keyId, issuerId: issuer, privateKeyPem: pem, name: _name.text.trim(), vendorNumber: _vendor.text.trim()),
      );
      if (mounted && widget.embedded) Navigator.of(context).pop();
    } on AscException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final s = widget.state;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.embedded ? 'Add another client' : 'Connect your App Store Connect key',
                      style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'App Store Connect → Users and Access → Integrations → App Store Connect API. '
                      'No Apple ID sign-in is needed, only the key.',
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                    if (s.message != null && !widget.embedded) ...[
                      const SizedBox(height: 14),
                      Text(s.message!, style: TextStyle(color: t.colorScheme.error)),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _issuer,
                      decoration: const InputDecoration(labelText: 'Issuer ID', hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _keyId,
                      decoration: const InputDecoration(labelText: 'Key ID', hintText: '10 characters, e.g. TX5ZF2BVG6'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Name (optional)',
                        helperText: 'Shown in the client switcher. Defaults to your first app.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(onPressed: _pick, icon: const Icon(Icons.upload_file), label: const Text('Choose .p8 file')),
                        const SizedBox(width: 12),
                        if (_fileName != null) Flexible(child: Text(_fileName!, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pem,
                      // A private key should never sit on screen. Pasted newlines are stripped by the single-line field;
                      // normalizePem() puts the PEM back together.
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: _fileName != null ? 'Private key loaded from $_fileName' : 'or paste the private key',
                        helperText: 'Hidden. Paste the whole .p8 contents, including the BEGIN/END lines.',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _vendor,
                      decoration: const InputDecoration(
                        labelText: 'Vendor number (optional)',
                        helperText: 'Only for Sales & Trends. Payments and Financial Reports → top left.',
                      ),
                    ),
                    if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: TextStyle(color: t.colorScheme.error))],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.keysPersist
                                ? 'Stored in your system keychain. Opening the app asks for your password or Touch ID.'
                                : 'Kept in this tab only. Close or reload it and you will add the key again.',
                            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (widget.embedded) ...[
                          TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
                          const SizedBox(width: 8),
                        ],
                        FilledButton(
                          onPressed: _busy ? null : _connect,
                          child: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Connect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
