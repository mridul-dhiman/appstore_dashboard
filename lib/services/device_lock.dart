import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

enum UnlockResult { unlocked, cancelled, unavailable }

/// Asks the operating system to prove the person at the keyboard is the owner: Touch ID or the Mac login password,
/// falling back to the account password (`biometricOnly: false`).
class DeviceLock {
  final _auth = LocalAuthentication();

  /// Browsers cannot reach the OS lock through `local_auth`; the web build does not use it.
  bool get supported => !kIsWeb;

  String? lastMessage;

  Future<UnlockResult> unlock({String reason = 'Unlock your App Store Connect keys'}) async {
    lastMessage = null;
    if (!supported) return UnlockResult.unavailable;
    try {
      if (!await _auth.isDeviceSupported()) {
        lastMessage =
            'This device has no login password or Touch ID set up, so the keys cannot be protected. '
            'Set a login password in system settings and try again.';
        return UnlockResult.unavailable;
      }
      final ok = await _auth.authenticate(localizedReason: reason, biometricOnly: false);
      return ok ? UnlockResult.unlocked : UnlockResult.cancelled;
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.userCanceled:
        case LocalAuthExceptionCode.systemCanceled:
        case LocalAuthExceptionCode.timeout:
        case LocalAuthExceptionCode.authInProgress:
          return UnlockResult.cancelled;
        default:
          lastMessage = e.description ?? 'Authentication failed (${e.code.name}).';
          return UnlockResult.unavailable;
      }
    } catch (e) {
      lastMessage = 'Authentication failed: $e';
      return UnlockResult.unavailable;
    }
  }
}
