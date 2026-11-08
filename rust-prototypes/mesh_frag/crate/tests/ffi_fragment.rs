use mesh_frag::ffi::fragment_payloads;

#[test]
fn ffi_payloads_match_fragment_headers_and_reject_small_buffers() {
    let input = [1u8, 2, 3, 4, 5];
    let id = [9u8; 8];
    let mut output = [0u8; 44];
    assert_eq!(fragment_payloads(&input, &id, 2, 7, &mut output), Some(44));
    assert_eq!(&output[..13], &[9, 9, 9, 9, 9, 9, 9, 9, 0, 0, 0, 3, 7]);
    assert_eq!(&output[13..15], &[1, 2]);
    assert_eq!(&output[15..28], &[9, 9, 9, 9, 9, 9, 9, 9, 0, 1, 0, 3, 7]);
    assert_eq!(&output[28..30], &[3, 4]);
    assert_eq!(&output[30..43], &[9, 9, 9, 9, 9, 9, 9, 9, 0, 2, 0, 3, 7]);
    assert_eq!(output[43], 5);
    assert_eq!(
        fragment_payloads(&input, &id, 2, 7, &mut output[..43]),
        None
    );
    assert_eq!(fragment_payloads(&input, &id, 0, 7, &mut output), None);
}
