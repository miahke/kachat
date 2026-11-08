//! PKCS#7-style padding to fixed block sizes, port of `MessagePadding`.

pub const BLOCK_SIZES: [usize; 4] = [256, 512, 1024, 2048];

/// Smallest block fitting `data_size` plus a 16-byte tag; oversized frames keep their size.
pub fn optimal_block_size(data_size: usize) -> usize {
    let total = data_size + 16;
    for &b in &BLOCK_SIZES {
        if total <= b {
            return b;
        }
    }
    data_size
}

/// Strict PKCS#7 pad; unchanged if over 255 bytes of padding are needed.
pub fn pad(data: &[u8], target_size: usize) -> Vec<u8> {
    if data.len() >= target_size {
        return data.to_vec();
    }
    let needed = target_size - data.len();
    if needed == 0 || needed > 255 {
        return data.to_vec();
    }
    let mut out = vec![needed as u8; target_size];
    out[..data.len()].copy_from_slice(data);
    out
}

/// Removes PKCS#7 padding, returning the input unchanged when the trailing run is invalid.
pub fn unpad(data: &[u8]) -> Vec<u8> {
    if data.is_empty() {
        return data.to_vec();
    }
    let plen = data[data.len() - 1] as usize;
    if plen == 0 || plen > data.len() {
        return data.to_vec();
    }
    let start = data.len() - plen;
    if data[start..].iter().any(|&b| b as usize != plen) {
        return data.to_vec();
    }
    data[..start].to_vec()
}
