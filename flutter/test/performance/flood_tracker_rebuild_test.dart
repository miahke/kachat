import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/features/messages/flood_tracker.dart';
import 'package:nym_bar/models/message.dart';
import 'package:nym_bar/state/app_state.dart';

void main() {
  test('relay count updates do not replay unchanged message history', () {
    final messages = [
      for (var i = 0; i < 3; i++)
        Message(id: '$i', author: 'a', pubkey: 'peer', content: 'hello there', createdAt: 1, timestamp: 1000 + i),
    ];
    final container = ProviderContainer(overrides: [
      messagesForCurrentViewProvider.overrideWith((ref) => messages),
    ]);
    addTearDown(container.dispose);
    final app = container.read(appStateProvider.notifier);
    app.setProxyMode(false);
    final first = container.read(floodTrackerProvider);
    app.setConnectedRelays(1);
    expect(identical(container.read(floodTrackerProvider), first), isTrue);
    app.setProxyMode(true);
    expect(container.read(floodTrackerProvider), same(FloodTracker.empty));
  });
}
