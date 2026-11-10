import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/lock_screen.dart';
import 'ui/setup_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() => runApp(const DashboardApp());

class DashboardApp extends StatefulWidget {
  const DashboardApp({super.key});

  @override
  State<DashboardApp> createState() => _DashboardAppState();
}

class _DashboardAppState extends State<DashboardApp> {
  final _state = AppState();

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) => MaterialApp(
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
