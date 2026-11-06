import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nym_bar/core/constants/storage_keys.dart';
import 'package:nym_bar/features/mesh/mesh_bridge.dart';
import 'package:nym_bar/features/mesh/mesh_outbox.dart';
import 'package:nym_bar/services/mesh/mesh_peer.dart';
import 'package:nym_bar/services/storage/key_value_store.dart';
import 'package:nym_bar/services/storage/at_rest_cipher.dart';
import 'package:nym_bar/services/storage/sealed_key_value.dart';
import 'package:nym_bar/state/settings_provider.dart';
import 'package:nym_bar/services/mesh/mesh_service.dart';
import 'package:nym_bar/state/app_state.dart';
import 'package:nym_bar/models/message.dart';
import 'package:nym_bar/services/mesh/noise/noise_identity.dart';
import 'package:nym_bar/services/mesh/protocol/noise_payload.dart';
import 'package:nym_bar/services/mesh/transport/mesh_transport.dart';

class MemoryKeys implements AtRestKeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FakeTransport implements MeshTransport {
  @override
  Future<void> broadcast(Uint8List frame) async {}
  @override
  Stream<MeshInboundFrame> get inbound => const Stream.empty();
  @override
  Stream<MeshLinkEvent> get links => const Stream.empty();
  @override
  MeshTransportAvailability get availability => MeshTransportAvailability.ready;
  @override
  int get connectedLinkCount => 0;
  @override
  Future<void> openSystemSettings() async {}
  @override
  Future<MeshTransportAvailability> start() async => availability;
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('replay parts match the exact ids and text in mesh packets', () async {
    final service = MeshService(
      identity: await NoiseIdentity.ephemeral(),
      transport: FakeTransport(),
      nicknameProvider: () => 'test',
    );
    const peer = '0123456789abcdef';
    final text = '${'x' * 254} 😀 ${'z' * 300}';
    final sent = await service.sendPrivateMessageParts(peer, text);
    final packets = service
        .pendingPlaintextForTest(peer)
        .map(
          (bytes) =>
              PrivateMessagePacket.decode(NoisePayload.decode(bytes)!.data)!,
        )
        .toList();
    expect(sent.length, greaterThan(1));
    expect(sent.map((e) => e.messageID), packets.map((e) => e.messageID));
    expect(sent.map((e) => e.content), packets.map((e) => e.content));
    expect(sent.map((e) => e.content).join(), text);
    expect(sent.map((e) => e.messageID).toSet().length, sent.length);
    expect(sent.every((e) => utf8.encode(e.content).length <= 255), isTrue);
  });
  test('fragment echoes keep spaces and allow whitespace-only fragments', () {
    final app = AppStateNotifier();
    addTearDown(app.dispose);
    final view = ChatView.pm('alice');
    final first = app.sendLocal(
      'part ',
      viewOverride: view,
      preserveWhitespace: true,
    );
    final second = app.sendLocal(
      '   ',
      viewOverride: view,
      preserveWhitespace: true,
    );
    expect(first?.content, 'part ');
    expect(second?.content, '   ');
  });

  for (final meshFirst in [true, false]) {
    test('mesh and Nym fragment copies merge when meshFirst=$meshFirst', () {
      final app = AppStateNotifier();
      addTearDown(app.dispose);
      const peer = 'alice';
      const pieces = ['alpha ', 'beta', 'beta'];
      for (var i = 0; i < pieces.length; i++) {
        Message message(bool mesh) => Message(
          id: mesh ? 'id-$i' : 'relay-$i',
          author: peer,
          pubkey: peer,
          content: pieces[i],
          createdAt: 100,
          isPM: true,
          conversationKey: 'pm-$peer',
          conversationPubkey: peer,
          nymMessageId: 'id-$i',
          senderVerified: true,
          viaMesh: mesh,
        );
        if (meshFirst) {
          app.ingestMeshPm(message(true));
          app.ingestPMMessage(message(false));
        } else {
          app.ingestPMMessage(message(false));
          app.ingestMeshPm(message(true));
        }
      }
      final messages = app.state.messages['pm-$peer']!;
      expect(messages.map((m) => m.content), pieces);
      expect(messages.map((m) => m.nymMessageId), ['id-0', 'id-1', 'id-2']);
    });
  }

  test(
    'bridge queues each exact mesh fragment with its own echo and id',
    () async {
      SharedPreferences.setMockInitialValues({
        StorageKeys.meshEnabled: 'false',
      });
      final kv = await KeyValueStore.open();
      final oldCipher = AtRestCipher.instance;
      final cipher = AtRestCipher(MemoryKeys());
      AtRestCipher.instance = cipher;
      addTearDown(() {
        AtRestCipher.instance = oldCipher;
      });
      final service = MeshService(
        identity: await NoiseIdentity.ephemeral(),
        transport: FakeTransport(),
        nicknameProvider: () => 'test',
      );
      final bridgeProvider = Provider<MeshBridge>(
        (ref) => MeshBridge(ref: ref, service: service, selfNym: () => 'test'),
      );
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(kv)],
      );
      addTearDown(container.dispose);
      final bridge = container.read(bridgeProvider);
      const peerId = '0123456789abcdef';
      final pubkey = bridge.openPeerDm(
        MeshPeer(
          peerID: peerId,
          nostrPubkey: 'a' * 64,
          nostrLinkVerified: true,
        ),
      );
      final view = ChatView.pm(pubkey);
      final text = ['x' * 255, ' ' * 255, 'end'].join();
      await bridge.sendFromComposer(view, text);
      await KeyValueStore.settle();
      final packets = service
          .pendingPlaintextForTest(peerId)
          .map(
            (bytes) =>
                PrivateMessagePacket.decode(NoisePayload.decode(bytes)!.data)!,
          )
          .toList();
      final saved = await SealedKeyValue(
        kv,
        cipher: cipher,
      ).read(StorageKeys.meshOutbox);
      final queue = MeshOutbox()..decode(saved);
      final echoes = container
          .read(appStateProvider)
          .messages[view.storageKey]!;
      expect(queue.entries.length, 1);
      final queuedParts = queue.entries.single.parts!;
      expect(queuedParts.map((e) => e.content), packets.map((p) => p.content));
      expect(
        queuedParts.map((e) => e.messageId),
        packets.map((p) => p.messageID),
      );
      expect(echoes.map((e) => e.content), packets.map((p) => p.content));
      expect(
        echoes.map((e) => e.nymMessageId),
        packets.map((p) => p.messageID),
      );
    },
  );

  test('Nym self copies reconcile with each fragment echo', () {
    final app = AppStateNotifier();
    addTearDown(app.dispose);
    final view = ChatView.pm('alice');
    for (var i = 0; i < 3; i++) {
      final id = 'id-$i';
      final echo = app.sendLocal(
        'same',
        nymMessageId: id,
        viewOverride: view,
        preserveWhitespace: true,
      )!;
      app.ingestPMMessage(
        Message(
          id: 'self-$i',
          author: echo.author,
          pubkey: echo.pubkey,
          content: echo.content,
          createdAt: echo.createdAt,
          isOwn: true,
          isPM: true,
          conversationKey: view.storageKey,
          conversationPubkey: 'alice',
          nymMessageId: id,
          senderVerified: true,
        ),
      );
    }
    expect(app.state.messages[view.storageKey]!.length, 3);
  });
}
