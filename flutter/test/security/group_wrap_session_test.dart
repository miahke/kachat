import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/crypto/keys.dart' as keys;
import 'package:nym_bar/models/nostr_event.dart';
import 'package:nym_bar/services/nostr/event_signer.dart';
import 'package:nym_bar/services/nostr/identity_service.dart';
import 'package:nym_bar/services/nostr/nostr_service.dart';

class ControlledSigner implements EventSigner {
  ControlledSigner(this.local);
  final LocalSigner local;
  final started = Completer<void>();
  final release = Completer<void>();
  int signs = 0;
  bool failSecond = false;
  @override
  String get pubkey => local.pubkey;
  @override
  bool get isRemote => true;
  @override
  Future<NostrEvent> sign(UnsignedEvent event) async {
    signs++;
    if (signs == 1) {
      started.complete();
      await release.future;
    }
    if (failSecond && signs == 2) throw StateError('sign failed');
    return local.sign(event);
  }

  @override
  Future<String> nip44Encrypt(String peer, String text) =>
      local.nip44Encrypt(peer, text);
  @override
  Future<String> nip44Decrypt(String peer, String text) =>
      local.nip44Decrypt(peer, text);
}

class RecordingService extends NostrService {
  RecordingService(Identity identity, EventSigner signer)
    : super(identity: identity, signer: signer, useProxy: false, relays: []);
  final queued = <NostrEvent>[];
  @override
  void publishDmQueued(NostrEvent event, {int tier = 0}) => queued.add(event);
}

void main() {
  test('session cancellation during signing queues no wraps', () async {
    final signer = ControlledSigner(LocalSigner(keys.generatePrivateKey()));
    final service = RecordingService(
      Identity(pubkey: signer.pubkey, privkey: null, nym: ''),
      signer,
    );
    final recipient = keys.getPublicKeyHex(keys.generatePrivateKey());
    final rumor = UnsignedEvent(
      pubkey: signer.pubkey,
      createdAt: 1,
      kind: 14,
      tags: [],
      content: 'hello',
    );
    var live = true;
    final send = service.publishGroupMessage(
      rumor: rumor,
      recipients: [recipient],
      encryptTo: (p) => p,
      canPublish: () => live,
    );
    await signer.started.future;
    live = false;
    signer.release.complete();
    expect(await send, isFalse);
    expect(service.queued, isEmpty);
  });

  test(
    'remote signer failure before completing fan-out queues nothing',
    () async {
      final signer = ControlledSigner(LocalSigner(keys.generatePrivateKey()))
        ..failSecond = true;
      final service = RecordingService(
        Identity(pubkey: signer.pubkey, privkey: null, nym: ''),
        signer,
      );
      final recipients = List.generate(
        2,
        (_) => keys.getPublicKeyHex(keys.generatePrivateKey()),
      );
      final rumor = UnsignedEvent(
        pubkey: signer.pubkey,
        createdAt: 1,
        kind: 14,
        tags: [],
        content: 'hello',
      );
      final send = service.publishGroupMessage(
        rumor: rumor,
        recipients: recipients,
        encryptTo: (p) => p,
        canPublish: () => true,
      );
      await signer.started.future;
      signer.release.complete();
      try {
        await send;
      } catch (_) {}
      expect(service.queued, isEmpty);
    },
  );
  test('session-bound fan-out snapshots recipients before signing', () async {
    final signer = ControlledSigner(LocalSigner(keys.generatePrivateKey()));
    final service = RecordingService(
      Identity(pubkey: signer.pubkey, privkey: null, nym: ''),
      signer,
    );
    final recipients = [keys.getPublicKeyHex(keys.generatePrivateKey())];
    final rumor = UnsignedEvent(
      pubkey: signer.pubkey,
      createdAt: 1,
      kind: 14,
      tags: [],
      content: 'hello',
    );
    final send = service.publishGroupMessage(
      rumor: rumor,
      recipients: recipients,
      encryptTo: (p) => p,
      canPublish: () => true,
    );
    await signer.started.future;
    recipients.add(keys.getPublicKeyHex(keys.generatePrivateKey()));
    signer.release.complete();
    expect(await send, isTrue);
    expect(service.queued, hasLength(1));
  });
}
