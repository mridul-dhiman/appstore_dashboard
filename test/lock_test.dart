import 'dart:async';

import 'package:appstore_dashboard/main.dart';
import 'package:appstore_dashboard/services/device_lock.dart';
import 'package:appstore_dashboard/state/app_state.dart';
import 'package:appstore_dashboard/ui/lock_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_asc.dart';
import 'support/fake_state.dart';

void main() {
  testWidgets('locking closes open dialogs and screens, so nothing sits over the lock screen', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = StateHarness((r) => r.method == 'GET' ? json({'data': []}) : null);
    await h.state.unlock();
    await tester.pumpWidget(DashboardApp(state: h.state));
    await tester.pumpAndSettle();
    expect(h.state.phase, Phase.ready);

    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Pushed screen'))));
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: nav.context,
        builder: (_) => const AlertDialog(content: Text('A dialog')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A dialog'), findsOneWidget);

    h.lock.result = UnlockResult.cancelled; // the lock screen asks again at once; this time the person cancels
    h.state.lock();
    await tester.pumpAndSettle();
    expect(find.text('A dialog'), findsNothing);
    expect(find.text('Pushed screen'), findsNothing);
    expect(find.byType(LockScreen), findsOneWidget);
  });
}
