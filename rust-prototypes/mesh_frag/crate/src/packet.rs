//! Binary codec for `BitchatPacket` v1/v2 — port of `BinaryProtocol` in
//! flutter/lib/services/mesh/protocol/bitchat_packet.dart.
//! Wire format and fail-closed checks are identical.

use std::io::Read;

use flate2::read::DeflateDecoder;

use crate::padding;

pub const HEADER_SIZE_V1: usize = 14;
pub const HEADER_SIZE_V2: usize = 16;
pub const SENDER_ID_SIZE: usize = 8;
pub const RECIPIENT_ID_SIZE: usize = 8;
pub const SIGNATURE_SIZE: usize = 64;

/// bitchat's `MAX_PAYLOAD_LENGTH` (10 MiB).
pub const MAX_PAYLOAD_LENGTH: usize = 10 * 1024 * 1024;

pub const FLAG_HAS_RECIPIENT: u8 = 0x01;
pub const FLAG_HAS_SIGNATURE: u8 = 0x02;
pub const FLAG_IS_COMPRESSED: u8 = 0x04;
pub const FLAG_HAS_ROUTE: u8 = 0x08;

#[derive(Clone, Debug)]
pub struct BitchatPacket {
    pub version: u8,
    pub type_: u8,
    pub sender_id: [u8; SENDER_ID_SIZE],
    pub recipient_id: Option<[u8; RECIPIENT_ID_SIZE]>,
    /// u64 milliseconds, big-endian on the wire.
    pub timestamp: u64,
    pub payload: Vec<u8>,
    pub signature: Option<[u8; SIGNATURE_SIZE]>,
    pub ttl: u8,
    /// v2 source route, 8 bytes per hop.
    pub route: Option<Vec<[u8; SENDER_ID_SIZE]>>,
}

fn header_size(version: u8) -> usize {
    if version == 1 {
        HEADER_SIZE_V1
    } else {
        HEADER_SIZE_V2
    }
}

impl BitchatPacket {
    /// Signing bytes: no signature, TTL 0, padded — port of `toBytesForSigning`.
    pub fn to_bytes_for_signing(&self) -> Option<Vec<u8>> {
        let mut p = self.clone();
        p.signature = None;
        p.ttl = 0;
        encode(&p, true)
    }
}

fn bytes_fixed<const N: usize>(src: &[u8]) -> [u8; N] {
    let mut out = [0u8; N];
    let n = src.len().min(N);
    out[..n].copy_from_slice(&src[..n]);
    out
}

/// Never compresses on send; returns `None` if the payload exceeds the length field.
pub fn encode(packet: &BitchatPacket, padding_enabled: bool) -> Option<Vec<u8>> {
    let payload = &packet.payload;
    if payload.len() > MAX_PAYLOAD_LENGTH {
        return None;
    }

    let version = packet.version;
    let header = header_size(version);
    let has_recipient = packet.recipient_id.is_some();
    let has_signature = packet.signature.is_some();
    let has_route = version >= 2
        && packet
            .route
            .as_ref()
            .map(|r| !r.is_empty())
            .unwrap_or(false);

    let route_bytes = if has_route {
        1 + packet.route.as_ref().unwrap().len().min(255) * SENDER_ID_SIZE
    } else {
        0
    };
    let capacity = header
        + SENDER_ID_SIZE
        + if has_recipient { RECIPIENT_ID_SIZE } else { 0 }
        + route_bytes
        + payload.len()
        + if has_signature { SIGNATURE_SIZE } else { 0 }
        + 16;

    let mut buf = Vec::with_capacity(capacity.max(512));

    buf.push(version);
    buf.push(packet.type_);
    buf.push(packet.ttl);
    buf.extend_from_slice(&packet.timestamp.to_be_bytes());

    let mut flags = 0u8;
    if has_recipient {
        flags |= FLAG_HAS_RECIPIENT;
    }
    if has_signature {
        flags |= FLAG_HAS_SIGNATURE;
    }
    if has_route {
        flags |= FLAG_HAS_ROUTE;
    }
    buf.push(flags);

    if version >= 2 {
        buf.extend_from_slice(&(payload.len() as u32).to_be_bytes());
    } else {
        if payload.len() > 0xFFFF {
            return None;
        }
        buf.extend_from_slice(&(payload.len() as u16).to_be_bytes());
    }

    buf.extend_from_slice(&packet.sender_id);

    if let Some(r) = packet.recipient_id {
        buf.extend_from_slice(&r);
    }

    if has_route {
        let route = packet.route.as_ref().unwrap();
        let count = route.len().min(255);
        buf.push(count as u8);
        for hop in route.iter().take(count) {
            buf.extend_from_slice(hop);
        }
    }

    buf.extend_from_slice(payload);

    if let Some(sig) = packet.signature {
        buf.extend_from_slice(&sig);
    }

    if padding_enabled {
        Some(padding::pad(&buf, padding::optimal_block_size(buf.len())))
    } else {
        Some(buf)
    }
}

/// Tries the raw bytes, then again after stripping padding, as bitchat does.
pub fn decode(data: &[u8]) -> Option<BitchatPacket> {
    if let Some(p) = decode_core(data) {
        return Some(p);
    }
    let unpadded = padding::unpad(data);
    if unpadded.len() == data.len() {
        return None;
    }
    decode_core(&unpadded)
}

