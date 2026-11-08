//! `FragmentPayload` + `PacketFragmenter` + `FragmentReassembler` — ports of
//! flutter/lib/services/mesh/{protocol/fragment_payload,fragmentation}.dart.
//!
//! "UUID" note: bitchat's fragment id is 8 raw random bytes, not a UUID.
//! It is preserved byte-exactly here (keyed as `[u8; 8]`, hex form exposed).

use std::collections::HashMap;
use std::time::{Duration, Instant};

use crate::packet::{self, BitchatPacket};

pub const FRAGMENT_TYPE: u8 = 0x20;
pub const FRAGMENT_ID_SIZE: usize = 8;
pub const FRAGMENT_HEADER_SIZE: usize = 13;

/// bitchat mesh constants needed by the fragmenter.
pub const FRAGMENT_SIZE_THRESHOLD: usize = 512;
pub const MAX_FRAGMENT_SIZE: usize = 469;
pub const FRAGMENT_TIMEOUT: Duration = Duration::from_secs(30);
pub const MAX_FRAGMENTS_PER_ID: usize = 256;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FragmentPayload {
    pub fragment_id: [u8; FRAGMENT_ID_SIZE],
    pub index: u16,
    pub total: u16,
    pub original_type: u8,
    pub data: Vec<u8>,
}

impl FragmentPayload {
    /// `fragmentID:8 | index:2 BE | total:2 BE | originalType:1 | data`
    pub fn encode(&self) -> Vec<u8> {
        debug_assert!(self.index < self.total);
        let mut out = Vec::with_capacity(FRAGMENT_HEADER_SIZE + self.data.len());
        out.extend_from_slice(&self.fragment_id);
        out.extend_from_slice(&self.index.to_be_bytes());
        out.extend_from_slice(&self.total.to_be_bytes());
        out.push(self.original_type);
        out.extend_from_slice(&self.data);
        out
    }

    pub fn decode(payload: &[u8]) -> Option<FragmentPayload> {
        if payload.len() < FRAGMENT_HEADER_SIZE {
            return None;
        }
        let mut id = [0u8; FRAGMENT_ID_SIZE];
        id.copy_from_slice(&payload[..FRAGMENT_ID_SIZE]);
        let index = u16::from_be_bytes([payload[8], payload[9]]);
        let total = u16::from_be_bytes([payload[10], payload[11]]);
        Some(FragmentPayload {
            fragment_id: id,
            index,
            total,
            original_type: payload[12],
            data: payload[FRAGMENT_HEADER_SIZE..].to_vec(),
        })
    }

    /// Hex form of the 8-byte id, as used for reassembly keys and diagnostics.
    pub fn id_hex(&self) -> String {
        self.fragment_id
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect()
    }
}

/// Splits oversized packets; byte-compatible with `PacketFragmenter.fragment`.
///
/// `new_fragment_id` supplies the 8 id bytes — callers must pass CSPRNG output
/// (the Dart side uses `Random.secure()` via `randomBytes(8)`).
pub fn fragment(
    packet: &BitchatPacket,
    new_fragment_id: impl FnOnce() -> [u8; FRAGMENT_ID_SIZE],
) -> Vec<BitchatPacket> {
    if packet.type_ == FRAGMENT_TYPE {
        return vec![packet.clone()];
    }

    let Some(full_data) = packet::encode(packet, false) else {
        return Vec::new();
    };
    if full_data.len() <= FRAGMENT_SIZE_THRESHOLD {
        return vec![packet.clone()];
    }

    let has_route = packet
        .route
        .as_ref()
        .map(|r| !r.is_empty())
        .unwrap_or(false);
    let header_size = if has_route { 15 } else { 13 };
    let recipient_size = if packet.recipient_id.is_some() { 8 } else { 0 };
    let route_size = if has_route {
        1 + packet.route.as_ref().unwrap().len() * 8
    } else {
        0
    };
    let overhead = header_size + 8 + recipient_size + route_size + FRAGMENT_HEADER_SIZE + 16;
    // Dart: maxDataSize = threshold - overhead; empty when <= 0.
    let Some(mut max_data_size) = FRAGMENT_SIZE_THRESHOLD.checked_sub(overhead) else {
        return Vec::new();
    };
    if max_data_size > MAX_FRAGMENT_SIZE {
        max_data_size = MAX_FRAGMENT_SIZE;
    }
    if max_data_size == 0 {
        return Vec::new();
    }

    let fragment_id = new_fragment_id();
    let chunk_count = full_data.len().div_ceil(max_data_size);
    // bitchat caps reassembly at 256 fragments per id.
    if chunk_count > MAX_FRAGMENTS_PER_ID {
        return Vec::new();
    }

    let mut out = Vec::with_capacity(chunk_count);
    for (i, chunk) in full_data.chunks(max_data_size).enumerate() {
        let payload = FragmentPayload {
            fragment_id,
            index: i as u16,
            total: chunk_count as u16,
            original_type: packet.type_,
            data: chunk.to_vec(),
        }
        .encode();
        out.push(BitchatPacket {
            version: if has_route { 2 } else { 1 },
            type_: FRAGMENT_TYPE,
            sender_id: packet.sender_id,
            recipient_id: packet.recipient_id,
            timestamp: packet.timestamp,
            payload,
            signature: None,
            ttl: packet.ttl,
            route: packet.route.clone(),
        });
    }
    out
}

struct Assembly {
    total: u16,
    started_at: Instant,
    chunks: HashMap<u16, Vec<u8>>,
}

/// Reassembles fragments; byte-compatible with `FragmentReassembler.accept`.
/// Returns the original packet bytes once the last missing fragment arrives.
pub struct FragmentReassembler {
    assemblies: HashMap<[u8; FRAGMENT_ID_SIZE], Assembly>,
    timeout: Duration,
}

impl Default for FragmentReassembler {
    fn default() -> Self {
        Self::new()
    }
}

impl FragmentReassembler {
    pub fn new() -> Self {
        Self {
            assemblies: HashMap::new(),
            timeout: FRAGMENT_TIMEOUT,
        }
    }

    pub fn with_timeout(timeout: Duration) -> Self {
        Self {
            assemblies: HashMap::new(),
            timeout,
        }
    }

    pub fn accept(&mut self, fragment: &FragmentPayload) -> Option<Vec<u8>> {
        self.evict_expired();
        if fragment.total < 1
            || fragment.index >= fragment.total
            || fragment.total as usize > MAX_FRAGMENTS_PER_ID
        {
            return None;
        }
        let entry = self
            .assemblies
            .entry(fragment.fragment_id)
            .or_insert_with(|| Assembly {
                total: fragment.total,
                started_at: Instant::now(),
                chunks: HashMap::new(),
            });
        if entry.total != fragment.total {
            return None;
        }
        entry.chunks.insert(fragment.index, fragment.data.clone());

        if entry.chunks.len() != entry.total as usize {
            return None;
        }
        let mut out = Vec::new();
        for i in 0..entry.total {
            let chunk = entry.chunks.get(&i)?;
            out.extend_from_slice(chunk);
        }
        self.assemblies.remove(&fragment.fragment_id);
        Some(out)
    }

    fn evict_expired(&mut self) {
        let now = Instant::now();
        self.assemblies
            .retain(|_, a| now.duration_since(a.started_at) <= self.timeout);
    }

    pub fn clear(&mut self) {
        self.assemblies.clear();
    }

    pub fn pending(&self) -> usize {
        self.assemblies.len()
    }
}
