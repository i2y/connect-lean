# Contributing to connect-lean

Thank you for your interest in connect-lean. The maintainers are listed in
[MAINTAINERS.md](MAINTAINERS.md), and [docs/architecture.md](docs/architecture.md)
explains how the pieces fit and why some of them are the way they are.

## Before you contribute

If you plan to add or change a public API, please open an issue describing
the proposal before starting work. This helps ensure alignment with the
project's direction and makes the review smoother for everyone.

## Developer Certificate of Origin

All commits must be signed off to affirm compliance with the
[Developer Certificate of Origin](https://developercertificate.org/).
Configure your git identity to match your GitHub account, then use the `-s`
flag when committing:

```console
$ git commit -s -m "your commit message"
```

## Prerequisites

- [elan](https://github.com/leanprover/elan), which installs the Lean
  toolchain named in `lean-toolchain`.
- To regenerate code from `.proto` files: [`protoc`](https://github.com/protocolbuffers/protobuf/releases)
  and [`buf`](https://buf.build/docs/installation).

## Building and testing

```console
$ lake build              # the library and protoc-gen-connect-lean
$ lake test               # unit and end-to-end tests, and the code in README.md
$ lake exe tests reset    # only the tests whose names contain "reset"
```

Set `CONNECT_HTTP2_TRACE=/some/file` to log every HTTP/2 frame sent and
received.

## Conformance

The [Connect conformance suite](https://github.com/connectrpc/conformance)
runs against the server and the client, with the features
[`conformance/config.yaml`](conformance/config.yaml) claims:

```console
$ ./scripts/download-conformance.sh
$ lake build conformance-server conformance-client
$ .lake/tools/connectconformance --conf conformance/config.yaml --mode server -- .lake/build/bin/conformance-server
$ .lake/tools/connectconformance --conf conformance/config.yaml --mode client -- .lake/build/bin/conformance-client
```

A healthy run ends with `1980 passed, 0 failed` for the server and
`2647 passed, 0 failed` for the client. Changes to protocols, codecs or
transports should keep it that way.

## Generated code

Code generated from `.proto` files is checked in, under
`conformance/ConformanceGen/`, `examples/eliza/ElizaGen/` and
`tests/EdgeGen/`. After changing the generator (`ConnectGen/`) or a
`.proto` file, regenerate it:

```console
$ ./scripts/build-protoc-gen-lean4.sh     # the message generator, into .lake/tools
$ ./tests/generate.sh
$ PROTOC_GEN_LEAN4=.lake/tools/protoc-gen-lean4 ./conformance/generate.sh
$ (cd examples/eliza && buf generate)
```

CI fails when the checked-in code is out of date.

## Submitting a pull request

1. Create a branch from an up-to-date `main`.
2. Make your changes, with tests, and make sure `lake test` passes (and the
   conformance suite, for changes it covers).
3. For a change users will notice, add an entry under "Unreleased" in
   [CHANGELOG.md](CHANGELOG.md).
4. Commit with a sign-off and a clear message, push to your fork, and open a
   pull request.

Pull requests are more likely to be accepted when they include tests, keep
backward compatibility, and have clear commit messages.
