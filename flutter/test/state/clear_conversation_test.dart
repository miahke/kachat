import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/state/app_state.dart';
import 'package:nym_bar/state/nostr_controller.dart';
import 'package:nym_bar/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final views = [
    const ChatView.channel('room'),
    ChatView.pm(List.filled(64, 'b').join()),
    const ChatView.group('group-id'),
  ];

  for (final view in views) {
    test(
      '/clear hides the active ${view.kind.name} feed for this session',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await KeyValueStore.open();
        final container = ProviderContainer(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
        );
        addTearDown(container.dispose);
        final app = container.read(appStateProvider.notifier);
        final controller = container.read(nostrControllerProvider);
        final notices = <String>[];
        controller.setCommandHooks(onSystemMessage: notices.add);
        const otherView = ChatView.channel('other');

        app.switchView(view);
        app.addSystemMessage('old message');
        app.addSystemMessage('unrelated', storageKey: otherView.storageKey);
        Iterable<String> shown() => container
            .read(messagesForCurrentViewProvider)
            .map((message) => message.content);
        expect(shown(), ['old message']);

        await controller.sendCurrent('/clear');

        expect(shown(), isEmpty);
        expect(notices, hasLength(1));
        expect(
          container
              .read(appStateProvider)
              .messages[view.storageKey]!
              .map((message) => message.content),
          ['old message'],
        );
        app.switchView(otherView);
        expect(shown(), ['unrelated']);
        app.switchView(view);
        expect(shown(), isEmpty);
        app.addSystemMessage('new message');
        expect(shown(), ['new message']);

        final retained = container
            .read(appStateProvider)
            .messages[view.storageKey]!;
        app.reset();
        app.switchView(view);
        app.hydrateAllMessages({view.storageKey: retained});
        expect(shown(), unorderedEquals(['old message', 'new message']));
      },
    );
  }
}
