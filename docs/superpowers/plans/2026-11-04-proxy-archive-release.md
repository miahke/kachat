# Proxy, qWDTT profiles, archive and optional payments

User-authorized release changes (2026-11-04).

1. qWDTT: one imported subscription retains all hashes; selectable bounded workers using original core; existing split profiles remain intact rather than destructive guessing. Preserve export roundtrip and tests.
2. Tor: accept actual supported native bridge formats, copied official lines and validate before start. Do not claim unimplemented transports work.
3. Generic proxies: HTTP CONNECT, TLS-protected HTTPS CONNECT and SOCKS5, credentials stored with existing Android secret store. Import standard URIs, plain host/port/auth and Telegram SOCKS links; diagnose MTProto/other unsupported protocols explicitly. Route persistence and no direct fallback stay in force. Test remote domain forwarding, auth, protocol errors and cancellation.
4. Archive: per-account local chat/channel archive, restore and hide/show archive controls, persistent metadata without leaving/deleting messages. Test filtering and state changes.
5. Payments/store: restore actual original functions behind an explicit safety notice at the bottom of About/information. No test payments. Preserve original attribution and unrelated performance/routing fixes.
6. Integrate, run Flutter analyze/tests and JVM/native checks, bump release version. Build all three ABIs from neutral source path; verify update certificate, core hashes, alignment and private-pattern scan. Publish public release assets/source and verify remote asset digests.

Independent tasks: qWDTT/Tor parser, archive and payments are delegated under dispatching-parallel-agents; root owns generic proxy/route integration and release. Existing test native binaries need rebuilding only if Go/Rust inputs change. Physical/live provider checks must not be represented as completed without evidence.

Implementation verified: Flutter analyze clean, 63 Flutter tests passed (1 optional skip), 57 JVM tests passed, native Go tests passed. Final release packaging and remote digest verification follow source commit.