struct Reader<'a> {
    buf: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn u8(&mut self) -> Option<u8> {
        let v = *self.buf.get(self.offset)?;
        self.offset += 1;
        Some(v)
    }
    fn u16(&mut self) -> Option<u16> {
        let b = self.buf.get(self.offset..self.offset + 2)?;
        self.offset += 2;
        Some(u16::from_be_bytes([b[0], b[1]]))
    }
    fn u32(&mut self) -> Option<u32> {
        let b = self.buf.get(self.offset..self.offset + 4)?;
        self.offset += 4;
        Some(u32::from_be_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn u64(&mut self) -> Option<u64> {
        let b = self.buf.get(self.offset..self.offset + 8)?;
        self.offset += 8;
        Some(u64::from_be_bytes(b.try_into().unwrap()))
    }
    fn take(&mut self, n: usize) -> Option<&'a [u8]> {
        let s = self.buf.get(self.offset..self.offset + n)?;
        self.offset += n;
        Some(s)
    }
}

fn decode_core(raw: &[u8]) -> Option<BitchatPacket> {
    if raw.len() < HEADER_SIZE_V1 + SENDER_ID_SIZE {
        return None;
    }
    let mut r = Reader {
        buf: raw,
        offset: 0,
    };

    let version = r.u8()?;
    if version != 1 && version != 2 {
        return None;
    }

    let type_ = r.u8()?;
    let ttl = r.u8()?;
    // Dart reads u64 via BigInt.toInt(), which saturates at i64::MAX; match it.
    let timestamp = r.u64()?.min(i64::MAX as u64);
    let flags = r.u8()?;
    let has_recipient = flags & FLAG_HAS_RECIPIENT != 0;
    let has_signature = flags & FLAG_HAS_SIGNATURE != 0;
    let is_compressed = flags & FLAG_IS_COMPRESSED != 0;
    let has_route = version >= 2 && flags & FLAG_HAS_ROUTE != 0;

    let payload_length = if version >= 2 {
        r.u32()? as usize
    } else {
        r.u16()? as usize
    };
    if payload_length > MAX_PAYLOAD_LENGTH {
        return None;
    }

    // Bounds pre-check before consuming any section, as bitchat does.
    let mut expected = header_size(version) + SENDER_ID_SIZE + payload_length;
    if has_recipient {
        expected += RECIPIENT_ID_SIZE;
    }
    let mut route_count = 0usize;
    if has_route {
        let route_offset =
            r.offset + SENDER_ID_SIZE + if has_recipient { RECIPIENT_ID_SIZE } else { 0 };
        if raw.len() > route_offset {
            route_count = raw[route_offset] as usize;
        }
        expected += 1 + route_count * SENDER_ID_SIZE;
    }
    if has_signature {
        expected += SIGNATURE_SIZE;
    }
    if raw.len() < expected {
        return None;
    }

    let sender_id = bytes_fixed::<SENDER_ID_SIZE>(r.take(SENDER_ID_SIZE)?);
    let recipient_id = if has_recipient {
        Some(bytes_fixed::<RECIPIENT_ID_SIZE>(r.take(RECIPIENT_ID_SIZE)?))
    } else {
        None
    };

    let route = if has_route {
        let count = r.u8()? as usize;
        if count > 0 {
            let mut v = Vec::with_capacity(count);
            for _ in 0..count {
                v.push(bytes_fixed::<SENDER_ID_SIZE>(r.take(SENDER_ID_SIZE)?));
            }
            Some(v)
        } else {
            None
        }
    } else {
        None
    };

    let payload = if is_compressed {
        let len_field_bytes = if version >= 2 { 4 } else { 2 };
        if payload_length < len_field_bytes {
            return None;
        }
        let original_size = if version >= 2 {
            r.u32()? as usize
        } else {
            r.u16()? as usize
        };
        if original_size == 0 || original_size > MAX_PAYLOAD_LENGTH {
            return None;
        }
        let compressed_size = payload_length - len_field_bytes;
        if compressed_size == 0 {
            return None;
        }
        // Decompression-bomb guard, identical ratio to bitchat.
        if original_size as f64 / compressed_size as f64 > 50000.0 {
            return None;
        }
        let compressed = r.take(compressed_size)?;
        let mut decoder = DeflateDecoder::new(compressed);
        let mut expanded = Vec::with_capacity(original_size);
        decoder.read_to_end(&mut expanded).ok()?;
        if expanded.len() != original_size {
            return None;
        }
        expanded
    } else {
        r.take(payload_length)?.to_vec()
    };

    let signature = if has_signature {
        let s = r.take(SIGNATURE_SIZE)?;
        let mut sig = [0u8; SIGNATURE_SIZE];
        sig.copy_from_slice(s);
        Some(sig)
    } else {
        None
    };

    Some(BitchatPacket {
        version,
        type_,
        sender_id,
        recipient_id,
        timestamp,
        payload,
        signature,
        ttl,
        route,
    })
}

pub fn packet_version_for_payload(length: usize) -> u8 {
    if length > 0xFFFF {
        2
    } else {
        1
    }
}
