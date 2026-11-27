import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'theme.dart';

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
    final k = Tokens.of(context);
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final s = widget.state;
        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: k.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: k.line),
                        boxShadow: k.shadow,
                      ),
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(color: k.accentSoft, borderRadius: BorderRadius.circular(18)),
                            child: Icon(Icons.lock_outline, size: 30, color: k.accentInk),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'App Store Dashboard',
                            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: k.ink),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Unlock with Touch ID or your computer password to open your App Store Connect keys.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: k.muted, fontSize: 13),
                          ),
                          if (s.message != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              s.message!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: k.bad),
                            ),
                          ],
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 40,
                            child: FilledButton.icon(
                              onPressed: s.unlocking ? null : s.unlock,
                              icon: s.unlocking
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.fingerprint),
                              label: const Text('Unlock'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: k.muted),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Your API keys stay in your system keychain while locked',
                            style: TextStyle(color: k.muted, fontSize: 12.5),
                          ),
                        ),
                      ],
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
