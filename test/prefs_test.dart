import 'package:appstore_dashboard/services/prefs.dart';
import 'package:appstore_dashboard/ui/shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_asc.dart';
import 'support/fake_state.dart';

void main() {
  test('theme, grid and the last app survive a reload of the store', () async {
    SharedPreferences.setMockInitialValues({});
    final a = await Prefs.load();
    await a.setTheme(ThemeMode.dark);
    await a.setAppsGrid(false);
    await a.setLastApp('client1', 'A1', 2);
    final b = await Prefs.load();
    expect(b.theme, ThemeMode.dark);
    expect(b.appsGrid, isFalse);
    expect(b.lastApp('client1'), (appId: 'A1', tab: 2));
    expect(b.lastApp('client2'), isNull);
    await b.setLastApp('client1', null);
    expect((await Prefs.load()).lastApp('client1'), isNull);
  });

  testWidgets('the shell reopens the app and tab that were open last time', (tester) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = StateHarness((r) {
      if (r.method != 'GET') return null;
      if (r.path.startsWith('/v1/apps?')) {
        return json({
          'data': [
            {
              'type': 'apps',
              'id': 'A1',
              'attributes': {'name': 'Vidyagram', 'bundleId': 'com.example.vidya', 'sku': 'VG1'},
            },
          ],
        });
      }
      return json({'data': []});
    });
    await h.state.unlock();
    await h.state.prefs.setLastApp(h.state.credentials!.id, 'A1', 3);
    await tester.pumpWidget(MaterialApp(home: Shell(state: h.state)));
    await tester.pumpAndSettle();
    expect(find.text('Applications'), findsOneWidget, reason: 'the back button of the app page');
    expect(find.text('No builds uploaded.'), findsOneWidget, reason: 'tab 3 is Builds');
  });
}
