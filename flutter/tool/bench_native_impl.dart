import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

typedef _NativeFragment = IntPtr Function(
  Pointer<Uint8>,
  IntPtr,
  Pointer<Uint8>,
  IntPtr,
  Uint8,
  Pointer<Uint8>,
  IntPtr,
);
typedef _DartFragment = int Function(
  Pointer<Uint8>,
  int,
  Pointer<Uint8>,
  int,
  int,
  Pointer<Uint8>,
  int,
);

/// Optional acceleration. Missing libraries and call failures use the Dart codec.
class NativeFragment {
  NativeFragment._();

  static final _DartFragment? _fragment = _load();

  static _DartFragment? _load() {
    if (!Platform.isLinux) return null;
    try {
      return DynamicLibrary.open(
        '../rust-prototypes/mesh_frag/crate/target/release/libmesh_frag.so',
      ).lookupFunction<_NativeFragment, _DartFragment>(
        'mesh_fragment_payloads',
      );
    } catch (_) {
      return null;
    }
  }

  static List<Uint8List>? split(
    Uint8List data,
    Uint8List id,
    int size,
    int type,
  ) {
    final fragment = _fragment;
    if (fragment == null || id.length != 8 || size <= 0 || data.isEmpty) {
      return null;
    }
    final count = (data.length + size - 1) ~/ size;
    if (count > 256) return null;
    final outputSize = data.length + 13 * count;
    final input = calloc<Uint8>(data.length);
    final idBuffer = calloc<Uint8>(8);
    final output = calloc<Uint8>(outputSize);
    try {
      input.asTypedList(data.length).setAll(0, data);
      idBuffer.asTypedList(8).setAll(0, id);
      if (fragment(
            input,
            data.length,
            idBuffer,
            size,
            type,
            output,
            outputSize,
          ) !=
          outputSize) {
        return null;
      }
      final bytes = output.asTypedList(outputSize);
      final result = <Uint8List>[];
      var offset = 0;
      for (var i = 0; i < count; i++) {
        final remaining = data.length - i * size;
        final length = 13 + (remaining < size ? remaining : size);
        result.add(Uint8List.fromList(bytes.sublist(offset, offset + length)));
        offset += length;
      }
      return result;
    } catch (_) {
      return null;
    } finally {
      calloc.free(input);
      calloc.free(idBuffer);
      calloc.free(output);
    }
  }
}
