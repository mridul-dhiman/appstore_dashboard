import 'dart:convert';
import 'dart:io';

import '../api/models.dart';

/// Decodes the base64 profile content and writes it to the Provisioning Profiles
/// directory so Xcode picks it up without a manual download.
Future<bool> installProfile(Resource profile) async {
  final content = profile.str('profileContent');
  final uuid = profile.str('uuid');
  if (content == null || uuid == null) return false;

  final home = realHome();
  if (home == null) return false;

  final dir = Directory('$home/Library/MobileDevice/Provisioning Profiles');
  if (!dir.existsSync()) await dir.create(recursive: true);

  final file = File('${dir.path}/$uuid.mobileprovision');
  await file.writeAsBytes(base64Decode(content));
  return true;
}

/// In the App Sandbox HOME is the app's container; Xcode reads the user's real home.
String? realHome() {
  final home = Platform.environment['HOME'];
  if (home == null) return null;
  final i = home.indexOf('/Library/Containers/');
  return i < 0 ? home : home.substring(0, i);
}
