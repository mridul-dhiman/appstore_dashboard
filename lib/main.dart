import 'package:flutter/material.dart';

import 'services/prefs.dart';
import 'state/app_state.dart';
import 'ui/lock_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await Prefs.load();
  runApp(DashboardApp(state: AppState(prefs: prefs)));
}

class DashboardApp extends StatefulWidget {
  const DashboardApp({super.key, this.state});

  /// Made in [main] with the saved preferences; tests pass their own. The app owns it and disposes it.
  final AppState? state;

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  late final _state = widget.state ?? AppState();
  final _navigator = GlobalKey<NavigatorState>();
  Phase? _lastPhase;

  @override
  void initState() {
    super.initState();
    _lastPhase = _state.phase;
    _state.addListener(_onState);
  }

  /// Locking swaps the home screen, but dialogs, drawers and pushed screens sit above it and would stay visible over
  /// the lock screen. Close them all when the app locks.
  void _onState() {
    final phase = _state.phase;
    if (phase == Phase.locked && _lastPhase != Phase.locked) {
      _navigator.currentState?.popUntil((r) => r.isFirst);
    }
    _lastPhase = phase;
  }

  @override
  void dispose() {
    _state.removeListener(_onState);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        title: 'App Store Dashboard',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: _state.themeMode,
        home: switch (_state.phase) {
          Phase.locked => LockScreen(state: _state),
          Phase.setup => SetupScreen(state: _state),
          Phase.ready => Shell(state: _state),
        },
      ),
    );
  }
}
