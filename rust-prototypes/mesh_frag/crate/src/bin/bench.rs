//! Throughput benchmark: fragment+encode and decode+reassemble.
//! Same workload shape as the Dart baseline (see ../dart_baseline/tool/bench.dart).

use std::hint::black_box;
use std::time::Instant;

use mesh_frag::fragment::{self, FragmentReassembler};
use mesh_frag::packet::{self, BitchatPacket};

fn pat(n: usize, seed: usize) -> Vec<u8> {
    (0..n).map(|i| ((i * 31 + seed * 7) & 0xFF) as u8).collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let iters: usize = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(2000);

    // Workload: ~3 KiB payloads -> multi-fragment packets, plus decode of wires.
    let mk = |payload_len: usize| BitchatPacket {
        version: 1,
        type_: 0x02,
        sender_id: {
            let mut s = [0u8; 8];
            s.copy_from_slice(&pat(8, 3));
            s
        },
        recipient_id: None,
        timestamp: 1_700_000_000_456,
        payload: pat(payload_len, 5),
        signature: None,
        ttl: 7,
        route: None,
    };

    let packets: Vec<BitchatPacket> = (0..64).map(|i| mk(2900 + (i % 8) * 700)).collect();

    // Warmup.
    for p in &packets {
        let frags = fragment::fragment(p, || [0xAB; 8]);
        black_box(&frags);
    }

    let t0 = Instant::now();
    let mut frag_count = 0usize;
    for _ in 0..iters {
        for p in &packets {
            let frags = fragment::fragment(p, || [0xAB; 8]);
            frag_count += frags.len();
            for f in &frags {
                black_box(packet::encode(f, true));
            }
        }
    }
    let frag_dur = t0.elapsed();
    let frag_ops = iters * packets.len();

    // Reassemble path: decode wire bytes -> FragmentPayload -> accept.
    let wires: Vec<Vec<u8>> = packets
        .iter()
        .enumerate()
        .flat_map(|(i, p)| {
            let id = [i as u8; 8];
            fragment::fragment(p, || id)
                .iter()
                .map(|f| packet::encode(f, true).unwrap())
                .collect::<Vec<_>>()
        })
        .collect();

    let mut re = FragmentReassembler::new();
    let t1 = Instant::now();
    let mut accepted = 0usize;
    for _ in 0..iters {
        // Feed in reverse order to exercise out-of-order reassembly.
        for w in wires.iter().rev() {
            if let Some(pkt) = packet::decode(w) {
                if let Some(fp) = fragment::FragmentPayload::decode(&pkt.payload) {
                    if re.accept(&fp).is_some() {
                        accepted += 1;
                    }
                }
            }
        }
        if re.pending() > 0 {
            re.clear();
        }
    }
    let re_dur = t1.elapsed();

    let frag_ms = frag_dur.as_secs_f64() * 1e3;
    let re_ms = re_dur.as_secs_f64() * 1e3;
    println!(
        "iters={} packets_per_iter={} frag_count={} accepted={}",
        iters,
        packets.len(),
        frag_count,
        accepted
    );
    println!(
        "fragment+encode: {:.3} ms total, {:.1} us/packet, {:.0} pkt/s",
        frag_ms,
        frag_ms * 1e3 / frag_ops as f64,
        frag_ops as f64 / frag_dur.as_secs_f64()
    );
    println!(
        "decode+reassemble: {:.3} ms total, {:.1} us/wire, {:.0} wire/s",
        re_ms,
        re_ms * 1e3 / (iters * wires.len()) as f64,
        (iters * wires.len()) as f64 / re_dur.as_secs_f64()
    );
}
