import 'dart:async';

import 'package:appstore_dashboard/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a reload keeps the old content on screen; a failed reload keeps it too, with a retry bar', (tester) async {
    final reload = ReloadController();
    var calls = 0;
    Completer<String>? pending;
    Future<String> load() {
      calls++;
      if (calls == 1) return Future.value('first');
      pending = Completer<String>();
      return pending!.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoadView<String>(controller: reload, load: load, builder: (_, v) => Text(v)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);

    reload.reload();
    await tester.pump();
    expect(find.text('first'), findsOneWidget, reason: 'not blanked by a spinner');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    pending!.completeError(Exception('offline'));
    await tester.pump();
    expect(find.text('first'), findsOneWidget);
    expect(find.textContaining('Could not refresh'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    pending!.complete('second');
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    expect(find.textContaining('Could not refresh'), findsNothing);
  });

  testWidgets('a slow older load can not overwrite a newer one', (tester) async {
    final reload = ReloadController();
    final loads = <Completer<String>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoadView<String>(
            controller: reload,
            load: () {
              loads.add(Completer<String>());
              return loads.last.future;
            },
            builder: (_, v) => Text(v),
          ),
        ),
      ),
    );
    reload.reload();
    loads[1].complete('new');
    await tester.pump();
    loads[0].complete('old');
    await tester.pump();
    expect(find.text('new'), findsOneWidget);
    expect(find.text('old'), findsNothing);
  });
}
