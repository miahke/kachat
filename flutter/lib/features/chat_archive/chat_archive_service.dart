import 'dart:convert';

import '../chat_tools/chat_tools_service.dart';

/// Local organization only. Never deletes messages or leaves conversations.
class ChatArchiveService {
  ChatArchiveService(this._prefs, this.account) {
    if (account.isEmpty) return;
    try {
      final data = jsonDecode(_prefs.read(_storageKey) ?? '{}');
      if (data is! Map) return;
      final ids = data['ids'];
      if (ids is List) _ids.addAll(ids.whereType<String>().where(_valid));
      _hidden = data['hidden'] == true;
    } catch (_) {
      // Damaged preferences must not prevent opening the list.
    }
  }

  final ChatToolsPrefs _prefs;
  final String account;
  final Set<String> _ids = {};
  bool _hidden = false;
  String get _storageKey => 'local_chat_archive_v1_$account';
  bool get hidden => _hidden;
  bool contains(String key) => _ids.contains(key);
  static bool _valid(String key) =>
      (key.startsWith('#') && key.length > 1) ||
      (key.startsWith('pm-') && key.length > 3) ||
      (key.startsWith('group-') && key.length > 6);

  void setArchived(String key, bool archived) {
    if (account.isEmpty || !_valid(key)) return;
    archived ? _ids.add(key) : _ids.remove(key);
    _save();
  }

  void setHidden(bool hidden) {
    if (account.isEmpty) return;
    _hidden = hidden;
    _save();
  }

  void _save() => _prefs.write(
    _storageKey,
    jsonEncode({'ids': _ids.toList()..sort(), 'hidden': _hidden}),
  );
}
