import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_state.dart';
import '../../state/settings_provider.dart';
import '../chat_tools/chat_tools_providers.dart';
import 'chat_archive_service.dart';

final chatArchiveRevisionProvider = StateProvider<int>((ref) => 0);
final chatArchiveProvider = Provider<ChatArchiveService>((ref) {
  final account = ref.watch(appStateProvider.select((s) => s.selfPubkey));
  return ChatArchiveService(
    KeyValueChatToolsPrefs(ref.watch(keyValueStoreProvider)),
    account,
  );
});
