# connect-lean

[![CI](https://github.com/i2y/connect-lean/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/i2y/connect-lean/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

[Connect](https://connectrpc.com) for Lean 4: serve and call APIs defined in
Protocol Buffers, over the Connect protocol, gRPC and gRPC-Web, with binary or
JSON messages. connect-lean is a community implementation, outside the
[connectrpc](https://github.com/connectrpc) organization.

> **Status: 0.1, experimental.** The runtime passes the official
> [Connect conformance suite](https://github.com/connectrpc/conformance) for
> everything it claims: all 1,980 server cases and all 2,647 client cases, for
> the Connect, gRPC and gRPC-Web protocols over HTTP/1.1 and HTTP/2 without TLS
> (see [Limitations](#limitations)). The API may still change between 0.x
> releases.

## Features

- **Servers and clients** for the Connect protocol (including cacheable `GET`
  requests), gRPC and gRPC-Web, with unary, client-streaming, server-streaming
  and bidirectional calls.
- **HTTP/1.1 and HTTP/2**, both on one server port. HTTP/2 is written in Lean
  on `Std.Async`, with full-duplex streams; HTTP/1.1 comes from Lean's
  `Std.Http`. No native dependencies.
- **Binary protobuf and ProtoJSON** messages, from
  [Lean-zh/protobuf](https://github.com/Lean-zh/protobuf).
- **Interceptors** as in connect-py, gzip (written in Lean), deadlines,
  cancellation, headers and trailers, typed error details and message size
  limits.
- **Code generation:** `protoc-gen-connect-lean` turns each service into a
  structure of handlers and a typed client.
- **Proofs** that the codecs decode what they encode and that untrusted input
  cannot make the parsers use more than configured (see [Proofs](#proofs)).

## Quick start

1. Add connect-lean to your `lakefile.lean`, with a library for the generated
   code and an executable, and run `lake update connectrpc`:

   ```lean
   require connectrpc from git "https://github.com/i2y/connect-lean" @ "v0.1.0"

   lean_lib Gen

   lean_exe greet where
     root := `Main
   ```

   Use the Lean version in connect-lean's [`lean-toolchain`](lean-toolchain)
   (`leanprover/lean4:v4.34.1`) for your project too.

2. Describe the service in `proto/greet/v1/greet.proto`:

   ```proto
   syntax = "proto3";

   package greet.v1;

   message GreetRequest {
     string name = 1;
   }

   message GreetResponse {
     string greeting = 1;
   }

   service GreetService {
     rpc Greet(GreetRequest) returns (GreetResponse) {}
   }
   ```

3. Generate the code. Messages come from `protoc-gen-lean4` of Lean-zh/protobuf,
   and services from connect-lean's `protoc-gen-connect-lean`: build both
   plugins once, then run `protoc` with the two of them and the same
   `lean4_prefix`, the module prefix of the output directory.

   ```bash
   lake build protoc-gen-connect-lean
   .lake/packages/connectrpc/scripts/build-protoc-gen-lean4.sh
   mkdir -p Gen
   protoc -I proto \
     --plugin=protoc-gen-lean4=.lake/packages/connectrpc/.lake/tools/protoc-gen-lean4 \
     --lean4_out=Gen --lean4_opt=lean4_prefix=Gen \
     --plugin=protoc-gen-connect-lean=.lake/packages/connectrpc/.lake/build/bin/protoc-gen-connect-lean \
     --connect-lean_out=Gen --connect-lean_opt=lean4_prefix=Gen \
     greet/v1/greet.proto
   ```

   This writes `Gen/greet/v1/greet.lean` (the messages) and
   `Gen/greet/v1/greet_connect.lean` (the service). `buf generate` works too,
   with the same two plugins in a `buf.gen.yaml` like
   [the example's](examples/eliza/buf.gen.yaml).

4. Implement the service in `Main.lean`:

   ```lean
   import Connect
   import Gen.greet.v1.greet_connect

   open greet.v1

   def greeter : GreetService where
     greet _ req := return { greeting := s!"Hello, {req.name}!" }

   def main : IO Unit :=
     Connect.serve (Connect.Router.empty.register greeter) (cfg := { port := 8080 })
   ```

5. Run it with `lake exe greet`, and call it:

   ```console
   $ curl -X POST localhost:8080/greet.v1.GreetService/Greet \
       -H 'content-type: application/json' -d '{"name": "Lean"}'
   {"greeting":"Hello, Lean!"}
   ```

[examples/eliza](examples/eliza) is a complete project, with streaming calls, a
client and `buf generate`.

## Generated code

For a service `GreetService` in package `greet.v1`, `greet_connect.lean`
declares:

| Name | What it is |
|---|---|
| `greet.v1.GreetService` | a structure with one handler field per method |
| `greet.v1.GreetService.Spec.greet` | the method's `Connect.MethodSpec` |
| `Connect.ToService GreetService` | lets a router serve an implementation |
| `greet.v1.GreetService.Client` | a client with one function per method |

`protoc-gen-lean4` only writes the files it is asked for: if your protos use
well-known types, list those too (for example `google/protobuf/empty.proto`,
from `protoc`'s include directory). Its notation makes `message`, `enum`,
`oneof` and `extend` keywords in files that import generated messages: write
`«message» := …` for such a structure field there, or use functions such as
`ConnectError.new`.

## Servers

The examples from here on use the Eliza service of
[examples/eliza](examples/eliza), which has a unary, a server-streaming and a
bidirectional method. Implement a service by filling in its structure; methods
you leave out answer `unimplemented`:

```lean
import Connect
import Gen.connectrpc.eliza.v1.eliza_connect

open Connect connectrpc.eliza.v1

def eliza : ElizaService where
  -- unary: one request, one response
  say ctx req := do
    ctx.setResponseHeader "x-served-by" "lean"
    if req.sentence.isEmpty then
      throw (.invalidArgument "say something")
    return { sentence := s!"You said: {req.sentence}" }

  -- server streaming: send as many responses as you like
  introduce _ req stream := do
    for line in ["Hello, " ++ req.name, "I'm Eliza."] do
      stream.send { sentence := line }

  -- bidirectional: read requests as they come, answer each
  converse _ requests responses := do
    for req in requests do
      responses.send { sentence := s!"Why do you say {req.sentence}?" }

def main : IO Unit :=
  Connect.serve (Router.empty.register eliza) (cfg := { port := 8080 })
```

Handlers run in `Connect.RpcM`, asynchronous IO (`Std.Async`) that can fail
with a `Connect.ConnectError`. `IO` actions lift into it; an `IO.Error` that
escapes a handler reaches the client as `unknown`.

The `Context` a handler receives describes the call: the method, protocol,
request headers, the client's timeout, and a cancellation context that fires
when the client goes away or the deadline passes. Use it to set response
headers and trailers, and `ctx.checkCancelled` in long-running handlers.

One port serves HTTP/1.1 and HTTP/2 without TLS (h2c with prior knowledge, as
gRPC clients use it). `Server.start` runs a server in the background and
returns its port, which is useful with port `0` in tests. To serve Connect next
to other routes in your own `Std.Http` server (HTTP/1.1 only), use
`Router.httpHandler`.

### Options

`serve` takes what the server does (`ServerOptions`), then where it listens
(`ServeConfig`, `127.0.0.1:8080` by default):

```lean
Connect.serve router
  { readMaxBytes := 1024 * 1024                    -- largest request message
    compressions := #[Compression.gzip]            -- besides identity
    interceptors := #[auth, timing, logRequests] } -- first one outermost
  { host := "0.0.0.0", port := 8080 }
```

### Interceptors

Interceptors run around calls, on servers (`ServerOptions.interceptors`) and on
clients (`ClientConfig.interceptors`), the first in the list outermost. As in
connect-py, there are two kinds, and both go in the same list.

A **metadata interceptor** sees each call's `Context` as it starts and its
outcome as it ends; what `onStart` returns goes to `onEnd`:

```lean
def timing : MetadataInterceptor Nat where
  onStart _ := IO.monoMsNow
  onEnd started ctx err? := do
    let ms := (← IO.monoMsNow) - started
    IO.eprintln s!"{ctx.spec.procedure}: {ms} ms, {(err?.map toString).getD "ok"}"

def auth : Interceptor := .before fun ctx => do
  unless ctx.requestHeaders.get? "authorization" == some "Bearer secret" do
    throw (.unauthenticated "missing token")
```

Throwing from `onStart` (or `before`) refuses the call; throwing from `onEnd`
(or `after`) replaces its outcome. On servers, the metadata interceptors at the
front of the list start before the request is read, so a call can be refused
without reading its body.

A **message interceptor** also sees the messages, with a hook for each kind of
call. A hook gets `next`, the rest of the chain, and may change the request or
the context it passes on, change the response, answer without calling `next`,
or call it again:

```lean
-- Logs every unary request, on either side.
def logRequests : MessageInterceptor where
  unary next ctx req := do
    IO.eprintln s!"{ctx.spec.procedure} {← Message.toJsonString req}"
    next ctx req

-- On a client: sends a token with every unary call.
def withToken : MessageInterceptor where
  unary next ctx req := do
    next { ctx with requestHeaders := ctx.requestHeaders.set "authorization" "Bearer secret" } req
```

Hooks reach the messages through their `Message` instances, whatever their
types. Streaming calls have hooks of their own, on servers (`clientStream`,
`serverStream`, `bidiStream`) and on clients (`clientStreamCall`,
`serverStreamCall`, `bidiStreamCall`). On a client:

```lean
let connection ← Connect.Client.create {
  baseUrl := "http://localhost:8080", interceptors := #[withToken, timing] }
```

## Clients

```lean
def main : IO Unit := do
  let connection ← Connect.Client.create { baseUrl := "http://localhost:8080" }
  let eliza : ElizaService.Client := { connection }
  let reply ← (eliza.say { sentence := "I feel happy" }).toIO
  IO.println reply.sentence
```

Calls return `RpcM` actions: `.toIO` runs one and raises its error, `.block`
returns an `Except`. `ClientConfig` chooses:

- the protocol: `.connect` (the default), `.grpc` or `.grpcWeb`;
- the HTTP version: `.http1` (the default) or `.http2`; gRPC always uses HTTP/2;
- the codec: `.proto` (the default) or `.json`;
- compression, message size limits, default headers and timeout, and whether
  side-effect-free methods use `GET`.

```lean
let connection ← Connect.Client.create {
  baseUrl := "http://localhost:8080", protocol := .grpc }
```

Per-call `CallOptions` set headers, a timeout and a cancellation context.
Streaming calls return a handle:

```lean
-- server streaming: iterate over the responses
for res in (← eliza.introduce { name := "Lean" }) do
  IO.println res.sentence

-- bidirectional: send, close, receive
let chat ← eliza.converse
chat.send { sentence := "Hi" }
chat.closeRequest
while true do
  let some res ← chat.receive | break
  IO.println res.sentence
```

For the response headers and trailers of a unary call, use
`client.connection.unaryWithMetadata ElizaService.Spec.say req`.

## Errors

A failed RPC throws a `ConnectError` with a `Code`, a message, optional
details (protobuf messages, carried as type name and bytes), and the headers and
trailers that came with it. `ConnectError.notFound "…"` and friends build one
for each code; `withDetail`, `withHeader` and `withTrailer` add to it.

Clients see the server's errors unchanged in every protocol, and make up their
own when the server cannot say: `unavailable` for a connection failure,
`deadline_exceeded` when the timeout passes, `canceled` after cancellation.

## Proofs

The protocol's pure pieces come with theorems, which Lean checks when it builds
the library and which cost nothing at run time. They rest on Lean's standard
axioms only (no `sorry`, no `native_decide`):

- decoding gives back what was encoded: message framing, HTTP/2 frames, HPACK
  integers, Huffman codes and strings, base64 and percent-encoding;
- untrusted input cannot make the parsers use more than configured: HPACK's
  integers and tables, frame and message sizes, and gzip's output;
- the message and frame readers return the same messages however the network
  splits the bytes.

[docs/proofs.md](docs/proofs.md) lists the theorems, and what they do not cover.

## Limitations

- **Linux and macOS.** CI builds and tests on both, and runs the conformance
  suite on Linux; Windows is untested.
- **No TLS** yet: `http://` only, and HTTP/2 only with prior knowledge (h2c).
- **Over HTTP/1.1**, bidirectional streams are half-duplex (a server reads all
  of a client's messages before its first answer), gRPC is unavailable (it needs
  trailers), and clients open a connection per call.
- **No retries.** A call that an HTTP/2 server refuses while it shuts down
  (GOAWAY, or `REFUSED_STREAM`) fails with `unavailable`, although it is safe
  to try again.
- **No write timeouts.** A peer that stops reading keeps its connection, and a
  handler writing to it, until it goes away: `Std.Async` cannot abort a pending
  socket write. (An HTTP/2 peer that sends frames without reading the replies is
  cut off.)
- **Throughput is modest.** With client and server in one process on a laptop,
  small unary calls run at about 2,200–2,400 per second over HTTP/1.1 (a
  connection per call) and 3,500–4,000 per second over HTTP/2
  (`lake exe bench [connect|grpc|grpc-web] [h2]`).

## Development

```bash
lake build              # the library and the plugin
lake test               # unit and end-to-end tests
lake exe tests reset    # only the tests whose names contain "reset"
```

[CONTRIBUTING.md](CONTRIBUTING.md) covers the rest: signing off commits, the
conformance suite, and regenerating code. [docs/architecture.md](docs/architecture.md)
explains how the pieces fit and why some of them are the way they are.
Changes are listed in [CHANGELOG.md](CHANGELOG.md); report security issues as
described in the [security policy](.github/SECURITY.md).

Layout: `Connect/` is the runtime, `ConnectGen/` the code generator,
`examples/eliza/` a complete example (`lake exe eliza-server`,
`lake exe eliza-client [connect|grpc|grpc-web] [proto|json] [h2]`), `tests/`
the tests, `conformance/` the conformance programs.

connect-lean follows the design of [connect-go](https://github.com/connectrpc/connect-go),
[connect-py](https://github.com/connectrpc/connect-py) and
[connect-rust](https://github.com/connectrpc/connect-rust), and uses `Std.Http`
the way [LeanAPI](https://github.com/theoriclabs/leanapi) does.

## License

[Apache License 2.0](LICENSE).
