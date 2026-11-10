import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The macOS window, which has no native title bar of its own (the app draws one). Everything here quietly does nothing
/// on the web, in tests, or anywhere the native side is missing.
class MacWindow {
  static const _channel = MethodChannel('appstore_dashboard/window');

  /// The window is drawn with its content under the title bar, so the traffic-light buttons float over the app.
  static bool get hasOverlayTrafficLights => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static Future<void> startDrag() => _call('startDrag');
  static Future<void> zoom() => _call('zoom');

  static Future<void> _call(String method) async {
    if (!hasOverlayTrafficLights) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // No native handler (tests, older build).
    } on PlatformException {
      // Not worth interrupting the person for a window gesture.
    }
  }
}
