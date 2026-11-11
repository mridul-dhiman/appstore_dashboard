import 'package:flutter/material.dart';

import '../state/app_state.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.state});
  final AppState state;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  @override
  void initState() {
    super.initState();
    // Prompt straight away; the button is there if the person cancels.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.state.unlock());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        return Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: t.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(20)),
                      child: Icon(Icons.lock_outline, size: 34, color: t.colorScheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 20),
                    Text('App Store Dashboard', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(
                      'Unlock with Touch ID or your computer password to open your App Store Connect keys.',
                      textAlign: TextAlign.center,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                    if (s.message != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        s.message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: t.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: s.unlocking ? null : s.unlock,
                      icon: s.unlocking
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.fingerprint),
                      label: const Text('Unlock'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
