import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'package:nym_bar/core/crypto/native_event_id_ffi.dart';

void main() {
  final n = NativeEventId.forTesting(
    DynamicLibrary.open(Platform.environment['NOSTR_TEST_LIBRARY']!),
  );
  final tags = <List<String>>[
    ['e', 'a' * 64],
    ['p', 'b' * 64],
    ['t', 'example'],
  ];
  final content = 'Привет 🌍 message ' * 20;
  String d() => sha256
      .convert(
        utf8.encode(jsonEncode([0, 'a' * 64, 1700000000, 1, tags, content])),
      )
      .toString();
  String r() => n.compute('a' * 64, 1700000000, 1, tags, content)!;
  if (d() != r()) throw StateError('mismatch');
  for (final f in [d, r]) {
    for (var i = 0; i < 5000; i++) {
      f();
    }
    final w = Stopwatch()..start();
    for (var i = 0; i < 50000; i++) {
      f();
    }
    stdout.writeln('${w.elapsedMicroseconds / 50000} us/op');
  }
}
