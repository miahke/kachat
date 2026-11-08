import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nym_bar/core/crypto/native_event_id_ffi.dart';
import 'package:nym_bar/models/nostr_event.dart';

void main() {
  final library = Platform.environment['NOSTR_TEST_LIBRARY'];
  final native = library == null
      ? null
      : NativeEventId.forTesting(DynamicLibrary.open(library));
  String expected(
    String pubkey,
    int createdAt,
    int kind,
    List<List<String>> tags,
    String content,
  ) => sha256
      .convert(
        utf8.encode(jsonEncode([0, pubkey, createdAt, kind, tags, content])),
      )
      .toString();

  test(
    'native event id matches Nym with escapes and Unicode',
    () {
      const List<List<String>> tags = [
        ['e', 'a\\b\n'],
        [],
        ['🌍', '"'],
      ];
      expect(
        native!.compute('ключ', -42, 1, tags, 'hello\n🌍'),
        expected('ключ', -42, 1, tags, 'hello\n🌍'),
      );
    },
    skip: library == null
        ? 'Set NOSTR_TEST_LIBRARY to run native integration'
        : false,
  );
  test('lone surrogates in content and tags use Dart fallback', () {
    final bad = String.fromCharCode(0xd800);
    if (native != null) {
      expect(native.compute('key', 1, 1, const [], bad), isNull);
      expect(
        native.compute('key', 1, 1, [
          [bad],
        ], 'ok'),
        isNull,
      );
    }
    expect(
      NostrEvent(
        pubkey: 'key',
        createdAt: 1,
        kind: 1,
        content: bad,
      ).computeId(),
      expected('key', 1, 1, [], bad),
    );
    expect(
      UnsignedEvent(
        pubkey: 'key',
        createdAt: 1,
        kind: 1,
        tags: [
          [bad],
        ],
      ).computeId(),
      expected('key', 1, 1, [
        [bad],
      ], ''),
    );
  });
}
