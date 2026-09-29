# Changelog

All notable changes to connect-lean are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0, a new minor version (0.1 → 0.2) may break compatibility; a new
patch version does not.

## [Unreleased]

The first release.

### Added

- Servers and clients for the Connect, gRPC and gRPC-Web protocols, with
  unary, client-streaming, server-streaming and bidirectional calls, and binary
  protobuf and ProtoJSON messages from [Lean-zh/protobuf](https://github.com/Lean-zh/protobuf).
- HTTP/1.1 (through `Std.Http` on servers) and HTTP/2 without TLS (h2c),
  written in Lean; a server serves both on one port.
- gzip in Lean, deadlines, cancellation, headers and trailers, error details,
  and message size limits.
- Interceptors on servers and clients, as in connect-py: metadata
  interceptors around every call, and message interceptors for each kind of
  call.
- `protoc-gen-connect-lean`, which generates a structure of handlers and a
  typed client for each service.
- Theorems (listed in docs/proofs.md): decoding gives back what was encoded,
  for envelopes, HTTP/2 frames, HPACK integers, Huffman codes and strings,
  base64 and percent-encoding; untrusted input cannot make the parsers use more
  than configured; and the envelope and frame readers return the same messages
  however the network splits the bytes.
- The Connect conformance suite v1.0.5 passes: all 1,980 server cases and all
  2,647 client cases in `conformance/config.yaml`.

[Unreleased]: https://github.com/i2y/connect-lean/commits/main
