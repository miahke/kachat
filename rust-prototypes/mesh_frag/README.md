# mesh_frag — Rust-прототип: проверка и сборка mesh-фрагментов

Прототип с экспериментальной Android FFI-интеграцией фрагментации в `flutter/lib`. Сеть, реальные ключи и устройства не
использовались; зависимостей из сети не скачивалось (`cargo --offline`,
crate `flate2 1.1.9` уже был в `~/.cargo`).

## Что внутри

- `crate/` — Rust-библиотека + бенч + тесты (единый crate `mesh_frag`):
  - `src/packet.rs` — порт `BinaryProtocol`/`BitchatPacket`
    (`flutter/lib/services/mesh/protocol/bitchat_packet.dart`): v1/v2,
    флаги recipient/signature/compressed/route, source-route, PKCS#7-padding,
    fail-closed decode (bounds pre-check, лимит 10 MiB, anti-zip-bomb
    ratio 50000, raw-deflate через `flate2`).
  - `src/padding.rs` — порт `MessagePadding`.
  - `src/fragment.rs` — порт `FragmentPayload` (заголовок 13 байт:
    `id:8 | index:2 BE | total:2 BE | originalType:1`), `PacketFragmenter`
    (порог 512, `maxFragmentSize` 469, лимит 256 фрагментов, version=2 при
    route — всё как в Dart) и `FragmentReassembler` (30 s timeout,
    отбраковка total/index, конфликт total по одному id).
  - `src/bin/bench.rs` — бенч fragment+encode и decode+reassemble.
  - `tests/vectors.rs` — golden-vectors против Dart-вывода.
  - `tests/edge.rs` — fail-closed края ревизора.
  - `tests/parity_edges.rs` — паритетные пробы верификатора: насыщение
    timestamp на i64::MAX (как `BigInt.toInt()` в Dart), trailing-байты
    после deflate-потока, last-write-wins в ревизоре.
- `dart_baseline/` — эталонный Dart-код для векторов и бенча:
  - `lib/` — **побайтовые копии** реальных файлов
    `flutter/lib/services/mesh/{fragmentation,mesh_constants}.dart` и
    `protocol/{bitchat_packet,message_padding,fragment_payload,mesh_message_type}.dart`.
  - `lib/core/crypto/keys.dart` — минимальный stub: только `randomBytes`
    (тело скопировано дословно); полный `keys.dart` тянет `package:coinlib`
    и `package:flutter`, которые не компилируются под чистым `dart run`
    (ошибки API coinlib 5.0.0 в `native_schnorr.dart` — существующая
    проблема снимка, не связана с прототипом).
  - `tool/gen_vectors.dart` — генератор `vectors.txt`.
  - `tool/bench.dart` — Dart-бенч на той же нагрузке.
- `vectors.txt` (в `dart_baseline/`) — golden vectors: полные байты
  пакетов, wire-байты всех фрагментов (включая 87-фрагментный кейс),
  padding-векторы, сжатый пакет.
- `bench_aot` — AOT-сборка `tool/bench.dart` (`dart compile exe`).

## Про «UUID»

В bitchat `fragmentID` — это **8 случайных байт**, не UUID. Прототип
сохраняет его побайтово (ключ ревизора `[u8; 8]`, hex-форма для
диагностики). Если под UUID имелась в виду другая сущность — уточнить.

## Воспроизведение

```bash
# 1. Векторы из Dart-реализации (verbatim copies)
cd rust-prototypes/mesh_frag/dart_baseline
DART=/home/dapi/Documents/Codex/2026-11-01/tor-https-github-com-permissionlesstech-bitchat/work/toolchains/flutter/bin/cache/dart-sdk/bin/dart
$DART pub get --offline
$DART run tool/gen_vectors.dart vectors.txt

# 2. Rust тесты против векторов
cd ../crate
/usr/bin/cargo test --release --offline        # 10 passed (7 + 3 verifier probes)
/usr/bin/cargo fmt -- --check
/usr/bin/cargo clippy --release --offline --all-targets -- -D warnings
/usr/bin/cargo build --release --offline       # note: `cargo` wrapper needs /var/tmp lock; /usr/bin/cargo works

# 2a. Dart baseline lint (из dart_baseline/)
$DART analyze

# 3. Бенчи (одинаковая нагрузка: 64 пакета ~3–7 КБ payload, 2000 итераций)
$DART compile exe tool/bench.dart -o ../bench_aot   # из dart_baseline/
../bench_aot 2000
../crate/target/release/bench 2000    # cargo build --release --offline
```

## Результаты (одна машина, чередующиеся прогоны, iters=2000)

Нагрузка идентична: `frag_count=1536000`, `accepted=128000` в обоих
раннерах — паритет выхода подтверждён.

