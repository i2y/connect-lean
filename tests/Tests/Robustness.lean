import Connect
import ElizaGen.connectrpc.eliza.v1.eliza_connect
import Tests.Harness
import Tests.Integration

/-! Calls that go wrong on purpose: silent servers, cancelled calls, clients
    that reset streams, and servers shutting down mid-call. -/

namespace Tests.Robustness
open Connect connectrpc.eliza.v1
open Tests.Integration (withServer eliza expectRpc expectRpcError testService)

/-- Runs `k` with the port of a local listener that hands each connection to
    `onClient`. -/
def withListener (onClient : Std.Async.TCP.Socket.Client → Std.Async.Async Unit)
    (k : UInt16 → IO Unit) : IO Unit := do
  let some ip := Std.Net.IPv4Addr.ofString "127.0.0.1" | throw (IO.userError "bad address")
  let listener ← Std.Async.TCP.Socket.Server.mk
  listener.bind (.v4 { addr := ip, port := 0 })
  listener.listen 16
  let port := (← listener.getSockName).port
  let stop ← Std.CancellationContext.new
  let acceptLoop : Std.Async.Async Unit := do
    repeat
      let next ← Std.Async.Selectable.one #[
        .case listener.acceptSelector (fun c => pure (some c)),
        .case stop.doneSelector (fun _ => pure none)]
      let some client := next | break
      Std.Async.background (t := Std.Async.AsyncTask) (onClient client)
  let _ ← (Std.Async.background (t := Std.Async.AsyncTask) acceptLoop : Std.Async.Async Unit).toIO
  try k port
  finally stop.cancel .cancel

/-- Runs `k` with the port of a server that accepts connections and then says
    nothing at all. -/
def withSilentServer (k : UInt16 → IO Unit) : IO Unit := do
  -- Held so that they stay open until the end.
  let held ← IO.mkRef (#[] : Array Std.Async.TCP.Socket.Client)
  try withListener (fun c => held.modify (·.push c)) k
  finally
    for c in ← held.get do
      try c.shutdown.block catch _ => pure ()

/-- Reads a client's HTTP/2 preface: the bytes that came after it. -/
partial def readPreface (socket : Std.Async.TCP.Socket.Client) (acc : ByteArray := .empty) :
    Std.Async.Async ByteArray := do
  if acc.size ≥ Http2.preface.size then return acc.extract Http2.preface.size acc.size
  match ← socket.recv? 65536 with
  | some bytes => readPreface socket (acc ++ bytes)
  | none => throw (IO.userError "no preface")

/-- Runs `k` with the port of an HTTP/2 server that resets every stream, with
    the error code the request's `x-reset-code` header asks for. -/
def withResettingServer (k : UInt16 → IO Unit) : IO Unit :=
  let onStream (stream : Http2.Stream) : Std.Async.Async Unit := do
    let hs ← stream.headers
    let code := ((hs.find? (·.1 == "x-reset-code")).bind (·.2.toNat?)).getD 0
    stream.reset code.toUInt32
  withListener (k := k) fun client => do
    let rest ← readPreface client
    let _ ← Http2.Connection.serve {
      send := client.sendAll, recv := client.recv? 65536
      close := try client.shutdown catch _ => pure () } onStream {} rest

/-- Answers `introduce` with one message, then works on regardless of what the
    client does. -/
def stubbornService : ElizaService where
  introduce _ _ stream := do
    stream.send { sentence := "working" }
    Std.Async.sleep 700

/-- The request headers of a gRPC call to `introduce`. -/
def introduceHeaders (port : UInt16) : Http2.HeaderList := #[
  (":method", "POST"), (":scheme", "http"), (":authority", s!"127.0.0.1:{port}"),
  (":path", "/connectrpc.eliza.v1.ElizaService/Introduce"),
  ("content-type", "application/grpc"), ("te", "trailers")]

