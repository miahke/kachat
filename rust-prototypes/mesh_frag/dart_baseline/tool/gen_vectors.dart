// Generates golden vectors from the verbatim Dart implementation and writes
// them to vectors.txt for the Rust prototype tests.
//
// Run: dart run tool/gen_vectors.dart <out-file>
import 'dart:io';
import 'dart:typed_data';

import '../lib/services/mesh/fragmentation.dart';
import '../lib/services/mesh/protocol/bitchat_packet.dart';
import '../lib/services/mesh/protocol/fragment_payload.dart';
import '../lib/services/mesh/protocol/message_padding.dart';
import '../lib/services/mesh/protocol/mesh_message_type.dart';

String hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List pat(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed * 7) & 0xFF));

Future<void> main(List<String> args) async {
  final out = File(args.isEmpty ? 'vectors.txt' : args[0]).openWrite();
  void emit(String s) => out.writeln(s);

  emit('# mesh_frag vectors v1');
  emit('# packet_cases <name> <version> <type> <ttl> <timestamp> <flags-present>');

  // Deterministic cases covering v1/v2, recipient, signature, route, sizes
  // around the 512-byte fragment threshold.
  final cases = <Map<String, Object>>[
    {
      'name': 'small_v1',
      'version': 1, 'type': MeshMessageType.message, 'ttl': 7,
      'ts': 1700000000000, 'payloadLen': 100, 'recipient': false,
      'sig': false, 'route': <int>[],
    },
    {
      'name': 'exact_threshold',
      'version': 1, 'type': MeshMessageType.message, 'ttl': 3,
      'ts': 1700000000123, 'payloadLen': 480, 'recipient': true,
      'sig': true, 'route': <int>[],
    },
    {
      'name': 'frag_two_parts',
      'version': 1, 'type': MeshMessageType.fileTransfer, 'ttl': 7,
      'ts': 1700000000456, 'payloadLen': 3000, 'recipient': false,
      'sig': false, 'route': <int>[],
    },
    {
      'name': 'frag_v2_route',
      'version': 2, 'type': MeshMessageType.noiseEncrypted, 'ttl': 5,
      'ts': 1700000000789, 'payloadLen': 5000, 'recipient': true,
      'sig': true, 'route': [0x0102030405060708, 0x1112131415161718],
    },
    {
      'name': 'frag_many',
      'version': 1, 'type': MeshMessageType.fileTransfer, 'ttl': 2,
      'ts': 1700000000999, 'payloadLen': 40000, 'recipient': false,
      'sig': false, 'route': <int>[],
    },
    {
      'name': 'already_fragment_type',
      'version': 1, 'type': MeshMessageType.fragment, 'ttl': 7,
      'ts': 1700000000111, 'payloadLen': 600, 'recipient': false,
      'sig': false, 'route': <int>[],
    },
  ];

  for (final c in cases) {
    final name = c['name'] as String;
    // Build route ids as 8-byte big-endian of the given values.
    final routeBytes = <Uint8List>[];
    for (final v in (c['route'] as List<int>)) {
      final b = Uint8List(8);
      var x = v;
      for (var i = 7; i >= 0; i--) { b[i] = x & 0xFF; x >>= 8; }
      routeBytes.add(b);
    }
    final pkt = BitchatPacket(
      version: c['version'] as int,
      type: c['type'] as int,
      senderID: pat(8, 3),
      recipientID: (c['recipient'] as bool) ? pat(8, 9) : null,
      timestamp: c['ts'] as int,
      payload: pat(c['payloadLen'] as int, 5),
      signature: (c['sig'] as bool) ? pat(64, 11) : null,
      ttl: c['ttl'] as int,
      route: routeBytes.isEmpty ? null : routeBytes,
    );

    final full = pkt.toBytes(padding: false)!;
    emit('packet $name');
    emit('full ${hex(full)}');
    emit('packet_hex sender ${hex(pkt.senderID)}');
    emit('packet_hex recipient ${pkt.recipientID == null ? '-' : hex(pkt.recipientID!)}');
    emit('packet_hex signature ${pkt.signature == null ? '-' : hex(pkt.signature!)}');
    emit('packet_hex route ${pkt.route == null ? '-' : pkt.route!.map(hex).join(",")}');
    emit('packet_fields version ${pkt.version} type ${pkt.type} ttl ${pkt.ttl} ts ${pkt.timestamp}');

    // Decode check: wire bytes (padded) must decode back.
    final wire = pkt.toBytes()!;
    emit('wire ${hex(wire)}');
    final dec = BinaryProtocol.decode(wire);
    emit('decode_ok ${dec != null && hex(dec.toBytes(padding: false)!) == hex(full)}');

    // Fragment and emit each fragment's payload + wire bytes.
    final frags = PacketFragmenter.fragment(pkt);
    emit('frag_count ${frags.length}');
    for (var i = 0; i < frags.length; i++) {
      final f = frags[i];
      final fp = FragmentPayload.decode(f.payload)!;
      emit('frag $i id ${hex(fp.fragmentID)} index ${fp.index} total ${fp.total} otype ${fp.originalType} sender ${hex(f.senderID)} recip ${f.recipientID == null ? "-" : hex(f.recipientID!)} ver ${f.version} type ${f.type} ttl ${f.ttl} ts ${f.timestamp} payload ${hex(f.payload)} wire ${hex(f.toBytes()!)}');
    }

    // Reassemble: feed fragment payloads (out of order: reverse) to reassembler.
    final re = FragmentReassembler();
    Uint8List? got;
    for (var i = frags.length - 1; i >= 0; i--) {
      final fp = FragmentPayload.decode(frags[i].payload)!;
      final r = re.accept(fp);
      if (r != null) got = r;
    }
    emit('reassembled ${got == null ? "-" : hex(got)}');
    emit('reassembled_ok ${got != null && hex(got) == hex(full)}');

    // Sign bytes vector for signature-path parity.
    emit('signing ${hex(pkt.toBytesForSigning()!)}');
    emit('end $name');
  }

  // Padding vectors.
  emit('pad_vectors');
  for (final n in [0, 1, 100, 240, 241, 255, 256, 500, 1000, 4096]) {
    final d = pat(n, 13);
    final target = MessagePadding.optimalBlockSize(n);
    final pp = MessagePadding.pad(d, target);
    final u = MessagePadding.unpad(pp);
    emit('pad $n $target ${hex(pp)} unpad_ok ${hex(u) == hex(d)}');
  }

  // Compressed-packet decode vector: hand-built v1 packet, raw deflate.
  {
    final orig = pat(2000, 21);
    final codec = ZLibCodec(raw: true);
    final compressed = Uint8List.fromList(codec.encode(orig));
    final w = _VecWriter();
    w.u8(1); w.u8(MeshMessageType.message); w.u8(7);
    w.u64(1700000002222);
    w.u8(0x04); // compressed flag only
    w.u16(2 + compressed.length);
    w.bytes(pat(8, 31));
    w.u16(orig.length);
    w.bytes(compressed);
    final raw = w.toBytes();
    emit('compressed_raw ${hex(raw)}');
    emit('compressed_orig ${hex(orig)}');
    final dec = BinaryProtocol.decode(raw);
    emit('compressed_ok ${dec != null && hex(dec.payload) == hex(orig)}');
  }

  await out.close();
  stdout.writeln('wrote ${args.isEmpty ? 'vectors.txt' : args[0]}');
}

class _VecWriter {
  final _b = BytesBuilder();
  void u8(int v) => _b.add([v & 0xFF]);
  void u16(int v) { u8(v >> 8); u8(v); }
  void u64(int v) { var x = v; for (var i = 0; i < 8; i++) { _b.add([(x >> (56 - i * 8)) & 0xFF]); } }
  void bytes(Uint8List b) => _b.add(b);
  Uint8List toBytes() => _b.toBytes();
}
