import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/constants/event_kinds.dart';
import 'package:nym_bar/core/crypto/bitchat.dart' as bitchat;
import 'package:nym_bar/core/crypto/gift_wrap.dart' as giftwrap;
import 'package:nym_bar/core/crypto/keys.dart';
import 'package:nym_bar/core/crypto/schnorr.dart';
import 'package:nym_bar/features/pms/pm_logic.dart';
import 'package:nym_bar/models/nostr_event.dart';
import 'package:nym_bar/services/nostr/identity_service.dart';
import 'package:nym_bar/services/nostr/nostr_service.dart';

/// Same shape as [_claimedPubkeyBitchatWrap] but the seal event claims
/// [claimedPubkey] as its author while [sealSignerSk] produces the signature,
/// so seal verification must fail.
Future<NostrEvent> _forgedSealBitchatWrap({
  required Uint8List sealSignerSk,
  required String claimedPubkey,
  required String recipientPubkey,
}) async {
  final rumor = UnsignedEvent(
    pubkey: claimedPubkey,
    createdAt: giftwrap.randomNow(),
    kind: EventKind.dmRumor,
    tags: const [],
    content: 'forged seal',
  );
  final rumorMap = {
    'id': rumor.computeId(),
    'pubkey': claimedPubkey,
    'created_at': rumor.createdAt,
    'kind': rumor.kind,
    'tags': rumor.tags,
    'content': rumor.content,
  };

  // Hand-built: pubkey claims [claimedPubkey] but the id is signed by
  // [sealSignerSk], so verification under the claimed key must fail.
  final sealBase = NostrEvent(
    pubkey: claimedPubkey,
    createdAt: giftwrap.randomNow(),
    kind: EventKind.seal,
    tags: const [],
    content: await bitchat.encryptBitchat(
        jsonEncode(rumorMap), sealSignerSk, recipientPubkey),
  );
  sealBase.id = sealBase.computeId();
  sealBase.sig = signId(sealBase.id, sealSignerSk);
  final seal = sealBase;

  final wrapSk = generatePrivateKey();
  return finalizeEvent(
    UnsignedEvent(
      pubkey: getPublicKeyHex(wrapSk),
      createdAt: giftwrap.randomNow(),
      kind: EventKind.giftWrap,
      tags: [
        ['p', recipientPubkey],
      ],
      content: await bitchat.encryptBitchat(
          jsonEncode(seal.toJson()), wrapSk, recipientPubkey),
    ),
    wrapSk,
  );
}

/// Builds a `v2:` Bitchat gift wrap whose inner rumor claims [claimedPubkey]
/// while the seal is signed by [sealSignerSk]'s real key — the impersonation
/// shape an unverified Bitchat sender can produce on the wire.
Future<NostrEvent> _claimedPubkeyBitchatWrap({
  required Uint8List sealSignerSk,
  required String claimedPubkey,
  required String recipientPubkey,
  String content = 'hello from a claimed identity',
}) async {
  final sealSignerPub = getPublicKeyHex(sealSignerSk);
  final rumor = UnsignedEvent(
    pubkey: claimedPubkey,
    createdAt: giftwrap.randomNow(),
    kind: EventKind.dmRumor,
    tags: const [],
    content: content,
  );
  final rumorMap = {
    'id': rumor.computeId(),
    'pubkey': claimedPubkey,
    'created_at': rumor.createdAt,
    'kind': rumor.kind,
    'tags': rumor.tags,
    'content': rumor.content,
  };

  // Kind-13 seal: content encrypted to the recipient, event signed by the
  // attacker's real key — but the rumor inside names someone else.
  final seal = finalizeEvent(
    UnsignedEvent(
      pubkey: sealSignerPub,
      createdAt: giftwrap.randomNow(),
      kind: EventKind.seal,
      tags: const [],
      content: await bitchat.encryptBitchat(
          jsonEncode(rumorMap), sealSignerSk, recipientPubkey),
    ),
    sealSignerSk,
  );

  final wrapSk = generatePrivateKey();
  return finalizeEvent(
    UnsignedEvent(
      pubkey: getPublicKeyHex(wrapSk),
      createdAt: giftwrap.randomNow(),
      kind: EventKind.giftWrap,
      tags: [
        ['p', recipientPubkey],
      ],
      content: await bitchat.encryptBitchat(
          jsonEncode(seal.toJson()), wrapSk, recipientPubkey),
    ),
    wrapSk,
  );
}

