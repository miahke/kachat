import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/groups/group_manager.dart';
import 'package:nym_bar/models/group.dart';
import 'package:nym_bar/services/nostr/identity_service.dart';
import 'package:nym_bar/services/nostr/nostr_service.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/state/app_state.dart';
import 'package:nym_bar/state/nostr_controller.dart';
import 'package:nym_bar/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DelayedService extends NostrService {
  DelayedService(Identity identity)
    : super(identity: identity, useProxy: false, relays: []);
  final stopping = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> stop() async {
    stopping.complete();
    await release.future;
  }
}

class DelayedGroups extends GroupManager {
  DelayedGroups(super.service);
  final result = Completer<Group?>();
  int calls = 0;
  @override
  Future<Group?> createGroup({
    required String selfPubkey,
    required String name,
    required List<String> memberPubkeys,
    String? avatar,
    String? banner,
    String? description,
    bool allowMemberInvites = true,
    MessagingSettings settings = const MessagingSettings(),
    bool Function()? sessionIsCurrent,
  }) {
    calls++;
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed creation and teardown do not register or send a group',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await KeyValueStore.open();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final identity = Identity(pubkey: 'a' * 64, privkey: null, nym: 'a');
      final service = DelayedService(identity);
      final groups = DelayedGroups(service);
      final controller = container.read(nostrControllerProvider);
      controller.debugSetGroupSession(identity, service, groups);
      var sends = 0;
      controller.debugSendInitialGroupMessage = (_, _) async {
        sends++;
      };
      final original = container.read(appStateProvider).view;
      final create = controller.createGroup('test', [
        'b' * 64,
      ], initialMessage: 'hello');
      groups.result.complete(null);
      expect(await create, isNull);
      expect(container.read(appStateProvider).view, original);
      expect(sends, 0);
      final teardown = controller.debugTeardownGroupSession();
      await service.stopping.future;
      expect(
        await controller.createGroup('late', [
          'b' * 64,
        ], initialMessage: 'hello'),
        isNull,
      );
      expect(groups.calls, 1);
      service.release.complete();
      await teardown;
      expect(sends, 0);
    },
  );
  test(
    'initial message keeps its group target after navigation changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await KeyValueStore.open();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final identity = Identity(pubkey: 'a' * 64, privkey: null, nym: 'a');
      final service = DelayedService(identity);
      final groups = DelayedGroups(service);
      final controller = container.read(nostrControllerProvider);
      controller.debugSetGroupSession(identity, service, groups);
      ChatView? target;
      controller.debugSendInitialGroupMessage = (_, view) async {
        target = view;
      };
      final create = controller.createGroup('test', [
        'b' * 64,
      ], initialMessage: 'hello');
      final subscription = container.listen(appStateProvider, (previous, next) {
        if (next.view == ChatView.group('new-group')) {
          container
              .read(appStateProvider.notifier)
              .switchView(const ChatView.channel('other'));
        }
      });
      addTearDown(subscription.close);
      groups.result.complete(Group(id: 'new-group'));
      expect(await create, isNotNull);
      expect(
        container.read(appStateProvider).view,
        const ChatView.channel('other'),
      );
      expect(target, ChatView.group('new-group'));
    },
  );

  test('teardown invalidates a group creation already in flight', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await KeyValueStore.open();
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    final identity = Identity(pubkey: 'a' * 64, privkey: null, nym: 'a');
    final service = DelayedService(identity);
    final groups = DelayedGroups(service);
    final controller = container.read(nostrControllerProvider);
    controller.debugSetGroupSession(identity, service, groups);
    var sends = 0;
    controller.debugSendInitialGroupMessage = (_, _) async {
      sends++;
    };
    final original = container.read(appStateProvider).view;
    final create = controller.createGroup('test', [
      'b' * 64,
    ], initialMessage: 'hello');
    final teardown = controller.debugTeardownGroupSession();
    await service.stopping.future;
    groups.result.complete(Group(id: 'stale-group'));
    await expectLater(create, throwsA(isA<GroupCreationInterrupted>()));
    expect(container.read(appStateProvider).view, original);
    expect(
      container.read(appStateProvider.notifier).groupById('stale-group'),
      isNull,
    );
    expect(sends, 0);
    service.release.complete();
    await teardown;
  });
}