| Метрика | Dart AOT (`dart compile exe`) | Rust release | Ускорение |
|---|---|---|---|
| fragment+encode | ~12–33 µs/packet | ~0.9–3.8 µs/packet | ~10–13x по парным прогонам |
| decode+reassemble | ~1.3–4.2 µs/wire | ~0.2–0.6 µs/wire | ~5–8x |

Свежие парные прогоны (после `cargo fmt`/clippy-правок, iters=2000):
Dart `fragment+encode` 11.6–19.9 µs, `decode+reassemble` 1.3–2.0 µs;
Rust `0.9–1.7 µs` и `0.2–0.3 µs` соответственно. `Random.secure()` в
Dart `fragment+encode` стоит ~2.4 µs/вызов (`bench_rng`), т.е.
~10–20% замера; Rust-бенч использует инъецированный fragment id без
RNG, поэтому codec-only разрыв ещё больше. Прогоны шумные (общая
машина), но порядок разрыва устойчив во всех измерениях.

## Совместимость

- Golden-vectors: побайтовое совпадение encode/decode/fragment/
  reassemble/signing-bytes/padding, включая v2 route, signature,
  compressed (raw deflate), 87 фрагментов, out-of-order сборку.
- Fail-closed поведение сохранено: те же отбраковки, лимиты и
  timeout-семантика; `cargo test --release --offline` — 10/10,
  `cargo clippy --release --offline --all-targets -- -D warnings` чисто.
- Формат данных и wire-протокол не менялись; Android FFI-интеграция описана ниже.

## Риски / ограничения

- Dart-база векторов — verbatim copy + stub `randomBytes`; полный
  `flutter test` не запускался (нет `.dart_tool` до `pub get`, а
  `native_schnorr.dart` не компилируется под чистым dart — отдельная
  проблема снимка). Для продакшн-интеграции нужен FFI-слой и прогон
  настоящих flutter-тестов.
- `fragment()` требует внешний источник 8 байт id (CSPRNG); в прототипе
  инъекция — осознанно, чтобы не тянуть rand-зависимость и не выдумывать
  криптографию. Внимание: Dart-бенч `fragment+encode` включает
  `Random.secure()` (~2.4 µs/вызов в свежем прогоне, ~10–20% замера) —
  при сравнении codec-only разрыв ещё больше, но абсолютные µs/packet
  у Dart включают RNG.
- `timestamp`: decode насыщается на `i64::MAX` как Dart `BigInt.toInt()`.
  Rust API принимает `u64`, поэтому вручную сконструированный
  `timestamp > i64::MAX` encode'ится как есть и не имеет аналога в Dart
  (такой `int` там не представим); для wire-совместимости использовать
  значения из decode или диапазон Dart `int`.
- Бенч — чистый CPU throughput на синтетике; реальный выигрыш в приложении
  зависит от того, какая доля времени уходит на mesh I/O (BLE pacing
  20 ms/fragment доминирует на проводе).
- `FragmentReassembler` хранит `Vec<u8>` на чанк; для предельных 256×469 B
  это ~120 KiB на сборку — как в Dart.

## release7 integration candidate

`flutter/lib/services/mesh/native_fragment.dart` optionally uses a narrow FFI
function for payload splitting on Android. Packet serialization, random 8-byte
fragment IDs (`Random.secure`), reassembly and the Nym path remain Dart. If the
library or symbol is unavailable or allocation/call fails, Dart constructs the
same payloads. This does not integrate the Rust packet decoder or reassembler.

Build the three Android libraries before packaging (NDK 28, API 29, Rust Android
targets required):

```sh
ANDROID_NDK_HOME=/path/to/android-ndk ./rust-prototypes/mesh_frag/build_android.sh
cd flutter && flutter build apk --debug
```

The three libraries are included under `flutter/android/app/src/main/jniLibs`
and the script rebuilds them in place; if absent the app still builds and uses Dart. An APK/device test is required
before release. Run Rust tests with `cargo test --release --offline` in `crate`;
the FFI parity test can be exercised on a host with `cargo build --release --lib`
and `MESH_FRAG_TEST_LIBRARY=/absolute/path/to/libmesh_frag.so flutter test
--no-pub test/mesh/native_fragment_test.dart` from `flutter`.

A local x86-64 Dart AOT microbenchmark of the integrated chunk-only boundary
(5 KB, 12 fragments, 50,000 iterations; `flutter/tool/bench_native.dart`) gave
0.91 µs Dart versus 1.11 µs FFI per packet in one run. It excludes BLE pacing,
packet serialization, device effects, and RNG. The original full-codec Rust
benchmark is not representative of this partial integration. Do not assume a
performance gain on Android; measure on device before enabling for release.
