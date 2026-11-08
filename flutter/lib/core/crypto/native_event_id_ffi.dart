import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _NativeId = Int32 Function(Pointer<Uint8>, IntPtr, Pointer<Uint8>);
typedef _DartId = int Function(Pointer<Uint8>, int, Pointer<Uint8>);

/// Optional Android acceleration. A null result always selects the Nym path.
class NativeEventId {
  NativeEventId._(DynamicLibrary library)
    : _id = library.lookupFunction<_NativeId, _DartId>('nostr_event_id_json');

  NativeEventId.forTesting(DynamicLibrary library) : this._(library);

  static final NativeEventId? instance = _load();
  final _DartId _id;

  static NativeEventId? _load() {
    if (!Platform.isAndroid) return null;
    try {
      return NativeEventId._(DynamicLibrary.open('libnostr_event_id.so'));
    } catch (_) {
      return null;
    }
  }

  String? compute(
    String pubkey,
    int createdAt,
    int kind,
    List<List<String>> tags,
    String content,
  ) {
    if (!_validUtf16(pubkey) ||
        !_validUtf16(content) ||
        tags.any((tag) => tag.any((part) => !_validUtf16(part)))) {
      return null;
    }
    Pointer<Uint8>? input;
    Pointer<Uint8>? output;
    try {
      final bytes = utf8.encode(
        jsonEncode([pubkey, createdAt, kind, tags, content]),
      );
      input = malloc<Uint8>(bytes.length);
      output = malloc<Uint8>(64);
      input.asTypedList(bytes.length).setAll(0, bytes);
      if (_id(input, bytes.length, output) != 1) return null;
      return ascii.decode(output.asTypedList(64));
    } catch (_) {
      return null;
    } finally {
      if (input != null) malloc.free(input);
      if (output != null) malloc.free(output);
    }
  }
}

bool _validUtf16(String value) {
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length) return false;
      final low = value.codeUnitAt(i);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
