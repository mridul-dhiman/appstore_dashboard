// Runs the app with Flutter Driver enabled, so a tool can tap and read the UI by text instead of moving the real mouse:
//   flutter run -d macos -t test_driver/main.dart
import 'package:appstore_dashboard/main.dart' as app;
import 'package:flutter_driver/driver_extension.dart';

Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main();
}
