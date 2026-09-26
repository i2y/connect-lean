import Connect
import ElizaGen.connectrpc.eliza.v1.eliza_connect
import Tests.Harness

/-! End-to-end tests: a server and a client in one process, over real sockets. -/

namespace Tests.Integration
open Connect connectrpc.eliza.v1

/-- A service whose behaviour the tests steer through the request. -/
def testService : ElizaService where
  say ctx req := do
    if let some v := ctx.requestHeaders.get? "x-client" then ctx.setResponseHeader "x-echo" v
    ctx.setResponseTrailer "x-trailer" "done"
    match req.sentence with
    | "error" =>
      throw ((ConnectError.invalidArgument "you asked for it").withDetail
          { typeName := "google.rpc.DebugInfo", value := ⟨#[10, 1, 120]⟩ }
        |>.withHeader "x-error-header" "h" |>.withTrailer "x-error-trailer" "t")
    | "slow" =>
      for _ in [0:40] do
        ctx.checkCancelled
        Std.Async.sleep 25
      return { sentence := "too late" }
    | "timeout?" => return { sentence := toString ctx.timeoutMs }
    | s => return { sentence := s!"{ctx.httpMethod} {s}" }
  introduce _ req stream := do
    for i in [0:req.name.toNat!] do
      stream.send { sentence := s!"line {i}" }
    if req.name.toNat! == 2 then throw (.dataLoss "lost the rest")
  converse ctx reqs stream := do
    let mut n := 0
    for r in reqs do
      stream.send { sentence := s!"echo {r.sentence}" }
      n := n + 1
    ctx.setResponseTrailer "x-count" (toString n)

/-- Only `say`; the other methods keep their `unimplemented` defaults. -/
def partialService : ElizaService where
  say _ req := return { sentence := req.sentence }

def withServer (router : Router) (opts : ServerOptions := {}) (k : UInt16 → IO Unit)
    (cfg : ServeConfig := {}) : IO Unit := do
  let running ← Server.start router opts { cfg with port := 0 }
  try k running.port
  finally running.shutdown

def eliza (port : UInt16) (protocol : Protocol) (codec : Codec)
    (sendCompression : Option Compression := none) (useHttpGet := false) (readMaxBytes := 4194304)
    (httpVersion : Transport.HttpVersion := .http1) :
    IO ElizaService.Client := do
  let c ← Client.create {
    baseUrl := s!"http://127.0.0.1:{port}"
    protocol, codec, sendCompression, useHttpGet, readMaxBytes, httpVersion }
  return { connection := c }

def expectRpc (x : RpcM α) (what : String := "call") : IO α := do
  match ← x.block with
  | .ok a => pure a
  | .error e => throw (IO.userError s!"{what}: {e}")

def expectRpcError (x : RpcM α) (code : Code) (what : String := "call") : IO ConnectError := do
  match ← x.block with
  | .ok _ => throw (IO.userError s!"{what}: expected {code}, but it succeeded")
  | .error e =>
    unless e.code == code do throw (IO.userError s!"{what}: expected {code}, got {e}")
    return e

def modes : List (Protocol × Codec × Option Compression × Transport.HttpVersion) := [
  (.connect, .proto, none, .http1), (.connect, .json, none, .http1),
  (.connect, .proto, some .gzip, .http1), (.grpcWeb, .proto, none, .http1),
  (.grpcWeb, .json, some .gzip, .http1),
  (.connect, .proto, none, .http2), (.connect, .json, some .gzip, .http2),
  (.grpc, .proto, none, .http2), (.grpc, .json, some .gzip, .http2),
  (.grpcWeb, .proto, none, .http2)]

private def modeName : Protocol × Codec × Option Compression × Transport.HttpVersion → String
  | (p, c, comp, v) => s!"{p}/{c}/{(comp.map (·.name)).getD "identity"}/{repr v}"

def tests : List Test := [
  ("unary, streams and metadata in every mode", withServer (Router.empty.register testService) {}
    fun port => do
      for mode@(p, c, comp, v) in modes do
        let client ← eliza port p c comp (httpVersion := v)
        let what := modeName mode
        -- unary with headers and trailers
        let r ← expectRpc (client.connection.unaryWithMetadata (Res := SayResponse)
          ElizaService.Spec.say ({ sentence := "hi" } : SayRequest)
          { headers := Headers.empty.add "x-client" "lean" }) what
        expectEq r.message.sentence "POST hi" what
        expectEq (r.headers.get? "x-echo") (some "lean") what
        expectEq (r.trailers.get? "x-trailer") (some "done") what
        -- errors keep code, message, details and metadata
        let e ← expectRpcError (client.say { sentence := "error" }) .invalidArgument what
        expectEq e.message "you asked for it" what
        expectEq (e.details.map (·.typeName)) #["google.rpc.DebugInfo"] what
        expectEq (e.details.map (·.value)) #[⟨#[10, 1, 120]⟩] what
        expect ((e.headers.get? "x-error-header") == some "h" ||
          (e.trailers.get? "x-error-header") == some "h") s!"{what}: error header"
        expectEq (e.trailers.get? "x-error-trailer") (some "t") what
        -- server streaming
        let lines ← expectRpc (do (← client.introduce { name := "3" }).toArray) what
        expectEq (lines.map (·.sentence)) #["line 0", "line 1", "line 2"] what
        -- a stream that fails after two messages
        let call ← expectRpc (client.introduce { name := "2" }) what
        let first ← expectRpc call.receive what
        expectEq (first.map (·.sentence)) (some "line 0") what
        let _ ← expectRpc call.receive what
        let _ ← expectRpcError call.receive .dataLoss what
        -- bidirectional (half-duplex over HTTP/1.1)
        let chat ← expectRpc client.converse what
        let _ ← expectRpc (do
          for s in ["a", "b", "c"] do chat.send { sentence := s }
          chat.closeRequest) what
        let mut answers := #[]
        repeat
          let some res ← expectRpc chat.receive what | break
          answers := answers.push res.sentence
        expectEq answers #["echo a", "echo b", "echo c"] what
        expectEq ((← chat.responseTrailers).get? "x-count") (some "3") what),
  ("full-duplex streams over HTTP/2", withServer (Router.empty.register testService) {}
    fun port => do
      for p in [Protocol.connect, .grpc, .grpcWeb] do
        let client ← eliza port p .proto (httpVersion := .http2)
        let chat ← expectRpc client.converse s!"{p}"
        -- Each answer arrives before the next request is sent.
        for s in ["one", "two", "three"] do
          let _ ← expectRpc (chat.send { sentence := s }) s!"{p} send"
          let answer ← expectRpc chat.receive s!"{p} receive"
          expectEq (answer.map (·.sentence)) (some s!"echo {s}") s!"{p}"
        let _ ← expectRpc chat.closeRequest s!"{p} close"
        expectEq ((← expectRpc chat.receive s!"{p} end").map (·.sentence)) none s!"{p}"
        expectEq ((← chat.responseTrailers).get? "x-count") (some "3") s!"{p}"),
  ("many calls share one HTTP/2 connection", withServer (Router.empty.register testService) {}
    fun port => do
      let client ← eliza port .grpc .proto (httpVersion := .http2)
      let calls := (Array.range 50).map fun i => RpcM.run (client.say { sentence := s!"n{i}" })
      let results ← Std.Async.Async.block (Std.Async.EAsync.concurrentlyAll calls)
      for r in results, i in [0:50] do
        match r with
        | .ok res => expectEq res.sentence s!"POST n{i}"
        | .error e => throw (IO.userError (toString e))),
  ("Connect GET for side-effect-free methods", withServer (Router.empty.register testService) {}
    fun port => do
      for c in [Codec.proto, .json] do
        for comp in [none, some Compression.gzip] do
          let client ← eliza port .connect c comp (useHttpGet := true)
          let r ← expectRpc (client.say { sentence := "cached" })
          expectEq r.sentence "GET cached"),
  ("timeouts: propagated, and enforced by the client", withServer (Router.empty.register testService) {}
    fun port => do
      for (p, v) in [(Protocol.connect, Transport.HttpVersion.http1), (.grpcWeb, .http1),
          (.grpc, .http2)] do
        let client ← eliza port p .proto (httpVersion := v)
        let r ← expectRpc (client.say { sentence := "timeout?" } { timeoutMs := some 5000 })
        expectEq r.sentence "(some 5000)"
        let _ ← expectRpcError (client.say { sentence := "slow" } { timeoutMs := some 150 })
          .deadlineExceeded s!"{p}"),
  ("unimplemented methods and unknown routes", withServer (Router.empty.register partialService) {}
    fun port => do
      for p in [Protocol.connect, .grpcWeb, .grpc] do
        let client ← eliza port p .proto
        let _ ← expectRpcError (do (← client.introduce { name := "1" }).toArray) .unimplemented
          s!"{p} default handler"
      let client ← Client.create { baseUrl := s!"http://127.0.0.1:{port}" }
      let spec : MethodSpec := { service := "no.Such", name := "Method", streamType := .unary }
      let _ ← expectRpcError (client.unary (Res := SayResponse) spec ({} : SayRequest))
        .unimplemented "unknown route"),
  ("interceptors can reject calls", withServer (Router.empty.register testService)
    { interceptors := #[Interceptor.before fun ctx => do
        unless ctx.requestHeaders.get? "authorization" == some "Bearer lean" do
          throw (.unauthenticated "missing token")] }
    fun port => do
      for p in [Protocol.connect, .grpcWeb, .grpc] do
        let client ← eliza port p .proto
        let _ ← expectRpcError (client.say { sentence := "hi" }) .unauthenticated s!"{p} rejected"
        let r ← expectRpc (client.say { sentence := "hi" }
          { headers := Headers.empty.add "authorization" "Bearer lean" }) s!"{p} allowed"
        expectEq r.sentence "POST hi"),
  ("message size limits", withServer (Router.empty.register testService) { readMaxBytes := 64 }
    fun port => do
      let big := String.ofList (List.replicate 200 'x')
      for p in [Protocol.connect, .grpcWeb, .grpc] do
        let client ← eliza port p .proto
        let _ ← expectRpcError (client.say { sentence := big }) .resourceExhausted s!"{p} server limit"
        let client ← eliza port p .proto (readMaxBytes := 16)
        let _ ← expectRpcError (client.say { sentence := "a reply longer than sixteen bytes" })
          .resourceExhausted s!"{p} client limit"),
  ("an unreachable server is unavailable", do
    let client ← eliza 1 .connect .proto
    let _ ← expectRpcError (client.say { sentence := "hi" }) .unavailable)
]

end Tests.Integration
