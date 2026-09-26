import Connect
import EdgeGen.edge.v1.kinds_connect
import Tests.Harness
import Tests.Integration

/-! Interceptors on servers and clients, after connect-py's interceptor tests. -/

namespace Tests.Interceptors
open Connect edge.v1
open Tests.Integration (withServer expectRpc expectRpcError)

/-- One method of each kind, counting the calls it handles. A request saying
    "error" fails the call. -/
def kinds (handled : IO.Ref Nat) : KindsService where
  unary _ req := do
    handled.modify (· + 1)
    if req.text == "error" then throw (.invalidArgument "bad request")
    return { text := s!"unary {req.text}" }
  clientStream _ reqs := do
    handled.modify (· + 1)
    let mut texts := #[]
    for r in reqs do
      if r.text == "error" then throw (.invalidArgument "bad request")
      texts := texts.push r.text
    return { text := ",".intercalate texts.toList }
  serverStream _ req out := do
    handled.modify (· + 1)
    if req.text == "error" then throw (.invalidArgument "bad request")
    out.send { text := s!"one {req.text}" }
    out.send { text := s!"two {req.text}" }
  bidiStream _ reqs out := do
    handled.modify (· + 1)
    for r in reqs do
      if r.text == "error" then throw (.invalidArgument "bad request")
      out.send { text := s!"echo {r.text}" }

def modes : List (Protocol × Transport.HttpVersion) :=
  [(.connect, .http1), (.grpc, .http2), (.grpcWeb, .http1)]

def kindsClient (port : UInt16) (protocol : Protocol) (httpVersion : Transport.HttpVersion)
    (interceptors : Array Interceptor := #[]) : IO KindsService.Client := do
  let c ← Client.create {
    baseUrl := s!"http://127.0.0.1:{port}", protocol, httpVersion, interceptors }
  return { connection := c }

/-- Makes one call of each kind, every request saying `text`: the replies. -/
def callAll (client : KindsService.Client) (text : String) : IO (Array (Option String)) := do
  let unary ← (client.unary { text }).block
  let clientStream ← (do
      let call ← client.clientStream
      call.send { text }
      call.send { text := "b" }
      return (← call.closeAndReceive).text : RpcM String).block
  let serverStream ← (do
      let call ← client.serverStream { text }
      return ",".intercalate ((← call.toArray).map (·.text)).toList : RpcM String).block
  let bidiStream ← (do
      let call ← client.bidiStream
      call.send { text }
      call.closeRequest
      let mut out := #[]
      repeat
        let some r ← call.receive | break
        out := out.push r.text
      return ",".intercalate out.toList : RpcM String).block
  return #[unary.toOption.map (·.text), clientStream.toOption, serverStream.toOption,
    bidiStream.toOption]

/-- connect-py's test interceptor: greets each call, and says goodbye with its
    error, if any. -/
def recorder (log : IO.Ref (Array String)) : MetadataInterceptor String where
  onStart ctx := return s!"Hello {ctx.spec.name}"
  onEnd token _ err := log.modify fun l => l.push <| match err with
    | none => s!"{token} and goodbye"
    | some e => s!"{token} and goodbye with error {e.message}"

/-- Posts `body` with the raw HTTP/1.1 client: the response status. -/
def rawPost (port : UInt16) (path contentType : String) (body : ByteArray) : IO Nat :=
  Std.Async.Async.block do
    let exchange ← Http1.start { host := "127.0.0.1", port } "POST" path
      (Headers.empty.set "content-type" contentType) (.fixed body)
    let (status, _) ← exchange.head
    repeat
      let some _ ← exchange.read | break
    exchange.close
    return status

