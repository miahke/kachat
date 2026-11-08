import 'dart:math';
import 'dart:typed_data';

final Random _rng = Random.secure();

/// Verbatim copy of randomBytes from flutter/lib/core/crypto/keys.dart;
/// the rest of that file pulls in package imports unavailable to `dart run`.
Uint8List randomBytes(int length) {
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = _rng.nextInt(256);
  }
  return out;
}
