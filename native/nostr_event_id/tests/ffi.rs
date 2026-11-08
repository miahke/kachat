use nostr_event_id::nostr_event_id_json;

#[test]
fn ffi_returns_id_for_event_and_rejects_invalid_data() {
    let input = br#"["ab",1,1,[["t","test"]],"hello"]"#;
    let mut output = [0u8; 64];
    assert_eq!(
        unsafe { nostr_event_id_json(input.as_ptr(), input.len(), output.as_mut_ptr()) },
        1
    );
    let event =
        nostr_event_id::EventParts::new("ab", 1, 1, vec![vec!["t".into(), "test".into()]], "hello");
    assert_eq!(
        std::str::from_utf8(&output).unwrap(),
        nostr_event_id::event_id(&event)
    );
    let bad = b"not json";
    assert_eq!(
        unsafe { nostr_event_id_json(bad.as_ptr(), bad.len(), output.as_mut_ptr()) },
        0
    );
}
