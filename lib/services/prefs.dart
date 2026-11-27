import 'dart:convert';

import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Small view choices kept between launches: theme, grid or list, and the app and tab that were open. No keys or
/// account data live here (those are in the keychain).
class Prefs {
  Prefs._(this._p);

  /// Not saved anywhere: for tests, and the fallback if the platform store is unavailable.
  Prefs.memory() : _p = null;

  static Future<Prefs> load() async {
    try {
      return Prefs._(await SharedPreferences.getInstance());
    } catch (_) {
      return Prefs.memory();
    }
  }

  final SharedPreferences? _p;
  final _mem = <String, Object>{};

  String? _str(String k) => _p?.getString(k) ?? _mem[k] as String?;
  bool? _bool(String k) => _p?.getBool(k) ?? _mem[k] as bool?;

  Future<void> _set(String k, Object? v) async {
    if (v == null) {
      _mem.remove(k);
      await _p?.remove(k);
      return;
    }
    _mem[k] = v;
    if (v is String) await _p?.setString(k, v);
    if (v is bool) await _p?.setBool(k, v);
  }

  ThemeMode get theme => switch (_str('theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  Future<void> setTheme(ThemeMode m) => _set('theme', m.name);

  bool get appsGrid => _bool('apps.grid') ?? true;
  Future<void> setAppsGrid(bool grid) => _set('apps.grid', grid);

  /// The app and tab last open for a client, or null.
  ({String appId, int tab})? lastApp(String clientId) {
    final v = _str('last.$clientId');
    final parts = v?.split('|');
    if (parts == null || parts.length != 2) return null;
    return (appId: parts[0], tab: int.tryParse(parts[1]) ?? 0);
  }

  /// A client's own reply templates (name → text), or null if it has none saved yet.
  Map<String, String>? replyTemplates(String clientId) {
    final raw = _str('templates.$clientId');
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return null;
    }
  }

  Future<void> setReplyTemplates(String clientId, Map<String, String> t) => _set('templates.$clientId', jsonEncode(t));

  Future<void> setLastApp(String clientId, String? appId, [int tab = 0]) => _set('last.$clientId', appId == null ? null : '$appId|$tab');
}
