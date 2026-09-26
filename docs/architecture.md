# Architecture

connect-lean is a Connect, gRPC and gRPC-Web runtime written entirely in Lean 4,
with no native code of its own. This note explains how the pieces fit, and why
some of them are the way they are.

## Layers

```
generated code      <file>_connect.lean (protoc-gen-connect-lean)
                    <file>.lean         (protoc-gen-lean4, Lean-zh/protobuf)
                                 │
runtime             Server.handle ─ Client        (Connect/Server/Core, Connect/Client)
                        │     protocols, codecs, compression, envelopes
                        │
transports          Std.Http (HTTP/1.1) │ Connect.Http2 (HTTP/2, h2c)
                                 │
                    Std.Async TCP sockets
```

* **Messages** come from [Lean-zh/protobuf](https://github.com/Lean-zh/protobuf):
  its `ProtoMessage` and `ReflectMessage` instances give every generated type a
  `Connect.Message` instance (binary and ProtoJSON). The runtime never looks
  inside a message; methods are type-erased to bytes at registration
  (`Connect.Method.unary` and friends), after decoding with the negotiated codec.
* **Protocol logic** (`Connect/Protocol.lean`, `Connect/Server/Core.lean`, the
  session in `Connect/Client.lean`) knows nothing about sockets. A server
  transport hands `Server.handle` a `ServerRequest` and a `ResponseWriter`; a
  client transport provides a `Transport.Exchange`.
* **Transports**: HTTP/1.1 through `Std.Http` on the server and a small client
  of our own; HTTP/2 through `Connect.Http2`, shared by both sides. One listener
  serves both HTTP versions, telling them apart by the HTTP/2 preface.

## Decisions

**gzip in Lean.** Lake does not propagate link flags to downstream executables,
so a zlib binding would have made every user's build configure `-lz` (LeanHttp
works around the same problem for libcurl with `dlopen`). `Connect.Gzip` is a
complete inflater (after zlib's `puff.c`) and an LZ77 + fixed-Huffman deflater;
other algorithms can be plugged in as `Compression` values.

**Our own HTTP/2.** The existing Lean HTTP/2 libraries target older toolchains
and other goals (Extended CONNECT, their own gRPC). Connect needs full-duplex
streams, trailers, and h2c detection on the same port as HTTP/1.1, which is
simplest with a connection engine designed for it (`Connect/Http2/Connection.lean`).
The HPACK encoder never inserts into the dynamic table, so header blocks of
different streams can be sent in any order; the decoder is complete.

**`Std.Http` is half-duplex.** Once a response starts, `Std.Http` drains the
unread request body itself and the handler never sees it. For streams whose
client sends several messages, `Server.handle` therefore reads the rest of the
request into memory before its first response message over HTTP/1.1. HTTP/2
has no such restriction. `Std.Http` also cannot send trailers, so gRPC (which
needs them) is only served over HTTP/2.

**Errors are values in `RpcM`.** Handlers and calls run in
`ExceptT ConnectError Async`. `IO.Error`s that escape a handler reach the client
as `unknown`.

## Lessons worth keeping

* **Writers must not block readers.** HTTP/2 peers answer some frames
  (SETTINGS, PING, WINDOW_UPDATE) from their reading side. If both peers do that
  with blocking writes, they deadlock as soon as both socket buffers are full —
  which large messages in both directions reliably cause. Every frame goes
  through one queue and a writer task, so the reader never waits on the socket.
* **Count every received byte exactly once.** Bytes the application never
  reads (a stream reset early, a handler that fails before reading) must still
  be returned to the connection window, or the window shrinks for good and the
  connection stalls. Lookup and accounting happen under one lock, and a stream's
  unread bytes are credited when it goes away.
* **`try … catch` inside `ExceptT ε m` catches only `ε`.** An `IO.Error` thrown
  by the underlying monad passes straight through it. Code that must swallow I/O
  failures (closing an already closed channel, writing to a closed connection)
  does so in helpers defined in `Async` itself (`RpcM.ignoreErrors`,
  `Connection.sendQuietly`).
* **Stream identifiers must be opened in order.** Choosing an identifier and
  sending the stream's HEADERS happen under one lock, or concurrent calls on one
  HTTP/2 connection violate the protocol.
* **An `RpcM` bind of an `Async (Except ConnectError α)`** unifies with
  `RpcM α` and unwraps the `Except` silently, because `RpcM` unfolds to exactly
  that type. Bind such actions in `Async`, or use `ExceptT.mk` on purpose.
* **A race leaves its loser running.** `EAsync.race` returns the winner, but a
  timer that loses keeps the call's state alive until it fires, and a socket read
  that loses to a deadline keeps waiting. Lean cannot interrupt a task, so
  deadlines and cancellation use `Connect.runUntil`: `Selectable.one` over the
  action's completion and the stop conditions, which unregisters the losing
  selectors, plus an `onLate` hook that releases what an abandoned action
  produces anyway (an exchange opened after the client gave up is closed).
  Calls that cannot end early (no deadline, no cancellation) skip the race.
* **Prefer plain reads to `recvSelector`.** Waiting on a socket through
  `Selectable.one` costs several thread-pool hops per read, which made a
  connection's first read (the HTTP/2 preface check) several milliseconds
  slower and cut HTTP/1.1 throughput by more than half. Reads use `recv?`; to
  stop one early, `cancelRecv` makes it return as if the stream had ended, and
  the reader checks whether it was aborted.
* **Count handlers, not streams, against the concurrency limit.** A client that
  opens streams and resets them at once ("rapid reset", CVE-2023-44487) frees
  the stream but not the work it started. The server admits a new stream only
  while fewer handlers than `maxConcurrentStreams` are running, and cuts off a
  peer that queues more replies than it reads (`maxQueuedFrames`).
* **Queue a stream's RST_STREAM before forgetting the stream.** DATA already
  in flight for a stream being reset would otherwise find it gone and draw a
  second RST_STREAM (STREAM_CLOSED), which can reach the peer first and hide the
  real error code. The stream stays known, marked as resetting, until its
  RST_STREAM is queued; its DATA is dropped meanwhile.
* **Send a small response in one write.** A client whose deadline passes
  between reading a response's headers and its body is left with headers and
  no body. A unary response that fits the flow-control windows goes out as
  HEADERS and DATA in one batch.
* **Let the client's deadline decide.** The server's copy of a deadline runs a
  little ahead of the client's: the timeout it sends is rounded down, and the
  request spends time in transit. An answer sent at exactly that moment can
  reach a client just as it gives up, leaving it with headers and no body. The
  server cancels the handler at its deadline but answers `deadlineGraceMs`
  (20 ms) later.
* **After GOAWAY, close when idle.** A graceful shutdown sends GOAWAY, lets
  running handlers finish (up to a grace period) and then closes; waiting for
  the grace period on a connection with nothing running would hold every idle
  keep-alive connection open for its full length.

## Proofs

The pure codecs carry theorems (see the README). They are stated about the
functions the runtime itself calls, `Envelope.parseAt?` and
`Http2.Frame.parseAt?`; the buffering around them in `EnvelopeReader` and
`FrameReader` is tested (including byte-at-a-time delivery), not proved.
