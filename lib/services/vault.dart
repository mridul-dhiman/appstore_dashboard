import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/asc_client.dart';

/// Everything saved: the clients and which one is open.
class VaultData {
  const VaultData({this.accounts = const [], this.activeId, this.unreadable = false});
  final List<Credentials> accounts;
  final String? activeId;

  /// Something was saved but could not be read. The raw text was copied to [Vault.backupKey] before anything else
  /// can overwrite it.
  final bool unreadable;

  Credentials? get active {
    if (accounts.isEmpty) return null;
    return accounts.firstWhere((a) => a.id == activeId, orElse: () => accounts.first);
  }
}

/// Where the API keys live between launches.
///
/// Desktop: the OS keychain (the app only reads it after [DeviceLock] succeeds).
/// Web: nowhere. A browser has no keychain we can protect with the device password, so keys are held in memory for the
/// tab's lifetime only and the person re-adds them next visit.
class Vault {
  static const _storage = FlutterSecureStorage(
    // The file-based login keychain: works for ad-hoc signed builds with no keychain-sharing entitlement.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'asc_clients_v1';

  /// Where an unreadable save is copied, so adding a key again cannot destroy it.
  static const backupKey = 'asc_clients_v1_unreadable_backup';

  static VaultData _memory = const VaultData();

  bool get persistent => !kIsWeb;

  Future<VaultData> read() async {
    if (kIsWeb) return _memory;
    final raw = await _storage.read(key: _key);
    if (raw == null) return const VaultData();
    final parsed = parseVault(raw);
    if (parsed.unreadable) {
      // Keep the first copy: a second bad read must not replace an older, maybe more useful, backup.
      if (await _storage.read(key: backupKey) == null) await _storage.write(key: backupKey, value: raw);
    }
    return parsed;
  }

  Future<void> write(VaultData d) async {
    if (kIsWeb) {
      _memory = d;
      return;
    }
    if (d.accounts.isEmpty) {
      await _storage.delete(key: _key);
      return;
    }
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'accounts': [for (final a in d.accounts) a.toJson()],
        'activeId': d.activeId,
      }),
    );
  }
}

/// The saved JSON, or [VaultData.unreadable] when it is not what this app wrote.
VaultData parseVault(String raw) {
  try {
    final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
    return VaultData(
      accounts: [for (final a in (j['accounts'] as List)) Credentials.fromJson((a as Map).cast<String, dynamic>())],
      activeId: j['activeId'] as String?,
    );
  } catch (_) {
    return const VaultData(unreadable: true);
  }
}
