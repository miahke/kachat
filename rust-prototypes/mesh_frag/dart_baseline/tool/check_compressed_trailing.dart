import 'dart:io';
import 'dart:typed_data';

import '../lib/services/mesh/protocol/bitchat_packet.dart';

String hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List packetWithCompressed(Uint8List compressed, int originalSize) {
  final w = BytesBuilder();
  void u8(int v) => w.add([v & 0xFF]);
  void u16(int v) {
    u8(v >> 8);
    u8(v);
  }

  u8(1);
  u8(2);
  u8(7);
  for (var i = 0; i < 8; i++) {
    u8(0x30 + i);
  }
  u8(0x04);
  u16(2 + compressed.length);
  for (var i = 0; i < 8; i++) {
    u8(i);
  }
  u16(originalSize);
  w.add(compressed);
  return w.toBytes();
}

void main() {
  final orig = Uint8List(200);
  for (var i = 0; i < orig.length; i++) {
    orig[i] = i & 0xFF;
  }
  final codec = ZLibCodec(raw: true);
  final compressed = Uint8List.fromList(codec.encode(orig));
  for (final suffix in <List<int>>[
    <int>[],
    <int>[0x00],
    <int>[0xAA, 0xBB, 0xCC],
  ]) {
    final c = Uint8List.fromList([...compressed, ...suffix]);
    final raw = packetWithCompressed(c, orig.length);
    final p = BinaryProtocol.decode(raw);
    stdout.writeln(
        'suffix=${suffix.length} raw=${hex(raw)} ok=${p != null} payload_len=${p?.payload.length}');
  }
}
