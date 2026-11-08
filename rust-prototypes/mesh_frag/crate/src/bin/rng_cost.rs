use std::fs::File;
use std::hint::black_box;
use std::io::Read;
use std::time::Instant;

fn main() {
    let iters: usize = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(128_000);
    let mut f = File::open("/dev/urandom").unwrap();
    let mut id = [0u8; 8];
    let t = Instant::now();
    for _ in 0..iters {
        f.read_exact(&mut id).unwrap();
        black_box(id);
    }
    let us = t.elapsed().as_secs_f64() * 1e6 / iters as f64;
    println!("iters={iters} urandom_read8: {us:.2} us/call");
}
