import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:nym_bar/services/mesh/native_fragment.dart';
import 'package:nym_bar/services/mesh/protocol/fragment_payload.dart';

void main() {
  test('missing native library uses Dart fallback', () {
    if (!Platform.isAndroid) {
      expect(
        NativeFragment.split(Uint8List(1000), Uint8List(8), 450, 7),
        isNull,
      );
    }
  });
  test('native payloads match Dart including partial final chunk', () {
    final path = Platform.environment['MESH_FRAG_TEST_LIBRARY'];
    if (path == null) return;
    final lib = DynamicLibrary.open(path);
    final id = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
    for (final length in [1, 449, 450, 451, 5000]) {
      final data = Uint8List.fromList(List.generate(length, (i) => i & 255));
      final actual = NativeFragment.split(
        data,
        id,
        450,
        7,
        libraryForTesting: lib,
      )!;
      final count = (length + 449) ~/ 450;
      expect(actual.length, count);
      for (var i = 0; i < count; i++) {
        final start = i * 450;
        final end = start + 450 < length ? start + 450 : length;
        final expected = FragmentPayload(
          fragmentID: id,
          index: i,
          total: count,
          originalType: 7,
          data: Uint8List.fromList(Uint8List.sublistView(data, start, end)),
        ).encode();
        expect(actual[i], orderedEquals(expected));
      }
    }
  });
}