void main() {
  late Uint8List selfSk;
  late String selfPub;
  late NostrService service;

  setUp(() {
    selfSk = generatePrivateKey();
    selfPub = getPublicKeyHex(selfSk);
    service = NostrService(
      identity: Identity(pubkey: selfPub, privkey: selfSk, nym: 'tester'),
      relays: const [],
      useProxy: false,
    );
  });

  tearDown(() => service.stop());

  test('bitchat wrap claiming another pubkey unwraps under the claimed identity',
      () async {
    final attackerSk = generatePrivateKey();
    final attackerPub = getPublicKeyHex(attackerSk);
    // The "friend" the attacker claims to be; the attacker holds no key for it.
    final claimedPub = getPublicKeyHex(generatePrivateKey());

    final wrap = await _claimedPubkeyBitchatWrap(
      sealSignerSk: attackerSk,
      claimedPubkey: claimedPub,
      recipientPubkey: selfPub,
    );

    final u = await service.probeArchivedWrap(wrap);
    expect(u, isNotNull);
    expect(u!.isBitchat, isTrue);
    expect(u.rumor['pubkey'], claimedPub);
    // The seal was verifiably NOT signed by the claimed pubkey, yet the
    // unwrapped rumor still carries the claimed identity with no marker
    // beyond senderVerified=false.
    expect(u.senderVerified, isFalse);
    expect(attackerPub, isNot(claimedPub));

    // The unverified gate accepts a plain kind-14 string rumor...
    expect(
        PmLogic.unverifiedWrapAllowed(u.rumor, selfPubkey: selfPub), isTrue);
    // ...and the mapper files the message under the claimed pubkey, which is
    // what the friends-only scope, friend notifications, blocklist checks
    // and format evidence all key on downstream.
    final m = PmLogic.mapPmRumor(
      rumor: u.rumor,
      wrapId: u.wrapId,
      selfPubkey: selfPub,
      senderVerified: u.senderVerified,
    );
    expect(m, isNotNull);
    expect(m!.pubkey, claimedPub);
    expect(m.senderVerified, isFalse);
  });

  test('honest bitchat wrap from our own helper verifies the sender',
      () async {
    // giftwrap.bitchatWrap signs the kind-13 seal with the sender key, the
    // new-protocol shape (upstream Bitchat PR #1345); the seal check upgrades
    // it to a verified sender.
    final peerSk = generatePrivateKey();
    final peerPub = getPublicKeyHex(peerSk);
    final wrap = await giftwrap.bitchatWrap(
      rumor: UnsignedEvent(
        pubkey: peerPub,
        createdAt: giftwrap.randomNow(),
        kind: EventKind.dmRumor,
        content: 'honest peer message',
      ),
      senderPrivkey: peerSk,
      recipientPubkey: selfPub,
    );

    final u = await service.probeArchivedWrap(wrap);
    expect(u, isNotNull);
    expect(u!.isBitchat, isTrue);
    expect(u.rumor['pubkey'], peerPub);
    expect(u.senderVerified, isTrue);
  });

  test('bitchat wrap with a forged seal claiming the victim is dropped',
      () async {
    // seal.pubkey == rumor.pubkey but the signature doesn't verify: same
    // forged-seal rejection as the NIP-59 path.
    final attackerSk = generatePrivateKey();
    final claimedPub = getPublicKeyHex(generatePrivateKey());

    final wrap = await _forgedSealBitchatWrap(
      sealSignerSk: attackerSk,
      claimedPubkey: claimedPub,
      recipientPubkey: selfPub,
    );

    final u = await service.probeArchivedWrap(wrap);
    expect(u, isNull);
  });
}
