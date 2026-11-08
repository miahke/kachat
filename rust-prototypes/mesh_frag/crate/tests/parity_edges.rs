//! Verifier-added parity probes: cases where the Dart baseline's quirks were
//! checked by hand (tool/probe_ts.dart, tool/check_compressed_trailing.dart)
//! and pinned here so the Rust port cannot silently diverge.

use std::io::Write;

use flate2::write::DeflateEncoder;
use flate2::Compression;
use mesh_frag::fragment::{FragmentPayload, FragmentReassembler};
use mesh_frag::packet::{self, FLAG_IS_COMPRESSED};

/// v1 packet bytes: `ver type ttl ts[8] flags len[2] sender[8] payload`.
fn v1_packet(flags: u8, payload_len_field: u16, sender: &[u8; 8], body: &[u8]) -> Vec<u8> {
    let mut b = Vec::new();
    b.push(1);
    b.push(0x02);
    b.push(7);
    b.extend_from_slice(&1_700_000_000_456u64.to_be_bytes());
    b.push(flags);
    b.extend_from_slice(&payload_len_field.to_be_bytes());
    b.extend_from_slice(sender);
    b.extend_from_slice(body);
    b
}

#[test]
fn timestamp_at_or_above_i64_max_saturates_like_dart() {
    // Dart: _ByteReader.u64 -> BigInt.toInt() saturates at i64::MAX
    // (probe_ts.dart: ffffffffffffffff / 8000000000000000 /
    // fffffffffffffffe all decode to 9223372036854775807, re-encode as
    // 7fffffffffffffff). Values below 2^63 pass through unchanged.
    for (ts, expected) in [
        (u64::MAX, i64::MAX as u64),
        (0x8000_0000_0000_0000, i64::MAX as u64),
        (u64::MAX - 1, i64::MAX as u64),
        (0x00FF_FFFF_FFFF_FFFF, 0x00FF_FFFF_FFFF_FFFF),
        (1_700_000_000_456, 1_700_000_000_456),
    ] {
        let mut b = Vec::new();
        b.push(1);
        b.push(2);
        b.push(7);
        b.extend_from_slice(&ts.to_be_bytes());
        b.push(0);
        b.extend_from_slice(&0u16.to_be_bytes());
        b.extend_from_slice(&[0, 1, 2, 3, 4, 5, 6, 7]);
        let p = packet::decode(&b).expect("decode");
        assert_eq!(p.timestamp, expected, "ts={ts:#x}");
        let re = packet::encode(&p, false).unwrap();
        assert_eq!(&re[3..11], &expected.to_be_bytes(), "re-encode ts={ts:#x}");
    }
}

#[test]
fn compressed_payload_tolerates_trailing_garbage_like_dart() {
    // Dart ZLibCodec(raw).decode ignores bytes after the deflate stream end
    // (check_compressed_trailing.dart: suffix 0/1/3 all decode ok).
    let orig: Vec<u8> = (0..200).map(|i| (i & 0xFF) as u8).collect();
    let mut enc = DeflateEncoder::new(Vec::new(), Compression::default());
    enc.write_all(&orig).unwrap();
    let compressed = enc.finish().unwrap();

    for suffix in [&[][..], &[0x00][..], &[0xAA, 0xBB, 0xCC][..]] {
        // payload region = u16 originalSize + compressed stream + suffix;
        // payloadLength covers the whole region, as in the Dart probe.
        let mut body = Vec::new();
        body.extend_from_slice(&(orig.len() as u16).to_be_bytes());
        body.extend_from_slice(&compressed);
        body.extend_from_slice(suffix);
        let raw = v1_packet(FLAG_IS_COMPRESSED, body.len() as u16, &[9u8; 8], &body);
        let p =
            packet::decode(&raw).unwrap_or_else(|| panic!("suffix={} must decode", suffix.len()));
        assert_eq!(p.payload, orig, "suffix={}", suffix.len());
    }
}

#[test]
fn reassembler_duplicate_index_last_write_wins() {
    // Dart: assembly.chunks[index] = data overwrites; Rust HashMap::insert
    // does the same. Pin it.
    let mut re = FragmentReassembler::new();
    let mk = |data: &[u8]| FragmentPayload {
        fragment_id: [0x42; 8],
        index: 0,
        total: 2,
        original_type: 0x02,
        data: data.to_vec(),
    };
    assert!(re.accept(&mk(&[0xAA])).is_none());
    assert!(re.accept(&mk(&[0xBB])).is_none()); // overwrites index 0
    let mut last = mk(&[0xCC]);
    last.index = 1;
    let done = re.accept(&last).expect("completes");
    assert_eq!(done, vec![0xBB, 0xCC]);
}
