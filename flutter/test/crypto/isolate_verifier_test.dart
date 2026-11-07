import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/crypto/isolate_verifier.dart';
import 'package:nym_bar/core/crypto/keys.dart';
import 'package:nym_bar/core/crypto/schnorr.dart';
import 'package:nym_bar/models/nostr_event.dart';

NostrEvent _signedEvent(String content) {
  final priv = generatePrivateKey();
  return finalizeEvent(
    UnsignedEvent(
      pubkey: '',
      createdAt: 1700000000,
      kind: 1,
      content: content,
    ),
    priv,
  );
}

/// Same id and content, different signature bytes.
NostrEvent _forgedSig(NostrEvent ev) {
  final sig = ev.sig.split('');
  sig[sig.length - 1] = sig.last == '0' ? '1' : '0';
  return ev.copyWith(sig: sig.join());
}

void main() {
  test('a replayed event with a forged signature is not accepted from cache',
      () async {
    final verifier = IsolateVerifier();
    final ev = _signedEvent('hello');
    expect(await verifier.verify(ev), isTrue);

    // Identical replay hits the cache.
    expect(await verifier.verify(ev.copyWith()), isTrue);

    // The id excludes `sig`, so this event has the same id but an invalid
    // signature; it must go through full verification and fail.
    expect(await verifier.verify(_forgedSig(ev)), isFalse);
  });

  test('snapshot/seed roundtrip only shortcuts the exact verified signature',
      () async {
    final first = IsolateVerifier();
    final ev = _signedEvent('persisted');
    expect(await first.verify(ev), isTrue);

    final second = IsolateVerifier();
    second.markVerified(first.snapshotVerifiedIds());
    expect(await second.verify(ev.copyWith()), isTrue);
    expect(await second.verify(_forgedSig(ev)), isFalse);
  });

  test('a bare seeded id cannot vouch for an unknown signature', () async {
    final verifier = IsolateVerifier();
    final ev = _signedEvent('bare seed');
    verifier.markVerified([ev.id]);
    expect(await verifier.verify(_forgedSig(ev)), isFalse);
    expect(await verifier.verify(ev.copyWith()), isTrue);
  });
}
