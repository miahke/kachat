import 'dart:typed_data';

import '../lib/services/mesh/protocol/bitchat_packet.dart';

void main() {
  for (final tsBytes in [
    [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
    [0x80, 0, 0, 0, 0, 0, 0, 0],
    [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFE],
    [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],
  ]) {
    final b = Uint8List(22);
    b[0] = 1;
    b[1] = 2;
    b[2] = 7;
    for (var i = 0; i < 8; i++) {
      b[3 + i] = tsBytes[i];
    }
    b[11] = 0;
    b[12] = 0;
    b[13] = 0;
    for (var i = 14; i < 22; i++) {
      b[i] = i - 14;
    }
    final p = BinaryProtocol.decode(b);
    print('${tsBytes.map((e) => e.toRadixString(16)).join()} -> ${p?.timestamp}');
    final re = p?.toBytes(padding: false);
    if (re != null) {
      print('  reenc ts: ${re.sublist(3, 11).map((e) => e.toRadixString(16).padLeft(2, '0')).join()}');
    }
  }
}
