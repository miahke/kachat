import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nym_bar/core/constants/event_kinds.dart';
import 'package:nym_bar/models/channel.dart';
import 'package:nym_bar/models/settings.dart';
import 'package:nym_bar/state/settings_provider.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/services/nostr/identity_service.dart';
import 'package:nym_bar/services/nostr/nostr_service.dart';

void main() {
  final identity = Identity(pubkey: 'a' * 64, privkey: null, nym: 'test');

  test('selected mode requests only chosen and open geotopic messages', () {
    final service = NostrService(
      identity: identity,
      useProxy: false,
      relays: [],
    );
    service.updateCriticalInputs(
      selectedGeoTopicsOnly: true,
      selectedGeoTopics: ['9q', 'INVALID', '9q'],
      activeGeoTopic: 'w2',
    );
    final filters = service.criticalFiltersForTest();
    final geo = filters
        .where((f) => f.kinds?.contains(EventKind.geoChannel) ?? false)
        .toList();
    expect(geo, hasLength(1));
    expect(geo.single.tags['g'], ['9q', 'w2']);
    expect(
      filters.any((f) => f.kinds?.contains(EventKind.namedChannel) ?? false),
      isTrue,
    );
    expect(
      filters.any((f) => f.kinds?.contains(EventKind.giftWrap) ?? false),
      isTrue,
    );
  });

  test('selected mode without chosen or open geotopic skips geo messages', () {
    final service = NostrService(
      identity: identity,
      useProxy: false,
      relays: [],
    );
    service.updateCriticalInputs(
      selectedGeoTopicsOnly: true,
      selectedGeoTopics: [],
    );
    expect(
      service.criticalFiltersForTest().any(
        (f) => f.kinds?.contains(EventKind.geoChannel) ?? false,
      ),
      isFalse,
    );
  });

  test('all mode keeps the unfiltered geo message subscription', () {
    final service = NostrService(
      identity: identity,
      useProxy: false,
      relays: [],
    );
    final geo = service.criticalFiltersForTest().singleWhere(
      (f) => f.kinds?.contains(EventKind.geoChannel) ?? false,
    );
    expect(geo.tags['g'], isNull);
  });

  test('channel archive selection keeps named and chosen geo channels', () {
    final keys = channelKeysForGeoMode(
      [
        ChannelEntry(channel: 'nymchat'),
        ChannelEntry(channel: '9q', geohash: '9q'),
        ChannelEntry(channel: 'w2', geohash: 'w2'),
      ],
      selectedOnly: true,
      selectedGeoTopics: {'9q'},
      activeChannel: 'w2',
    );
    expect(keys, {'nymchat', '9q', 'w2'});
    expect(
      channelKeysForGeoMode(
        [
          ChannelEntry(channel: 'nymchat'),
          ChannelEntry(channel: '9q', geohash: '9q'),
          ChannelEntry(channel: 'w2', geohash: 'w2'),
        ],
        selectedOnly: true,
        selectedGeoTopics: {'9q'},
      ),
      {'nymchat', '9q'},
    );
  });

  test('selected geotopics persist independently of favorites', () async {
    SharedPreferences.setMockInitialValues({});
    final kv = await KeyValueStore.open();
    final container = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(kv)],
    );
    final controller = container.read(settingsProvider.notifier);
    controller.setSelectedGeoTopicsOnly(true);
    controller.setGeoTopicSelected('9q', true);
    controller.setGeoTopicSelected('w2', true);
    controller.setGeoTopicSelected('w2', false);
    expect(container.read(settingsProvider).selectedGeoTopicsOnly, isTrue);
    expect(container.read(settingsProvider).selectedGeoTopics, ['9q']);
    expect(Settings.fromStore(kv).selectedGeoTopics, ['9q']);
    container.dispose();
  });
}
