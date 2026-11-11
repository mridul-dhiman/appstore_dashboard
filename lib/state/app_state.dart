import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:http/http.dart' as http;

import '../api/asc_client.dart';
import '../services/device_lock.dart';
import '../services/prefs.dart';
import '../services/vault.dart';

enum Phase { locked, setup, ready }

/// Holds the saved clients and the active API client. Keys only exist in memory while the app is unlocked; locking
/// drops them.
class AppState extends ChangeNotifier {
  AppState({DeviceLock? lock, Vault? vault, this.httpClient, Prefs? prefs})
      : _lock = lock ?? DeviceLock(),
        _vault = vault ?? Vault(),
        prefs = prefs ?? Prefs.memory() {
    themeMode = this.prefs.theme;
    if (kIsWeb) {
      // Nothing is stored in a browser, so there is nothing to unlock.
      phase = Phase.setup;
      _load();
    }
  }

  final DeviceLock _lock;
  final Vault _vault;

  /// Test seam: where each [AscClient] gets its HTTP client. Null = a real one.
  final http.Client Function()? httpClient;

  AscClient _newClient(Credentials c) => AscClient(c, baseUrl: baseUrl, client: httpClient?.call());

  Phase phase = Phase.locked;

  /// View choices kept between launches.
  final Prefs prefs;

  /// Follows the system until the person flips the switch in the title bar; the choice is remembered.
  ThemeMode themeMode = ThemeMode.system;

  void toggleTheme(Brightness current) {
    themeMode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    prefs.setTheme(themeMode);
    notifyListeners();
  }

  bool unlocking = false;
  String? message;

  List<Credentials> accounts = const [];
  Credentials? credentials; // the active client
  AscClient? client;

  bool get supportsDeviceLock => _lock.supported;
  bool get keysPersist => _vault.persistent;

  /// Where requests go. Desktop talks to Apple directly; the browser goes through the bundled proxy on the same origin
  /// (or the `ASC_PROXY` dart-define when developing with `flutter run -d chrome`).
  static String get baseUrl {
    if (!kIsWeb) return AscClient.appleHost;
    const override = String.fromEnvironment('ASC_PROXY');
    return override.isNotEmpty ? override : '${Uri.base.origin}/asc';
  }

  Future<void> _load() async {
    final data = await _vault.read();
    accounts = data.accounts;
    final active = data.active;
    if (active != null) {
      _activate(active);
    } else {
      if (data.unreadable) {
        message = 'Your saved clients could not be read, so you need to add a key again. The unreadable data was kept in '
            'your keychain as "${Vault.backupKey}" and is not overwritten.';
      }
      phase = Phase.setup;
      notifyListeners();
    }
  }

  /// Prompts for the system password / biometrics, then loads the saved clients.
  Future<void> unlock() async {
    if (unlocking) return;
    unlocking = true;
    message = null;
    notifyListeners();
    try {
      final result = await _lock.unlock();
      if (result != UnlockResult.unlocked) {
        message = _lock.lastMessage;
        return;
      }
      try {
        await _load();
      } catch (e) {
        // A keychain that cannot be read leaves the app locked with the reason, not stuck on a spinner.
        _drop();
        phase = Phase.locked;
        message = 'Could not read your saved keys from the keychain: $e';
      }
    } finally {
      unlocking = false;
      notifyListeners();
    }
  }

  void _activate(Credentials c) {
    client?.close();
    credentials = c;
    client = _newClient(c);
    phase = Phase.ready;
    notifyListeners();
  }

  Future<void> _persist() => _vault.write(VaultData(accounts: accounts, activeId: credentials?.id));

  /// Verifies the key against Apple, then saves it as a client and switches to it.
  /// Entering the same issuer + key again replaces the saved one.
  Future<void> connect(Credentials c) async {
    final probe = _newClient(c);
    String? firstApp;
    try {
      final page = await probe.page('/v1/apps', {'limit': '1', 'fields[apps]': 'name'});
      firstApp = page.data.isEmpty ? null : page.data.first.str('name');
    } finally {
      probe.close();
    }
    final named = c.name.isNotEmpty ? c : c.copyWith(name: firstApp ?? '');
    final next = [...accounts.where((a) => a.id != named.id), named];
    // Saved first: if the keychain refuses, the key is not shown as connected only to vanish on the next launch.
    await _vault.write(VaultData(accounts: next, activeId: named.id));
    message = null;
    accounts = next;
    _activate(named);
  }

  /// Throws if the choice could not be saved; the switch itself still happens.
  Future<void> switchTo(String id) async {
    final target = accounts.where((a) => a.id == id);
    if (target.isEmpty || credentials?.id == id) return;
    _activate(target.first);
    await _persist();
  }

  Future<void> rename(String id, String name) async {
    accounts = [for (final a in accounts) a.id == id ? a.copyWith(name: name.trim()) : a];
    if (credentials?.id == id) _activate(accounts.firstWhere((a) => a.id == id));
    await _persist();
  }

  Future<void> setVendorNumber(String vendor) async {
    final c = credentials;
    if (c == null) return;
    final updated = c.copyWith(vendorNumber: vendor.trim());
    accounts = [for (final a in accounts) a.id == c.id ? updated : a];
    _activate(updated);
    await _persist();
  }

  /// Forget one client. Falls back to another saved one, or to the setup screen if none is left.
  Future<void> remove(String id) async {
    accounts = accounts.where((a) => a.id != id).toList();
    if (credentials?.id == id) {
      client?.close();
      client = null;
      credentials = null;
      if (accounts.isEmpty) {
        phase = Phase.setup;
        notifyListeners();
      } else {
        _activate(accounts.first);
      }
    } else {
      notifyListeners();
    }
    await _persist();
  }

  /// Drop the keys from memory and ask again.
  void lock() {
    if (!supportsDeviceLock) return;
    _drop();
    phase = Phase.locked;
    message = null;
    notifyListeners();
  }

  void _drop() {
    client?.close();
    client = null;
    credentials = null;
    accounts = const [];
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }
}
