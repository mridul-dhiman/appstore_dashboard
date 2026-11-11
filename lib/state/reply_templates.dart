import 'package:flutter/foundation.dart';

import '../api/reviews.dart';
import '../services/prefs.dart';

/// The reply templates of one client, editable and remembered on this Mac.
class ReplyTemplates extends ChangeNotifier {
  ReplyTemplates({Prefs? prefs, String? clientId})
    : _prefs = prefs,
      _clientId = clientId,
      _items = (clientId == null ? null : prefs?.replyTemplates(clientId)) ?? Map.of(defaultReplyTemplates);

  final Prefs? _prefs;
  final String? _clientId;
  Map<String, String> _items;

  Map<String, String> get items => Map.unmodifiable(_items);

  /// Replaces them all. Blank names or texts are dropped.
  Future<void> save(Map<String, String> next) async {
    _items = {
      for (final e in next.entries)
        if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty) e.key.trim(): e.value.trim(),
    };
    notifyListeners();
    if (_clientId != null) await _prefs?.setReplyTemplates(_clientId, _items);
  }
}
