//! Edge-case tests for fragment validation (fail-closed paths).

use mesh_frag::fragment::{FragmentPayload, FragmentReassembler};

fn fp(id: u8, index: u16, total: u16) -> FragmentPayload {
    FragmentPayload {
        fragment_id: [id; 8],
        index,
        total,
        original_type: 0x02,
        data: vec![1, 2, 3],
    }
}

#[test]
fn rejects_invalid_fragments() {
    let mut re = FragmentReassembler::new();
    assert!(re.accept(&fp(1, 0, 0)).is_none()); // total 0
    assert!(re.accept(&fp(1, 5, 3)).is_none()); // index >= total
    assert!(re.accept(&fp(1, 0, 257)).is_none()); // total > 256
    assert_eq!(re.pending(), 0);
}

#[test]
fn rejects_mixed_totals_same_id() {
    let mut re = FragmentReassembler::new();
    let mut a = fp(7, 0, 2);
    a.data = vec![9];
    assert!(re.accept(&a).is_none());
    // Same fragment id, different total -> rejected, assembly keeps first total.
    assert!(re.accept(&fp(7, 0, 3)).is_none());
    assert_eq!(re.pending(), 1);
}

#[test]
fn out_of_order_completion() {
    let mut re = FragmentReassembler::new();
    let mut p0 = fp(9, 0, 3);
    p0.data = vec![0xAA];
    let mut p1 = fp(9, 1, 3);
    p1.data = vec![0xBB, 0xBB];
    let mut p2 = fp(9, 2, 3);
    p2.data = vec![0xCC];
    assert!(re.accept(&p2).is_none());
    assert!(re.accept(&p0).is_none());
    let done = re.accept(&p1).expect("last fragment completes");
    assert_eq!(done, vec![0xAA, 0xBB, 0xBB, 0xCC]);
    assert_eq!(re.pending(), 0);
}

#[test]
fn timeout_expires_assemblies() {
    let mut re = FragmentReassembler::with_timeout(std::time::Duration::from_millis(1));
    assert!(re.accept(&fp(3, 0, 2)).is_none());
    std::thread::sleep(std::time::Duration::from_millis(5));
    // Next accept evicts the stale assembly; a fresh partial stays pending.
    assert!(re.accept(&fp(4, 0, 2)).is_none());
    assert_eq!(re.pending(), 1);
}
