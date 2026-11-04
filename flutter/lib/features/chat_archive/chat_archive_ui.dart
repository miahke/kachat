import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/sidebar/pm_context_menu.dart';
import '../i18n/i18n.dart';
import 'chat_archive_providers.dart';

const archiveSvg =
    '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="2" width="12" height="3" rx="1"/><path d="M3 5v9h10V5M6 8h4"/></svg>';

List<SidebarQuickMenuItem> chatArchiveSidebarItems(WidgetRef ref, String key) {
  final archive = ref.read(chatArchiveProvider);
  final archived = archive.contains(key);
  return [
    SidebarQuickMenuItem(
      label: archived ? tr('Unarchive chat') : tr('Archive chat'),
      svg: archiveSvg,
      onSelected: () {
        if (!identical(ref.read(chatArchiveProvider), archive)) return;
        archive.setArchived(key, !archived);
        ref.read(chatArchiveRevisionProvider.notifier).state++;
      },
    ),
  ];
}

class ChatArchiveHeader extends ConsumerWidget {
  const ChatArchiveHeader({
    super.key,
    required this.open,
    required this.count,
    required this.onToggle,
    required this.onOpen,
  });

  final bool open;
  final int count;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatArchiveRevisionProvider);
    final archive = ref.watch(chatArchiveProvider);
    final visible = !archive.hidden || open;
    return ListTile(
      dense: true,
      leading: visible
          ? Icon(open ? Icons.arrow_back : Icons.archive_outlined)
          : null,
      title: Text(
        visible ? '${tr('Archived chats')} ($count)' : tr('Chat list'),
      ),
      onTap: visible ? onToggle : null,
      trailing: PopupMenuButton<String>(
        key: const ValueKey('archive-options'),
        tooltip: tr('Archive options'),
        onSelected: (action) {
          if (action == 'open') {
            onOpen();
          } else {
            archive.setHidden(!archive.hidden);
            ref.read(chatArchiveRevisionProvider.notifier).state++;
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'open', child: Text(tr('Open archive'))),
          PopupMenuItem(
            value: 'hide',
            child: Text(
              archive.hidden ? tr('Show archive') : tr('Hide archive'),
            ),
          ),
        ],
      ),
    );
  }
}
