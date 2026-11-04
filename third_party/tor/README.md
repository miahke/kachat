# Bundled Tor components

Modified 2026-11-04 for Качат: Arti JNI 1.9.0 and lyrebird with obfs4,
WebTunnel and Snowflake. Arti source tag/commit and locked Rust dependencies
are in tools/arti-build; local PT source and locked Go dependencies are in
native/pt. The Snowflake adapter comes from upstream lyrebird commit
362a60bb4e3fa434130ef81a9990d83d6d8eaea5; Snowflake client v2.14.1
implements broker rendezvous, ICE/WebRTC and TurboTunnel.

The native SOCKS listener binds only 127.0.0.1, requires fresh random username
and password authentication and reports real Arti bootstrap progress.
Readiness requires Arti ready_for_traffic. Bridge settings never enter app
status or errors. The app exports the Android trust manager's issuers for
WebTunnel and Snowflake TLS; PT file logging is disabled by default.

The bundled Snowflake bridge comes from the Tor project's public configuration,
verified 2026-11-04 at:
https://support.torproject.org/little-t-tor/circumvention/using-bridges/
and https://pkg.go.dev/gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/v2/client
It is public configuration and can be replaced by a user-supplied Snowflake
bridge. Availability depends on the user's network and bridge service.

Rebuild Arti with tools/arti-build/build-arti.sh using the pinned toolchain;
build the PT executables with tools/build-tor-pt.sh and NDK r27d.
Redistribution notices are retained in this directory. SHA256SUMS covers all
six Android native release inputs.
