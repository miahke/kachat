// Baseline benchmark for the Dart implementation.
// Run: dart run tool/bench.dart [iters]
import 'dart:typed_data';

import '../lib/services/mesh/fragmentation.dart';
import '../lib/services/mesh/protocol/bitchat_packet.dart';
import '../lib/services/mesh/protocol/fragment_payload.dart';

Uint8List pat(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed * 7) & 0xFF));

void main(List<String> args) {
  final iters = args.isEmpty ? 2000 : int.parse(args[0]);

  final packets = List.generate(
    64,
    (i) => BitchatPacket(
      version: 1,
      type: 0x02,
      senderID: pat(8, 3),
      timestamp: 1700000000456,
      payload: pat(2900 + (i % 8) * 700, 5),
      ttl: 7,
    ),
  );

  // Warmup.
  for (final p in packets) {
    for (final f in PacketFragmenter.fragment(p)) {
      f.toBytes();
    }
  }

  var fragCount = 0;
  final sw = Stopwatch()..start();
  for (var it = 0; it < iters; it++) {
    for (final p in packets) {
      final frags = PacketFragmenter.fragment(p);
      fragCount += frags.length;
      for (final f in frags) {
        f.toBytes();
      }
    }
  }
  sw.stop();
  final fragMs = sw.elapsedMicroseconds / 1000.0;
  final fragOps = iters * packets.length;

  // Reassemble path: decode wires -> FragmentPayload -> accept, reversed.
  final wires = <Uint8List>[];
  for (var i = 0; i < packets.length; i++) {
    for (final f in PacketFragmenter.fragment(packets[i])) {
      wires.add(f.toBytes()!);
    }
  }
  var accepted = 0;
  final sw2 = Stopwatch()..start();
  for (var it = 0; it < iters; it++) {
    final re = FragmentReassembler();
    for (var i = wires.length - 1; i >= 0; i--) {
      final pkt = BinaryProtocol.decode(wires[i]);
      if (pkt == null) continue;
      final fp = FragmentPayload.decode(pkt.payload);
      if (fp == null) continue;
      if (re.accept(fp) != null) accepted++;
    }
  }
  sw2.stop();
  final reMs = sw2.elapsedMicroseconds / 1000.0;

  print('iters=$iters packets_per_iter=${packets.length} frag_count=$fragCount accepted=$accepted');
  print('fragment+encode: ${fragMs.toStringAsFixed(3)} ms total, ${(fragMs * 1000 / fragOps).toStringAsFixed(1)} us/packet, ${(fragOps / (fragMs / 1000)).toStringAsFixed(0)} pkt/s');
  print('decode+reassemble: ${reMs.toStringAsFixed(3)} ms total, ${(reMs * 1000 / (iters * wires.length)).toStringAsFixed(1)} us/wire, ${(iters * wires.length / (reMs / 1000)).toStringAsFixed(0)} wire/s');
}
