import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/services/api/api_client.dart';
import 'package:nym_bar/services/api/storage_sync.dart';
import 'package:nym_bar/services/nostr/event_signer.dart';

class FakeApi extends ApiClient {
  final requests = <Map<String, dynamic>>[];
  @override
  Future<StorageStream> storageStream(
    Map<String, dynamic> body, {
    String? statsAction,
    bool socket = true,
  }) async {
    requests.add(body);
    return const StorageStream(
      items: [
        {'id': 'wrap1', 'created_at': 1},
      ],
      hasMore: false,
    );
  }
}

void main() {
  test(
    'ephemeral recovery reads a bounded authenticated recent window',
    () async {
      final api = FakeApi();
      final sync = StorageSync(
        api: api,
        signer: LocalSigner(Uint8List.fromList([...List.filled(31, 0), 1])),
        pubkey: 'a' * 64,
        durableIdentity: false,
        now: () => DateTime.fromMillisecondsSinceEpoch(2000000000),
      );
      sync.setAuthBuilder((action) async => {'action': action});
      final wraps = await sync.pmRestoreEphemeral();
      expect(wraps.single['id'], 'wrap1');
      expect(api.requests.single['action'], 'pm-get');
      expect(api.requests.single['pubkey'], 'a' * 64);
      expect(api.requests.single['auth'], {'action': 'pm-get'});
      expect(int.parse(api.requests.single['after'] as String), greaterThan(0));
      expect(await sync.pmRestoreEphemeral(), isEmpty);
    },
  );
}
