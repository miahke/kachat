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
    try {
      if (!Platform.isAndroid) return null;
      return DynamicLibrary.open('libmesh_frag.so')
          .lookupFunction<_NativeFragment, _DartFragment>(
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
    int type, {
    DynamicLibrary? libraryForTesting,
  }) {
    final fragment = libraryForTesting == null
        ? _fragment
        : libraryForTesting.lookupFunction<_NativeFragment, _DartFragment>(
            'mesh_fragment_payloads',
          );
    if (fragment == null || id.length != 8 || size <= 0 || data.isEmpty) {
      return null;
    }
    final count = (data.length + size - 1) ~/ size;
    if (count > 256) return null;
    final outputSize = data.length + 13 * count;
    Pointer<Uint8>? input;
    Pointer<Uint8>? idBuffer;
    Pointer<Uint8>? output;
    try {
      input = calloc<Uint8>(data.length);
      idBuffer = calloc<Uint8>(8);
      output = calloc<Uint8>(outputSize);
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
      if (input != null) calloc.free(input);
      if (idBuffer != null) calloc.free(idBuffer);
      if (output != null) calloc.free(output);
    }
  }
}