def tests : List Test := [
  ("a deadline holds against a server that never answers", withSilentServer fun port => do
    for (p, v) in [(Protocol.connect, Transport.HttpVersion.http1), (.grpcWeb, .http1),
        (.connect, .http2), (.grpc, .http2)] do
      let client ← eliza port p .proto (httpVersion := v)
      let start ← IO.monoMsNow
      let _ ← expectRpcError (client.say { sentence := "hello?" } { timeoutMs := some 200 })
        .deadlineExceeded s!"{p} over {repr v}"
      let took := (← IO.monoMsNow) - start
      expect (took < 2000) s!"{p} over {repr v}: gave up after {took} ms"),
  ("cancelling a call ends it at once", withServer (Router.empty.register testService) {}
    fun port => do
      for (p, v) in [(Protocol.connect, Transport.HttpVersion.http1), (.grpcWeb, .http1),
          (.connect, .http2), (.grpc, .http2)] do
        let client ← eliza port p .proto (httpVersion := v)
        let cancel ← Std.CancellationContext.new
        let start ← IO.monoMsNow
        let _ ← IO.asTask (do IO.sleep 100; cancel.cancel .cancel)
        let _ ← expectRpcError (client.say { sentence := "slow" } { cancellation := some cancel })
          .canceled s!"{p} over {repr v}"
        let took := (← IO.monoMsNow) - start
        expect (took < 800) s!"{p} over {repr v}: canceled after {took} ms"),
  ("a stream the server resets fails with the matching code", withResettingServer fun port => do
    let cases := [(Http2.ErrorCode.cancel, Code.canceled), (Http2.ErrorCode.refusedStream, .unavailable),
      (Http2.ErrorCode.enhanceYourCalm, .resourceExhausted),
      (Http2.ErrorCode.inadequateSecurity, .permissionDenied), (Http2.ErrorCode.internalError, .internal)]
    for p in [Protocol.connect, .grpc, .grpcWeb] do
      let client ← eliza port p .proto (httpVersion := .http2)
      for (reset, code) in cases do
        let opts : CallOptions := { headers := Headers.empty.add "x-reset-code" (toString reset) }
        let _ ← expectRpcError (client.say { sentence := "hi" } opts) code s!"{p}, unary, {reset}"
        let _ ← expectRpcError (do (← client.introduce { name := "1" } opts).toArray) code
          s!"{p}, server stream, {reset}"),
  ("resetting streams does not free the server's stream slots",
    withServer (Router.empty.register stubbornService) {} (cfg := { http2 := { maxConcurrentStreams := 2 } })
    fun port => Std.Async.Async.block do
      let socket ← Transport.connectTcp "127.0.0.1" port
      let conn ← Http2.Connection.connect {
        send := socket.sendAll, recv := socket.recv? 65536
        close := try socket.shutdown catch _ => pure () }
      -- An empty request message.
      let body := ({ flags := 0, payload := .empty } : Envelope).encode
      let start : Std.Async.Async Http2.Stream := do
        let s ← conn.openStream (introduceHeaders port) false
        s.sendData body true
        return s
      -- Two calls take both slots. The client resets each as soon as it has
      -- answered, but the handlers work on, and still count.
      for _ in [0:2] do
        let s ← start
        let _ ← s.headers
        s.reset Http2.ErrorCode.cancel
      -- The refusal may come before the request body is sent, or after.
      let refused ← try (do let _ ← (← start).headers; pure false) catch _ => pure true
      unless refused do throw (IO.userError "a third stream was served while two handlers ran")
      -- Once the handlers are done, there is room again.
      Std.Async.sleep 1000
      let fourth ← start
      let _ ← fourth.headers
      conn.close),
  ("shutdown lets a running call finish and closes idle connections", do
    let running ← Server.start (Router.empty.register testService) {} { port := 0 }
    let client ← eliza running.port .grpc .proto
    let _ ← expectRpc (client.say { sentence := "warm up" })
    let call ← IO.asTask (client.say { sentence := "slow" }).block
    IO.sleep 200
    let start ← IO.monoMsNow
    running.shutdown
    let took := (← IO.monoMsNow) - start
    match ← IO.wait call with
    | .ok (.ok r) => expectEq r.sentence "too late"
    | .ok (.error e) => throw (IO.userError s!"the running call failed: {e}")
    | .error e => throw e
    -- The call had about 800 ms to go; the grace period is 5 s.
    expect (took < 3000) s!"shutdown took {took} ms")
]

end Tests.Robustness
