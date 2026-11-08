//! Narrow caller-owned-buffer interface for Dart's mesh fragment payloads.
use crate::fragment::{FRAGMENT_HEADER_SIZE, MAX_FRAGMENTS_PER_ID};

pub fn fragment_payloads(
    input: &[u8],
    id: &[u8; 8],
    size: usize,
    original_type: u8,
    output: &mut [u8],
) -> Option<usize> {
    if input.is_empty() || size == 0 {
        return None;
    }
    let count = input.len().div_ceil(size);
    if count > MAX_FRAGMENTS_PER_ID {
        return None;
    }
    let required = input
        .len()
        .checked_add(count.checked_mul(FRAGMENT_HEADER_SIZE)?)?;
    if output.len() < required {
        return None;
    }
    let mut offset = 0;
    for (index, chunk) in input.chunks(size).enumerate() {
        output[offset..offset + 8].copy_from_slice(id);
        output[offset + 8..offset + 10].copy_from_slice(&(index as u16).to_be_bytes());
        output[offset + 10..offset + 12].copy_from_slice(&(count as u16).to_be_bytes());
        output[offset + 12] = original_type;
        output[offset + 13..offset + 13 + chunk.len()].copy_from_slice(chunk);
        offset += 13 + chunk.len();
    }
    Some(required)
}

/// # Safety
/// Pointers must be valid for their specified lengths, non-overlapping, and
/// the ID pointer must reference eight readable bytes.
#[no_mangle]
pub unsafe extern "C" fn mesh_fragment_payloads(
    input: *const u8,
    input_len: usize,
    id: *const u8,
    size: usize,
    original_type: u8,
    output: *mut u8,
    output_len: usize,
) -> isize {
    if input.is_null()
        || id.is_null()
        || output.is_null()
        || input_len > isize::MAX as usize
        || output_len > isize::MAX as usize
    {
        return -1;
    }
    let input = unsafe { std::slice::from_raw_parts(input, input_len) };
    let id = unsafe { &*(id as *const [u8; 8]) };
    let output = unsafe { std::slice::from_raw_parts_mut(output, output_len) };
    fragment_payloads(input, id, size, original_type, output).map_or(-1, |n| n as isize)
}
