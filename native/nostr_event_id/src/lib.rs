use sha2::{Digest, Sha256};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EventParts {
    pub pubkey: String,
    pub created_at: i64,
    pub kind: i64,
    pub tags: Vec<Vec<String>>,
    pub content: String,
}

impl EventParts {
    pub fn new(
        pubkey: impl Into<String>,
        created_at: i64,
        kind: i64,
        tags: Vec<Vec<String>>,
        content: impl Into<String>,
    ) -> Self {
        Self {
            pubkey: pubkey.into(),
            created_at,
            kind,
            tags,
            content: content.into(),
        }
    }
}

pub fn canonical_bytes(event: &EventParts) -> Vec<u8> {
    let mut out =
        Vec::with_capacity(event.pubkey.len() + event.content.len() + event.tags.len() * 16 + 32);
    write_canonical_event(event, &mut |bytes| out.extend_from_slice(bytes));
    out
}

pub fn write_canonical_event<F>(event: &EventParts, out: &mut F)
where
    F: FnMut(&[u8]),
{
    out(b"[0,");
    write_json_string(&event.pubkey, out);
    out(b",");
    write_i64(event.created_at, out);
    out(b",");
    write_i64(event.kind, out);
    out(b",[");
    for (tag_index, tag) in event.tags.iter().enumerate() {
        if tag_index != 0 {
            out(b",");
        }
        out(b"[");
        for (value_index, value) in tag.iter().enumerate() {
            if value_index != 0 {
                out(b",");
            }
            write_json_string(value, out);
        }
        out(b"]");
    }
    out(b"],");
    write_json_string(&event.content, out);
    out(b"]");
}

pub fn event_id(event: &EventParts) -> String {
    let mut hasher = Sha256::new();
    write_canonical_event(event, &mut |bytes| hasher.update(bytes));
    hex_lower(hasher.finalize().as_ref())
}

pub fn event_id_from_canonical(canonical: &[u8]) -> String {
    hex_lower(Sha256::digest(canonical).as_ref())
}

fn write_json_string<F>(value: &str, out: &mut F)
where
    F: FnMut(&[u8]),
{
    const HEX: &[u8; 16] = b"0123456789abcdef";

    out(b"\"");
    let bytes = value.as_bytes();
    let mut start = 0;
    for (index, ch) in value.char_indices() {
        match ch {
            '"' => {
                out(&bytes[start..index]);
                out(b"\\\"");
                start = index + 1;
            }
            '\\' => {
                out(&bytes[start..index]);
                out(b"\\\\");
                start = index + 1;
            }
            '\u{08}' => {
                out(&bytes[start..index]);
                out(b"\\b");
                start = index + 1;
            }
            '\u{09}' => {
                out(&bytes[start..index]);
                out(b"\\t");
                start = index + 1;
            }
            '\u{0a}' => {
                out(&bytes[start..index]);
                out(b"\\n");
                start = index + 1;
            }
            '\u{0c}' => {
                out(&bytes[start..index]);
                out(b"\\f");
                start = index + 1;
            }
            '\u{0d}' => {
                out(&bytes[start..index]);
                out(b"\\r");
                start = index + 1;
            }
            c if (c as u32) < 0x20 => {
                let code = c as u32;
                out(&bytes[start..index]);
                out(b"\\u00");
                out(&[HEX[(code >> 4) as usize & 0x0f], HEX[code as usize & 0x0f]]);
                start = index + c.len_utf8();
            }
            _ => {}
        }
    }
    out(&bytes[start..]);
    out(b"\"");
}

fn write_i64<F>(value: i64, out: &mut F)
where
    F: FnMut(&[u8]),
{
    let mut buffer = [0u8; 20];
    let mut cursor = buffer.len();
    let mut remaining = value.unsigned_abs();
    loop {
        cursor -= 1;
        buffer[cursor] = b'0' + (remaining % 10) as u8;
        remaining /= 10;
        if remaining == 0 {
            break;
        }
    }
    if value < 0 {
        out(b"-");
    }
    out(&buffer[cursor..]);
}

fn hex_lower(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push(HEX[(byte >> 4) as usize] as char);
        out.push(HEX[(byte & 0x0f) as usize] as char);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_shape_matches_nip01() {
        let event = EventParts::new(
            "ab".repeat(32),
            1_700_000_000,
            1,
            vec![vec!["t".into(), "test".into()]],
            "hello",
        );
        assert_eq!(
            String::from_utf8(canonical_bytes(&event)).unwrap(),
            format!(
                "[0,\"{}\",1700000000,1,[[\"t\",\"test\"]],\"hello\"]",
                "ab".repeat(32)
            )
        );
    }

    #[test]
    fn streaming_and_buffered_ids_match() {
        let event = EventParts::new(
            "cd".repeat(32),
            -1,
            -30023,
            vec![vec![], vec!["a\"b".into(), "c\\d".into(), "é\n".into()]],
            "content \u{1f30d}",
        );
        assert_eq!(
            event_id(&event),
            event_id_from_canonical(&canonical_bytes(&event))
        );
    }
}

/// Returns 1 on success, 0 on invalid input. Output must hold 64 bytes.
/// The caller owns both buffers, which must remain valid for this call.
#[no_mangle]
pub unsafe extern "C" fn nostr_event_id_json(input: *const u8, len: usize, output: *mut u8) -> i32 {
    if input.is_null() || output.is_null() || len > isize::MAX as usize {
        return 0;
    }
    std::panic::catch_unwind(|| {
        let bytes = std::slice::from_raw_parts(input, len);
        let value: serde_json::Value = match serde_json::from_slice(bytes) {
            Ok(v) => v,
            Err(_) => return 0,
        };
        let Some(parts) = value.as_array().filter(|v| v.len() == 5) else {
            return 0;
        };
        let (Some(pubkey), Some(created_at), Some(kind), Some(tags), Some(content)) = (
            parts[0].as_str(),
            parts[1].as_i64(),
            parts[2].as_i64(),
            parts[3].as_array(),
            parts[4].as_str(),
        ) else {
            return 0;
        };
        let tags: Option<Vec<Vec<String>>> = tags
            .iter()
            .map(|tag| {
                tag.as_array()?
                    .iter()
                    .map(|item| item.as_str().map(str::to_owned))
                    .collect()
            })
            .collect();
        let Some(tags) = tags else { return 0 };
        let id = event_id(&EventParts::new(pubkey, created_at, kind, tags, content));
        std::ptr::copy_nonoverlapping(id.as_ptr(), output, 64);
        1
    })
    .unwrap_or(0)
}
