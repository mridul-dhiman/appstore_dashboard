import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../api/asc_client.dart';
import '../services/device_lock.dart';
import '../services/vault.dart';

enum Phase { locked, setup, ready }

/// Holds the saved clients and the active API client. Keys only exist in memory while the app is unlocked; locking
/// drops them.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({DeviceLock? lock, Vault? vault})
      : _lock = lock ?? DeviceLock(),
        _vault = vault ?? Vault() {
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      // Nothing is stored in a browser, so there is nothing to unlock.
      phase = Phase.setup;
      _load();
    }
  }

  /// How long the app may sit in the background before it asks for the password / Touch ID again.
  static const relockAfter = Duration(minutes: 1);

  final DeviceLock _lock;
  final Vault _vault;

  Phase phase = Phase.locked;
  bool unlocking = false;
  String? message;

  List<Credentials> accounts = const [];
  Credentials? credentials; // the active client
  AscClient? client;
  DateTime? _leftAt;

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
      await _load();
    } finally {
      unlocking = false;
      notifyListeners();
    }
  }

  void _activate(Credentials c) {
    client?.close();
    credentials = c;
    client = AscClient(c, baseUrl: baseUrl);
    phase = Phase.ready;
    notifyListeners();
  }

  Future<void> _persist() => _vault.write(VaultData(accounts: accounts, activeId: credentials?.id));

  /// Verifies the key against Apple, then saves it as a client and switches to it.
  /// Entering the same issuer + key again replaces the saved one.
  Future<void> connect(Credentials c) async {
    final probe = AscClient(c, baseUrl: baseUrl);
    String? firstApp;
    try {
      final page = await probe.page('/v1/apps', {'limit': '1', 'fields[apps]': 'name'});
      firstApp = page.data.isEmpty ? null : page.data.first.str('name');
    } finally {
      probe.close();
    }
    final named = c.name.isNotEmpty ? c : c.copyWith(name: firstApp ?? '');
    accounts = [...accounts.where((a) => a.id != named.id), named];
    _activate(named);
    await _persist();
  }

  void switchTo(String id) {
    final target = accounts.where((a) => a.id == id);
    if (target.isEmpty || credentials?.id == id) return;
    _activate(target.first);
    _persist();
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!supportsDeviceLock) return;
    if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && phase != Phase.locked && DateTime.now().difference(left) >= relockAfter) lock();
    } else {
      _leftAt ??= DateTime.now();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _drop();
    super.dispose();
  }
}
