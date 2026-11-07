import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/crypto/ml_kem.dart';
import 'package:nym_bar/core/crypto/pq.dart' as pq;
import 'package:nym_bar/features/identity/pq_registry.dart';

final _pubkey = 'a' * 64;
final _ttl = pqTtl.inSeconds;

Uint8List _kemKey(int seed) => Uint8List(mlKemPublicKeyLength)..[0] = seed;

String _announce({
  required int createdAt,
  Uint8List? key,
  int? expiresAt,
  bool keyless = false,
}) =>
    PqAnnouncement.encode(
      publicKey: keyless ? null : (key ?? _kemKey(1)),
      expiresAt: expiresAt ?? createdAt + _ttl,
      epoch: 1,
      devices: const [],
    );

void main() {
  group('PqRegistry stale event ordering', () {
    test('a replayed old retraction must not erase a newer key', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      // Key announced at t0, retracted at t0+200, re-announced at t0+400.
      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNotNull);

      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 200),
          nowSec: now, createdAt: t0 + 200);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);

      reg.ingest(_pubkey, _announce(createdAt: t0 + 400, key: _kemKey(2)),
          nowSec: now, createdAt: t0 + 400);
      expect(pq.b64uEncode(reg.keyFor(_pubkey, nowSec: now, enabled: true)!),
          pq.b64uEncode(_kemKey(2)));

      // Relay replays the old signed retraction: the live key must survive.
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 200),
          nowSec: now, createdAt: t0 + 200);
      expect(pq.b64uEncode(reg.keyFor(_pubkey, nowSec: now, enabled: true)!),
          pq.b64uEncode(_kemKey(2)));
    });

    test('a replayed old expired announcement must not erase a newer key', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 5000;

      // Live entry announced at t0+400 (exp = t0+400+ttl).
      reg.ingest(_pubkey, _announce(createdAt: t0 + 400),
          nowSec: now, createdAt: t0 + 400);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNotNull);

      // An older announcement whose own expiry already passed arrives late.
      reg.ingest(
          _pubkey,
          _announce(
              createdAt: t0,
              expiresAt: t0 + 10), // expired long before `now`
          nowSec: now,
          createdAt: t0);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNotNull);
    });

    test('a newer retraction still removes the key', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 900),
          nowSec: now, createdAt: t0 + 900);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);
      expect(reg.isKnownNymchatClient(_pubkey, nowSec: now), isFalse);
    });

    test('a newer expired announcement still clears the entry', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 5000;

      reg.ingest(_pubkey, _announce(createdAt: t0 + 400),
          nowSec: now, createdAt: t0 + 400);
      // Newest event is an announcement that already expired.
      reg.ingest(
          _pubkey,
          _announce(createdAt: t0 + 4500, expiresAt: t0 + 4600),
          nowSec: now,
          createdAt: t0 + 4500);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);
    });

    test('unordered events cannot displace a held entry', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      // created_at = 0 is unordered: neither a stale key nor a retraction may apply.
      reg.ingest(_pubkey, _announce(createdAt: 0, key: _kemKey(9)),
          nowSec: now,
          createdAt: 0);
      expect(pq.b64uEncode(reg.keyFor(_pubkey, nowSec: now, enabled: true)!),
          pq.b64uEncode(_kemKey(1)));
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 900),
          nowSec: now,
          createdAt: 0);
      expect(pq.b64uEncode(reg.keyFor(_pubkey, nowSec: now, enabled: true)!),
          pq.b64uEncode(_kemKey(1)));
    });

    test('a replayed pre-retraction announcement cannot resurrect the key', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 900),
          nowSec: now, createdAt: t0 + 900);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);

      // Relay replays the older still-valid announcement: the retraction's
      // created_at is remembered, so the retired key stays retired.
      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);
      expect(reg.isKnownNymchatClient(_pubkey, nowSec: now), isFalse);
    });

    test('a strictly newer announcement still restores the key after retraction',
        () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 900),
          nowSec: now, createdAt: t0 + 900);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);

      // The peer genuinely re-announces later: the key comes back.
      reg.ingest(_pubkey, _announce(createdAt: t0 + 950, key: _kemKey(3)),
          nowSec: now, createdAt: t0 + 950);
      expect(pq.b64uEncode(reg.keyFor(_pubkey, nowSec: now, enabled: true)!),
          pq.b64uEncode(_kemKey(3)));
    });

    test('an unordered replay cannot resurrect a retracted key', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      reg.ingest(_pubkey, _announce(createdAt: t0),
          nowSec: now, createdAt: t0);
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 900),
          nowSec: now, createdAt: t0 + 900);
      reg.ingest(_pubkey, _announce(createdAt: 0, key: _kemKey(9)),
          nowSec: now,
          createdAt: 0);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);
    });

    test('retraction survives hydration and rejects equal timestamp replay', () {
      const t0 = 1700000000;
      const now = t0 + 1000;
      final reg = PqRegistry();
      reg.ingest(_pubkey, _announce(createdAt: t0), nowSec: now, createdAt: t0);
      reg.ingest(_pubkey, PqAnnouncement.encodeRetraction(t0 + 900),
          nowSec: now, createdAt: t0 + 900);
      final restored = PqRegistry()..hydrate(reg.toJson(nowSec: now), nowSec: now);
      restored.ingest(_pubkey, _announce(createdAt: t0 + 900),
          nowSec: now, createdAt: t0 + 900);
      expect(restored.keyFor(_pubkey, nowSec: now, enabled: true), isNull);
    });

    test('an older replay cannot resurrect a naturally expired entry', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 5000;

      // Short-lived announcement already expired by `now`; its created_at stays
      // remembered so an older still-valid replay cannot take its place.
      reg.ingest(
          _pubkey, _announce(createdAt: t0, expiresAt: t0 + 10),
          nowSec: now, createdAt: t0);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);

      reg.ingest(_pubkey, _announce(createdAt: t0 - 100),
          nowSec: now, createdAt: t0 - 100);
      expect(reg.keyFor(_pubkey, nowSec: now, enabled: true), isNull);
    });

    test('an older live announcement still cannot overwrite a newer key', () {
      final reg = PqRegistry();
      const t0 = 1700000000;
      const now = t0 + 1000;

      reg.ingest(_pubkey, _announce(createdAt: t0 + 400, key: _kemKey(2)),
          nowSec: now, createdAt: t0 + 400);
      reg.ingest(_pubkey, _announce(createdAt: t0, key: _kemKey(1)),
          nowSec: now, createdAt: t0);
      expect(pq.b64uEncode(reg.keyFor(_pubkey, nowSec: now, enabled: true)!),
          pq.b64uEncode(_kemKey(2)));
    });
  });
}
