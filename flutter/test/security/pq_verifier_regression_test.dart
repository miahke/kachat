import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/crypto/isolate_verifier.dart';
import 'package:nym_bar/core/crypto/schnorr.dart' as schnorr;
import 'package:nym_bar/features/identity/pq_registry.dart';
import 'package:nym_bar/models/nostr_event.dart';

void main() {
  test('stale retraction and expiry cannot remove a fresh PQ key', () {
    const now = 1000000;
    final registry = PqRegistry();
    final key = Uint8List(1184);
    registry.ingest(
      'peer',
      PqAnnouncement.encode(
        publicKey: key,
        expiresAt: now + pqTtl.inSeconds,
        epoch: 1,
        devices: [],
      ),
      nowSec: now,
      createdAt: now,
    );
    registry.ingest(
      'peer',
      PqAnnouncement.encodeRetraction(now - 10),
      nowSec: now,
      createdAt: now - 10,
    );
    expect(registry.keyFor('peer', nowSec: now, enabled: true), isNotNull);
    registry.ingest(
      'peer',
      PqAnnouncement.encode(
        publicKey: key,
        expiresAt: now - 1,
        epoch: 0,
        devices: [],
      ),
      nowSec: now,
      createdAt: now - 20,
    );
    expect(registry.keyFor('peer', nowSec: now, enabled: true), isNotNull);
    registry.ingest(
      'peer',
      PqAnnouncement.encodeRetraction(now + 1),
      nowSec: now,
      createdAt: now + 1,
    );
    expect(registry.keyFor('peer', nowSec: now, enabled: true), isNull);
  });
  test('ordering uses signed timestamp and survives persistence', () {
    const now = 1000000;
    final key = Uint8List(1184);
    final registry = PqRegistry();
    registry.ingest('peer', PqAnnouncement.encode(publicKey: key,
        expiresAt: now + 100, epoch: 1, devices: []),
        nowSec: now, createdAt: now);
    final restored = PqRegistry()..hydrate(registry.toJson(nowSec: now), nowSec: now);
    restored.ingest('peer', PqAnnouncement.encodeRetraction(now - 1),
        nowSec: now, createdAt: now - 1);
    expect(restored.keyFor('peer', nowSec: now, enabled: true), isNotNull);
  });

  test('withdrawal blocks older announcements after restore', () {
    const now = 1000000;
    final key = Uint8List(1184);
    final old = PqAnnouncement.encode(publicKey: key,
        expiresAt: now + pqTtl.inSeconds, epoch: 1, devices: []);
    final registry = PqRegistry();
    registry.ingest('peer', old, nowSec: now, createdAt: now - 10);
    registry.ingest('peer', PqAnnouncement.encodeRetraction(now),
        nowSec: now, createdAt: now);
    expect(registry.isKnownNymchatClient('peer', nowSec: now), isFalse);
    final restored = PqRegistry()..hydrate(registry.toJson(nowSec: now), nowSec: now);
    restored.ingest('peer', old, nowSec: now, createdAt: now - 10);
    expect(restored.keyFor('peer', nowSec: now, enabled: true), isNull);
    restored.ingest('peer', old, nowSec: now, createdAt: now + 1);
    expect(restored.keyFor('peer', nowSec: now, enabled: true), isNotNull);
  });

  test('verified ID never authenticates a different signature', () async {
    final key = Uint8List(32)..[31] = 1;
    final event = schnorr.finalizeEvent(
      UnsignedEvent(pubkey: '', createdAt: 1, kind: 1),
      key,
    );
    final verifier = IsolateVerifier();
    expect(await verifier.verify(event), isTrue);
    final altered = event.copyWith(sig: '0' * 128);
    expect(await verifier.verify(altered), isFalse);
    final seeded = IsolateVerifier()..markVerified([event.id]);
    expect(await seeded.verify(altered), isFalse);
    expect(await seeded.verify(event), isTrue);
  });
}
