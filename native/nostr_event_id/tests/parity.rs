use nostr_event_id::{canonical_bytes, event_id, event_id_from_canonical, EventParts};
use serde_json::Value;

#[test]
fn nym_vectors_match_canonical_bytes_and_ids() {
    check_vectors(include_str!("vectors.jsonl"), 38);
}

#[test]
fn nym_adversarial_vectors_match_canonical_bytes_and_ids() {
    check_vectors(include_str!("adversarial_vectors.jsonl"), 5);
}

fn check_vectors(source: &str, expected_cases: usize) {
    let mut checked = 0usize;
    for (line_index, line) in source.lines().enumerate() {
        if line.trim().is_empty() {
            continue;
        }
        let value: Value = serde_json::from_str(line).unwrap();
        let tags = value["tags"]
            .as_array()
            .unwrap()
            .iter()
            .map(|tag| {
                tag.as_array()
                    .unwrap()
                    .iter()
                    .map(|item| item.as_str().unwrap().to_string())
                    .collect::<Vec<_>>()
            })
            .collect::<Vec<_>>();
        let event = EventParts::new(
            value["pubkey"].as_str().unwrap(),
            value["created_at"].as_i64().unwrap(),
            value["kind"].as_i64().unwrap(),
            tags,
            value["content"].as_str().unwrap(),
        );

        let canonical = canonical_bytes(&event);
        assert_eq!(
            hex_lower(&canonical),
            value["canonical_hex"].as_str().unwrap(),
            "canonical mismatch on line {}",
            line_index + 1
        );
        let buffered_id = event_id_from_canonical(&canonical);
        assert_eq!(
            buffered_id,
            value["id"].as_str().unwrap(),
            "buffered id mismatch on line {}",
            line_index + 1
        );
        assert_eq!(
            event_id(&event),
            value["id"].as_str().unwrap(),
            "streaming id mismatch on line {}",
            line_index + 1
        );
        let ffi_input = serde_json::to_vec(&serde_json::json!([
            value["pubkey"],
            value["created_at"],
            value["kind"],
            value["tags"],
            value["content"]
        ]))
        .unwrap();
        let mut output = [0u8; 64];
        assert_eq!(
            unsafe {
                nostr_event_id::nostr_event_id_json(
                    ffi_input.as_ptr(),
                    ffi_input.len(),
                    output.as_mut_ptr(),
                )
            },
            1
        );
        assert_eq!(
            std::str::from_utf8(&output).unwrap(),
            value["id"].as_str().unwrap()
        );
        checked += 1;
    }
    assert_eq!(checked, expected_cases);
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
