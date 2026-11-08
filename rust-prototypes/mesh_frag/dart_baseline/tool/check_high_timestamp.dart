import 'dart:typed_data';

import '../lib/services/mesh/protocol/bitchat_packet.dart';

void main() {
  final b = Uint8List(22);
  b[0] = 1;
  b[1] = 2;
  b[2] = 7;
  for (var i = 3; i <= 10; i++) {
    b[i] = 0xFF;
  }
  b[11] = 0;
  b[12] = 0;
  b[13] = 0;
  for (var i = 14; i < 22; i++) {
    b[i] = i - 14;
  }
  final p = BinaryProtocol.decode(b);
  print('decoded=${p != null} timestamp=${p?.timestamp}');
  final re = p?.toBytes(padding: false);
  print('reencoded=${re == null ? '-' : re.map((x) => x.toRadixString(16).padLeft(2, '0')).join()}');
}
