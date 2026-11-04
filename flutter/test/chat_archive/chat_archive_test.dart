import 'package:flutter/material.dart';
import 'package:nym_bar/features/chat_archive/chat_archive_ui.dart';
import 'package:nym_bar/models/pm_conversation.dart';
import 'package:nym_bar/models/group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nym_bar/features/chat_archive/chat_archive_providers.dart';
import 'package:nym_bar/features/chat_archive/chat_archive_service.dart';
import 'package:nym_bar/features/chat_tools/chat_tools_service.dart';
import 'package:nym_bar/models/channel.dart';
import 'package:nym_bar/widgets/sidebar/sidebar_rows.dart';

void main() {
  test('local archive and hide preference survive restart and unarchive', () {
    final prefs = MemoryChatToolsPrefs();
    final archive = ChatArchiveService(prefs, 'alice');
    for (final id in ['pm-bob', '#channel', 'group-team']) {
      archive.setArchived(id, true);
    }
    archive.setHidden(true);
    final restored = ChatArchiveService(prefs, 'alice');
    expect(restored.hidden, isTrue);
    expect(restored.contains('pm-bob'), isTrue);
    expect(restored.contains('#channel'), isTrue);
    expect(restored.contains('group-team'), isTrue);
    restored.setArchived('#channel', false);
    restored.setHidden(false);
    final next = ChatArchiveService(prefs, 'alice');
    expect(next.hidden, isFalse);
    expect(next.contains('#channel'), isFalse);
    expect(next.contains('pm-bob'), isTrue);
  });

  test(
    'account changes and unauthenticated state cannot share archive state',
    () {
      final prefs = MemoryChatToolsPrefs();
      final alice = ChatArchiveService(prefs, 'alice');
      alice.setArchived('#channel', true);
      alice.setHidden(true);
      final bob = ChatArchiveService(prefs, 'bob');
      expect(bob.contains('#channel'), isFalse);
      expect(bob.hidden, isFalse);
      bob.setArchived('pm-carol', true);
      expect(ChatArchiveService(prefs, 'alice').contains('pm-carol'), isFalse);
      final writes = Map.of(prefs.values);
      final loggedOut = ChatArchiveService(prefs, '');
      loggedOut.setArchived('#channel', true);
      loggedOut.setHidden(true);
      expect(loggedOut.contains('#channel'), isFalse);
      expect(loggedOut.hidden, isFalse);
      expect(prefs.values, writes);
    },
  );

  testWidgets('hidden archive remains reachable and can be shown again', (
    tester,
  ) async {
    final archive = ChatArchiveService(MemoryChatToolsPrefs(), 'alice');
    var opened = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatArchiveProvider.overrideWithValue(archive)],
        child: MaterialApp(
          home: Scaffold(
            body: ChatArchiveHeader(
              open: false,
              count: 2,
              onToggle: () {},
              onOpen: () => opened = true,
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('archive-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide archive'));
    await tester.pumpAndSettle();
    expect(archive.hidden, isTrue);
    expect(find.byIcon(Icons.archive_outlined), findsNothing);
    await tester.tap(find.byKey(const ValueKey('archive-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open archive'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    await tester.tap(find.byKey(const ValueKey('archive-options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show archive'));
    await tester.pumpAndSettle();
    expect(archive.hidden, isFalse);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);
  });

  test(
    'PMs and groups partition into archive without losing unread metadata',
    () {
      final archive = ChatArchiveService(MemoryChatToolsPrefs(), 'alice');
      final pm = SidebarPmEntry.pm(PMConversation(pubkey: 'bob'))..unread = 5;
      final group = SidebarPmEntry.group(Group(id: 'team'))..unread = 7;
      final rows = SidebarRows<SidebarPmEntry>([
        SidebarRow(pm, ('bob', 5)),
        SidebarRow(group, ('team', 7)),
      ]);
      final container = ProviderContainer(
        overrides: [
          chatArchiveProvider.overrideWithValue(archive),
          sidebarAllPmRowsProvider.overrideWithValue(rows),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(sidebarPmRowsProvider, (_, _) {});
      addTearDown(sub.close);
      archive.setArchived('pm-bob', true);
      archive.setArchived('group-team', true);
      container.read(chatArchiveRevisionProvider.notifier).state++;
      expect(container.read(sidebarPmRowsProvider).rows, isEmpty);
      expect(rows.rows.map((r) => r.item.unread), [5, 7]);
      archive.setArchived('pm-bob', false);
      container.read(chatArchiveRevisionProvider.notifier).state++;
      expect(container.read(sidebarPmRowsProvider).rows.single.item, same(pm));
      expect(pm.unread, 5);
    },
  );

  test('damaged preference is ignored', () {
    final prefs = MemoryChatToolsPrefs();
    prefs.write('local_chat_archive_v1_alice', '{broken');
    final archive = ChatArchiveService(prefs, 'alice');
    expect(archive.contains('#channel'), isFalse);
    archive.setArchived('#channel', true);
    expect(ChatArchiveService(prefs, 'alice').contains('#channel'), isTrue);
  });

  test(
    'main rows exclude archived conversations without mutating source rows',
    () {
      final archive = ChatArchiveService(MemoryChatToolsPrefs(), 'alice');
      final general = ChannelEntry(channel: 'general');
      final archived = ChannelEntry(channel: 'archived');
      final rows = SidebarRows<ChannelEntry>([
        SidebarRow(general, ('general', 3)),
        SidebarRow(archived, ('archived', 8)),
      ], flag: true);
      final container = ProviderContainer(
        overrides: [
          chatArchiveProvider.overrideWithValue(archive),
          sidebarAllChannelRowsProvider.overrideWithValue(rows),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        sidebarChannelRowsProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      archive.setArchived('#archived', true);
      container.read(chatArchiveRevisionProvider.notifier).state++;
      expect(
        container.read(sidebarChannelRowsProvider).rows.map((r) => r.item.key),
        ['general'],
      );
      expect(rows.rows.length, 2);
      expect(rows.rows.last.sig, ('archived', 8));
      archive.setHidden(true);
      container.read(chatArchiveRevisionProvider.notifier).state++;
      expect(container.read(sidebarChannelRowsProvider).rows.length, 1);
      archive.setArchived('#archived', false);
      container.read(chatArchiveRevisionProvider.notifier).state++;
      expect(container.read(sidebarChannelRowsProvider).rows.length, 2);
      expect(
        container.read(sidebarChannelRowsProvider).rows.last,
        same(rows.rows.last),
      );
    },
  );
}