def tests : List Test := [
  ("metadata interceptors see every kind of call, on both sides", do
    for (p, v) in modes do
      let serverLog ← IO.mkRef #[]
      let clientLog ← IO.mkRef #[]
      let sides ← IO.mkRef (#[] : Array Bool)
      let side := Interceptor.before fun ctx => sides.modify (·.push ctx.isClient)
      let handled ← IO.mkRef 0
      withServer (Router.empty.register (kinds handled))
          { interceptors := #[recorder serverLog, side] } fun port => do
        let client ← kindsClient port p v #[recorder clientLog, side]
        expectEq (← callAll client "a") #[some "unary a", some "a,b", some "one a,two a",
          some "echo a"] s!"{p} replies"
        let expected := #["Hello Unary and goodbye", "Hello ClientStream and goodbye",
          "Hello ServerStream and goodbye", "Hello BidiStream and goodbye"]
        expectEq (← clientLog.get) expected s!"{p} client"
        expectEq (← serverLog.get) expected s!"{p} server"
        expectEq ((← sides.get).filter id).size 4 s!"{p} client sides"
        expectEq ((← sides.get).filter (!·)).size 4 s!"{p} server sides"),
  ("metadata interceptors see the errors calls end with", do
    for (p, v) in modes do
      let serverLog ← IO.mkRef #[]
      let clientLog ← IO.mkRef #[]
      let handled ← IO.mkRef 0
      withServer (Router.empty.register (kinds handled))
          { interceptors := #[recorder serverLog] } fun port => do
        let client ← kindsClient port p v #[recorder clientLog]
        expectEq (← callAll client "error") #[none, none, none, none] s!"{p} replies"
        let expected := #["Hello Unary and goodbye with error bad request",
          "Hello ClientStream and goodbye with error bad request",
          "Hello ServerStream and goodbye with error bad request",
          "Hello BidiStream and goodbye with error bad request"]
        expectEq (← clientLog.get) expected s!"{p} client"
        expectEq (← serverLog.get) expected s!"{p} server"),
  ("leading metadata interceptors run even when a request cannot be parsed", do
    let leading ← IO.mkRef #[]
    let trailing ← IO.mkRef #[]
    let handled ← IO.mkRef 0
    let passThrough : MessageInterceptor := {}
    withServer (Router.empty.register (kinds handled))
        { interceptors := #[recorder leading, passThrough, recorder trailing] } fun port => do
      let status ← rawPost port "/edge.v1.KindsService/Unary" "application/json" "{".toUTF8
      expect (status != 200) s!"unary status {status}"
      let envelope := Envelope.encode { flags := 0, payload := "{".toUTF8 }
      let status ← rawPost port "/edge.v1.KindsService/ServerStream" "application/connect+json"
        envelope
      expectEq status 200 "stream status"
      expectEq (← handled.get) 0 "handler calls"
      let log ← leading.get
      expectEq log.size 2 "leading interceptor calls"
      expect (log[0]!.startsWith "Hello Unary and goodbye with error") log[0]!
      expect (log[1]!.startsWith "Hello ServerStream and goodbye with error") log[1]!
      -- One after a message interceptor runs inside the chain, after parsing.
      expectEq (← trailing.get) #[] "trailing interceptor"),
  ("a leading metadata interceptor wraps the message interceptors after it", do
    let events ← IO.mkRef (#[] : Array String)
    let note (e : String) : BaseIO Unit := events.modify (·.push e)
    let metadata : MetadataInterceptor Unit :=
      { onStart := fun _ => note "metadata start", onEnd := fun _ _ _ => note "metadata end" }
    let messages : MessageInterceptor := { unary := fun next ctx req => do
      note "unary before"
      try next ctx req finally note "unary after" }
    let impl : KindsService := { unary := fun _ req => do note "handler"; return { text := req.text } }
    withServer (Router.empty.register impl) { interceptors := #[metadata, messages] } fun port => do
      let client ← kindsClient port .connect .http1
      let _ ← expectRpc (client.unary { text := "a" })
      expectEq (← events.get)
        #["metadata start", "unary before", "handler", "unary after", "metadata end"]),
  ("metadata set as a call ends still reaches the client", do
    let stamp : MetadataInterceptor Unit := { onStart := fun _ => pure (), onEnd := fun _ ctx _ => do
      ctx.setResponseHeader "x-interceptor" "ran"
      ctx.setResponseTrailer "x-interceptor-trailer" "ran" }
    let handled ← IO.mkRef 0
    withServer (Router.empty.register (kinds handled)) { interceptors := #[stamp] } fun port => do
      for (p, v) in modes do
        let client ← kindsClient port p v
        let r ← expectRpc (client.connection.unaryWithMetadata KindsService.Spec.unary
          ({ text := "a" } : Ping) (Res := Pong))
        expectEq (r.headers.get? "x-interceptor") (some "ran") s!"{p} unary header"
        expectEq (r.trailers.get? "x-interceptor-trailer") (some "ran") s!"{p} unary trailer"
        let call ← expectRpc (client.serverStream { text := "a" })
        let _ ← expectRpc call.toArray
        expectEq ((← call.responseTrailers).get? "x-interceptor-trailer") (some "ran")
          s!"{p} stream trailer"),
  ("an interceptor that fails as a call ends replaces its outcome", do
    let deny := Interceptor.after fun _ err =>
      if err.isNone then throw (.permissionDenied "denied after the fact") else pure ()
    let handled ← IO.mkRef 0
    -- On the server...
    withServer (Router.empty.register (kinds handled)) { interceptors := #[deny] } fun port => do
      for (p, v) in modes do
        let client ← kindsClient port p v
        let _ ← expectRpcError (client.unary { text := "a" }) .permissionDenied s!"{p} server"
    -- ...and on the client.
    withServer (Router.empty.register (kinds handled)) {} fun port => do
      for (p, v) in modes do
        let client ← kindsClient port p v #[deny]
        let _ ← expectRpcError (client.unary { text := "a" }) .permissionDenied s!"{p} client"),
  ("message interceptors can rewrite requests and answer calls themselves", do
    -- The server replaces every unary request with one it decodes from JSON.
    let rewrite : MessageInterceptor := { unary := fun next ctx _ => do
      next ctx (← RpcM.ofIOExcept (Codec.json.decode "{\"text\":\"rewritten\"}".toUTF8)) }
    -- The client answers some calls from a cache, without the server.
    let cache : MessageInterceptor := { unary := fun next ctx req => do
      if ctx.requestHeaders.contains "x-cached" then
        RpcM.ofIOExcept (Codec.json.decode "{\"text\":\"from the cache\"}".toUTF8)
      else next ctx req }
    let handled ← IO.mkRef 0
    withServer (Router.empty.register (kinds handled)) { interceptors := #[rewrite] } fun port => do
      for (p, v) in modes do
        let client ← kindsClient port p v #[cache]
        expectEq (← expectRpc (client.unary { text := "a" })).text "unary rewritten" s!"{p}"
        let cached ← expectRpc (client.unary { text := "a" }
          { headers := Headers.empty.add "x-cached" "1" })
        expectEq cached.text "from the cache" s!"{p} cached"
      expectEq (← handled.get) 3 "calls that reached the handler"),
  ("client interceptors can add headers and retry calls", do
    let attempts ← IO.mkRef 0
    -- The server refuses calls without a token, and fails every other call.
    let auth := Interceptor.before fun ctx => do
      unless ctx.requestHeaders.get? "x-token" == some "secret" do
        throw (.unauthenticated "no token")
    let flaky : MessageInterceptor := { unary := fun next ctx req => do
      let n ← attempts.modifyGet fun n => (n, n + 1)
      if n % 2 == 0 then throw (.unavailable "try again")
      next ctx req }
    -- The client sends the token, and tries once more when the server is unavailable.
    let token : MessageInterceptor := { unary := fun next ctx req => do
      next { ctx with requestHeaders := ctx.requestHeaders.set "x-token" "secret" } req }
    let retry : MessageInterceptor := { unary := fun next ctx req => do
      match ← RpcM.attempt (next ctx req) with
      | .error e => if e.code == .unavailable then next ctx req else throw e
      | .ok res => return res }
    let handled ← IO.mkRef 0
    withServer (Router.empty.register (kinds handled)) { interceptors := #[auth, flaky] }
        fun port => do
      for (p, v) in modes do
        let bare ← kindsClient port p v
        let _ ← expectRpcError (bare.unary { text := "a" }) .unauthenticated s!"{p} without token"
        let client ← kindsClient port p v #[retry, token]
        expectEq (← expectRpc (client.unary { text := "a" })).text "unary a" s!"{p} with token"
      expectEq (← attempts.get) 6 "attempts"),
  ("stream interceptors see each message, on both sides", do
    let seen ← IO.mkRef (#[] : Array String)
    let note (e : String) : BaseIO Unit := seen.modify (·.push e)
    let server : MessageInterceptor := {
      clientStream := fun next ctx reqs => next ctx { receive := do
        let r ← reqs.receive
        if let some m := r then note s!"server got {← Message.toJsonString m}"
        return r }
      serverStream := fun next ctx req out => next ctx req { send := fun m => do
        note s!"server sent {← Message.toJsonString m}"
        out.send m } }
    let client : MessageInterceptor := {
      clientStreamCall := fun next ctx => do
        let call ← next ctx
        return { call with send := fun m => do
          note s!"client sent {← Message.toJsonString m}"
          call.send m }
      serverStreamCall := fun next ctx req => do
        let call ← next ctx req
        return { call with receive := do
          let r ← call.receive
          if let some m := r then note s!"client got {← Message.toJsonString m}"
          return r } }
    let handled ← IO.mkRef 0
    withServer (Router.empty.register (kinds handled)) { interceptors := #[server] } fun port => do
      for (p, v) in modes do
        seen.set #[]
        let c ← kindsClient port p v #[client]
        let _ ← callAll c "x"
        let log ← seen.get
        let from_ (who : String) := log.filter (·.startsWith who)
        expectEq (from_ "client sent") #["client sent {\"text\":\"x\"}",
          "client sent {\"text\":\"b\"}"] s!"{p} client sent"
        expectEq (from_ "server got") #["server got {\"text\":\"x\"}",
          "server got {\"text\":\"b\"}"] s!"{p} server got"
        expectEq (from_ "server sent") #["server sent {\"text\":\"one x\"}",
          "server sent {\"text\":\"two x\"}"] s!"{p} server sent"
        expectEq (from_ "client got") #["client got {\"text\":\"one x\"}",
          "client got {\"text\":\"two x\"}"] s!"{p} client got")
]

end Tests.Interceptors
