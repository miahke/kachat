import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/crypto/keys.dart' as keys;
import 'package:nym_bar/models/nostr_event.dart';
import 'package:nym_bar/services/nostr/event_signer.dart';
import 'package:nym_bar/services/nostr/identity_service.dart';
import 'package:nym_bar/services/nostr/nostr_service.dart';

class DelegatedSigner implements EventSigner {
  DelegatedSigner(this.local);
  final LocalSigner local;
  @override String get pubkey => local.pubkey;
  @override bool get isRemote => true;
  @override Future<NostrEvent> sign(UnsignedEvent event) => local.sign(event);
  @override Future<String> nip44Encrypt(String peer, String text) => local.nip44Encrypt(peer, text);
  @override Future<String> nip44Decrypt(String peer, String text) => local.nip44Decrypt(peer, text);
}

void main() {
  test('Bitchat-only send fails when no recipient wrap can be built', () async {
    final signer = DelegatedSigner(LocalSigner(keys.generatePrivateKey()));
    final recipient = keys.getPublicKeyHex(keys.generatePrivateKey());
    final service = NostrService(identity: Identity(pubkey: signer.pubkey, privkey: null, nym: ''), signer: signer, useProxy: false, relays: []);
    final rumor = UnsignedEvent(pubkey: signer.pubkey, createdAt: 1, kind: 14, tags: [], content: 'hello');
    expect(await service.publishPM(rumor: rumor, recipientPubkey: recipient, bitchatRumors: [rumor], sendNymWrap: false), isFalse);
  });
  test('remote signer sends Nym when Bitchat is unavailable', () async {
    final signer = DelegatedSigner(LocalSigner(keys.generatePrivateKey()));
    final recipient = keys.getPublicKeyHex(keys.generatePrivateKey());
    final service = NostrService(identity: Identity(pubkey: signer.pubkey, privkey: null, nym: ''), signer: signer, useProxy: false, relays: []);
    final rumor = UnsignedEvent(pubkey: signer.pubkey, createdAt: 1, kind: 14, tags: [], content: 'hello');
    final wraps = <NostrEvent>[];
    expect(await service.publishPM(rumor: rumor, recipientPubkey: recipient, bitchatRumors: [rumor], onWrap: wraps.add), isTrue);
    expect(wraps, hasLength(2));
  });

}
