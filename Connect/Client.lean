module

public import Connect.Client.Http1
public import Connect.Client.Http2
public import Connect.Codec
public import Connect.Compression
public import Connect.Method
public import Connect.Protocol
public import Connect.Rpc
public import Connect.Envelope
public import Connect.Race
public import Connect.Call
public import Connect.Interceptor

public section

/-!
# Clients

A `Client` calls the methods of one server. It speaks Connect, gRPC or
gRPC-Web, over HTTP/1.1 or HTTP/2 without TLS (gRPC always uses HTTP/2), with
binary or JSON messages:

```lean
let client ← IO.ofExcept (Connect.Client.new { baseUrl := "http://localhost:8080" })
let eliza : ElizaService.Client := { connection := client }
let reply ← eliza.say { sentence := "Hello" }
```

Generated clients forward to `Client.unary`, `serverStream`, `clientStream` and
`bidiStream`. A call fails with a `ConnectError`: the server's own error, or
one the client makes up from what it saw (`unavailable` when the server cannot
be reached, `deadline_exceeded` when the timeout passes).

Over HTTP/1.1, a bidirectional stream is half-duplex: the server may wait for
all requests before it answers. Over HTTP/2 it is full-duplex.
-/

namespace Connect

open Std.Async (Async)

/-- The `user-agent` this library sends. -/
def clientUserAgent : String := "connect-lean/0.1.0"

/-- Settings shared by every call a client makes. -/
structure ClientConfig where
  /-- The server's URL, such as `http://localhost:8080`, optionally with a path prefix. -/
  baseUrl : String
  protocol : Protocol := .connect
  codec : Codec := .proto
  /-- Compression for request messages; `none` sends them as they are. -/
  sendCompression : Option Compression := none
  /-- Compressions accepted in responses. -/
  acceptCompressions : Array Compression := Compression.defaults
  /-- Largest response message accepted, before and after decompression. -/
  readMaxBytes : Nat := 4 * 1024 * 1024
  /-- Call side-effect-free unary methods with HTTP GET (Connect only). -/
  useHttpGet : Bool := false
  /-- Headers sent with every call. -/
  headers : Headers := {}
  /-- Timeout for every call, unless the call sets its own. -/
  timeoutMs : Option Nat := none
  /-- The HTTP version. gRPC uses HTTP/2 regardless. -/
  httpVersion : Transport.HttpVersion := .http1
  /-- Settings for HTTP/2 connections. -/
  http2 : Http2.Settings := {}
  /-- Run around every call, the first outermost. -/
  interceptors : Array Interceptor := #[]

/-- Settings for one call. -/
structure CallOptions where
  headers : Headers := {}
  timeoutMs : Option Nat := none
  /-- Cancelling this context abandons the call, which then fails with `canceled`. -/
  cancellation : Option Std.CancellationContext := none

/-- A connection to one server. -/
structure Client where
  config : ClientConfig
  endpoint : Transport.Endpoint
  /-- The shared HTTP/2 connection, for clients that use HTTP/2. -/
  http2Pool : Option Http2Client.Pool

namespace Client

/-- Whether calls go over HTTP/2. -/
def usesHttp2 (config : ClientConfig) : Bool :=
  config.httpVersion == .http2 || config.protocol == .grpc

/-- A client for the server at `config.baseUrl`, failing on a malformed URL.
    Nothing connects until the first call. -/
def create (config : ClientConfig) : IO Client := do
  let endpoint ← IO.ofExcept ((Transport.Endpoint.parse config.baseUrl).mapError IO.userError)
  let http2Pool ← if usesHttp2 config then some <$> Http2Client.Pool.new endpoint config.http2
    else pure none
  return { config, endpoint, http2Pool }

/-- Closes the client's shared HTTP/2 connection, if it has one. -/
def close (c : Client) : Async Unit := do
  if let some p := c.http2Pool then p.close

/-- Starts an HTTP exchange with the server. -/
private def startExchange (c : Client) (method path : String) (headers : Headers)
    (body : Transport.RequestBody) : Async Transport.Exchange :=
  match c.http2Pool with
  | some pool => Http2Client.start pool method path headers body
  | none => Http1.start c.endpoint method path headers body

/-- Where a call stands, as far as ending it early is concerned. -/
private inductive CallState where
  | active | finished | cancelled | expired
  deriving BEq

/-- Ends a call early when its deadline passes or its caller cancels it: every
    transport action stops waiting at once, and the exchange is closed. -/
private structure CallControl where
  state : IO.Ref CallState
  /-- Cancelled when the call ends, to stop the watcher. -/
  ended : Std.CancellationContext
  /-- Cancelled when the call ends early, to stop pending transport actions. -/
  aborted : Std.CancellationContext
  /-- Closes the exchange, once there is one. -/
  closer : IO.Ref (Async Unit)
  /-- Why the exchange failed, if its transport can tell. -/
  failure : IO.Ref (BaseIO (Option ConnectError))
  deadline : Option Nat
  /-- Whether the call can end early: it has a deadline or a cancellation
      context, or its caller can `cancel` it. Only then do transport actions
      race `aborted`, which costs a task each. -/
  abortable : Bool

/-- Moves from `active` to `s`; `false` if the call had already left `active`. -/
private def CallControl.transition (c : CallControl) (s : CallState) : BaseIO Bool :=
  c.state.modifyGet fun cur => if cur == .active then (true, s) else (false, cur)

/-- Marks the call as ended normally and stops the watcher. -/
private def CallControl.finish (c : CallControl) : BaseIO Unit := do
  let _ ← c.transition .finished
  c.ended.cancel .cancel

/-- The error for a call that was ended early, if it was. -/
private def CallControl.early (c : CallControl) : BaseIO (Option ConnectError) := do
  match ← c.state.get with
  | .cancelled => return some (.canceled "the call was canceled")
  | .expired => return some (.deadlineExceeded "the deadline passed")
  | _ =>
    if let some d := c.deadline then
      if (← IO.monoMsNow) ≥ d then return some (.deadlineExceeded "the deadline passed")
    return none

/-- Runs a transport action until the call ends early. Failures report why
    the call was ended early, if it was, or what the transport says went wrong,
    and are `unavailable` otherwise. If the action completes after the call
    gave up on it, `onLate` releases what it produced.

    Reads pass `race := false`: ending a call early closes its exchange, which
    stops them (HTTP/2 resets the stream, HTTP/1.1 cancels the pending read),
    so they need not run in a task of their own. -/
private def CallControl.io (c : CallControl) (act : Async α)
    (onLate : α → Async Unit := fun _ => pure ()) (race := true) : RpcM α := ExceptT.mk do
  if let some e ← c.early then
    if (← c.state.get) != .finished then return .error e
  let outcome ← try
      if c.abortable && race then
        Except.ok <$> runUntil act #[.case c.aborted.doneSelector pure] onLate
      else (Except.ok ∘ Except.ok) <$> act
    catch e => pure (.error e)
  match outcome with
  | .ok (.ok a) => return .ok a
  | .ok (.error ()) => return .error ((← c.early).getD (.canceled "the call was canceled"))
  | .error e =>
    if let some early ← c.early then return .error early
    if let some known ← (← c.failure.get) then return .error known
    return .error (.unavailable (toString e))

/-- Starts the call's exchange. An exchange that opens after the call gave up
    is closed, and so is one the watcher fired too early to see. -/
private def CallControl.start (c : CallControl) (act : Async Transport.Exchange) :
    RpcM Transport.Exchange := do
  let exchange ← c.io act (onLate := fun ex => ex.close)
  c.closer.set exchange.close
  c.failure.set exchange.failure
  let s ← c.state.get
  if s == .cancelled || s == .expired then RpcM.ignoreErrors exchange.close
  return exchange

/-- Watches the deadline and the caller's cancellation, closing the exchange when
    either fires first. -/
private def CallControl.watch (c : CallControl) (user : Option Std.CancellationContext) :
    Async Unit := do
  if c.deadline.isNone && user.isNone then return
  let mut cases : Array (Std.Async.Selectable CallState) :=
    #[.case c.ended.doneSelector (fun _ => pure .finished)]
  if let some d := c.deadline then
    let now ← IO.monoMsNow
    cases := cases.push (.case (← Std.Async.Selector.sleep
      (Std.Time.Millisecond.Offset.ofNat (d - now))) (fun _ => pure .expired))
  if let some u := user then
    cases := cases.push (.case u.doneSelector (fun _ => pure .cancelled))
  let selectables := cases
  Std.Async.background (t := Std.Async.AsyncTask) do
    let outcome ← Std.Async.Selectable.one selectables
    if outcome != .finished then
      if ← c.transition outcome then
        c.aborted.cancel .cancel
        try (← c.closer.get) catch _ => pure ()

/-- The control of a new call, watching its deadline and its caller's
    cancellation context. `cancellable`: whether the caller gets a `cancel`. -/
private def CallControl.new (deadline : Option Nat) (user : Option Std.CancellationContext)
    (cancellable : Bool) : Async CallControl := do
  let c : CallControl := {
    state := ← IO.mkRef .active, ended := ← Std.CancellationContext.new,
    aborted := ← Std.CancellationContext.new, closer := ← IO.mkRef (pure ()),
    failure := ← IO.mkRef (pure none), deadline
    abortable := cancellable || deadline.isSome || user.isSome }
  c.watch user
  return c

/-- Cancels the call from the caller's side. -/
private def CallControl.cancel (c : CallControl) : Async Unit := do
  if ← c.transition .cancelled then
    c.ended.cancel .cancel
    c.aborted.cancel .cancel
    try (← c.closer.get) catch _ => pure ()

private def timeoutOf (c : Client) (opts : CallOptions) : Option Nat :=
  opts.timeoutMs <|> c.config.timeoutMs

private def baseHeaders (c : Client) (opts : CallOptions) : Headers :=
  let h := c.config.headers.append opts.headers
  if h.contains HeaderName.userAgent then h else h.set HeaderName.userAgent clientUserAgent

/-- What a call takes from its options or, under interceptors, from the
    context they pass on. -/
private structure CallSettings where
  /-- Headers to send besides the protocol's own. -/
  headers : Headers
  timeoutMs : Option Nat
  cancellation : Option Std.CancellationContext

private def settingsOf (c : Client) (opts : CallOptions) : CallSettings :=
  { headers := c.baseHeaders opts, timeoutMs := c.timeoutOf opts, cancellation := opts.cancellation }

private def settingsFrom (ctx : Context) : BaseIO CallSettings := do
  return { headers := ctx.requestHeaders, timeoutMs := ← ctx.timeRemaining
           cancellation := some ctx.cancellation }

/-- The context interceptors see for a call. -/
private def callContext (c : Client) (spec : MethodSpec) (opts : CallOptions)
    (httpMethod : String) : BaseIO Context := do
  let ep := c.endpoint
  let host := if ep.host.contains ':' then s!"[{ep.host}]" else ep.host
  let cancellation ← match opts.cancellation with
    | some x => pure x
    | none => Std.CancellationContext.new
  Context.create spec c.config.protocol httpMethod (c.baseHeaders opts) (some s!"{host}:{ep.port}")
    (c.timeoutOf opts) cancellation (isClient := true)

private def acceptList (c : Client) : String :=
  Compression.acceptList c.config.acceptCompressions

/-- The response compression named by a header, which must be one we accept. -/
private def responseCompression (c : Client) (name : Option String) : Except ConnectError Compression :=
  match name with
  | none => .ok Compression.identity
  | some n =>
    match Compression.find? c.config.acceptCompressions n with
    | some comp => .ok comp
    | none => .error (.internal s!"unknown encoding \"{n}\" in the response; accepted: {acceptList c}")

/-- Splits Connect unary response headers into headers and `trailer-` trailers. -/
private def splitUnaryTrailers (h : Headers) : Headers × Headers := Id.run do
  let mut headers := Headers.empty
  let mut trailers := Headers.empty
  for (k, v) in h do
    if k.startsWith HeaderName.trailerPrefix then
      trailers := trailers.add (k.drop HeaderName.trailerPrefix.length).toString v
    else headers := headers.add k v
  return (headers, trailers)

/-- Reads a whole response body, up to `limit` bytes. -/
private partial def readBody (exchange : Transport.Exchange) (limit : Nat) (acc : ByteArray := .empty) :
    Async (Option ByteArray) := do
  match ← exchange.read with
  | none => return some acc
  | some bytes =>
    let acc := acc ++ bytes
    if acc.size > limit then return none
    readBody exchange limit acc

/-! ## Connect unary -/

private def unaryConnect [Message Req] [Message Res] (c : Client) (spec : MethodSpec) (req : Req)
    (settings : CallSettings) : RpcM (UnaryResponse Res) := do
  let cfg := c.config
  let timeout := settings.timeoutMs
  let deadline := timeout.map ((← IO.monoMsNow) + ·)
  let payload ← RpcM.ofIOExcept (cfg.codec.encode req)
  let (payload, sentWith) := match cfg.sendCompression with
    | some comp => (comp.compress payload, some comp.name)
    | none => (payload, none)
  let mut headers := settings.headers
    |>.set HeaderName.connectProtocolVersion "1"
    |>.set HeaderName.acceptEncoding (acceptList c)
  if let some t := timeout then headers := headers.set HeaderName.connectTimeout (toString t)
  let useGet := cfg.useHttpGet && spec.idempotency == .noSideEffects
  let ctl ← CallControl.new deadline settings.cancellation (cancellable := false)
  let exchange ← ctl.start <|
    if useGet then
      let message := match cfg.codec, sentWith with
        | .json, none => s!"message={Percent.encodeQuery ((String.fromUTF8? payload).getD "")}"
        | _, _ => s!"base64=1&message={Base64.encodeUrl payload}"
      let compression := match sentWith with
        | some n => s!"&compression={n}"
        | none => ""
      let query := s!"?connect=v1&encoding={cfg.codec.name}{compression}&{message}"
      c.startExchange "GET" (spec.procedure ++ query) headers .empty
    else
      let h := headers.set HeaderName.contentType (ContentType.render .connect cfg.codec false)
      let h := match sentWith with
        | some n => h.set HeaderName.contentEncoding n
        | none => h
      c.startExchange "POST" spec.procedure h (.fixed payload)
  try
    let (status, respHeaders) ← ctl.io exchange.head (race := false)
    let (userHeaders, trailers) := splitUnaryTrailers (userMetadata respHeaders)
    -- An error body is JSON; read it whole, with room for a long message.
    let limit := if status == 200 then cfg.readMaxBytes else max cfg.readMaxBytes 65536
    let some body ← ctl.io (readBody exchange limit) (race := false)
      | throw (.resourceExhausted s!"message is larger than configured max {cfg.readMaxBytes}")
    let comp ← RpcM.ofExcept (c.responseCompression (respHeaders.get? HeaderName.contentEncoding))
    let contentType := ContentType.normalize ((respHeaders.get? HeaderName.contentType).getD "")
    if status != 200 then
      let fallback := Code.ofHttpStatus status
      if contentType == "application/json" then
        let body := (comp.decompress body cfg.readMaxBytes).toOption.getD body
        match (String.fromUTF8? body).map Lean.Json.parse with
        | some (.ok json@(.obj _)) =>
          let err := ConnectError.ofJson json fallback
          throw { err with headers := userHeaders, trailers }
        | _ => pure ()
      throw { code := fallback, message := s!"HTTP status {status}", headers := userHeaders, trailers }
    let expected := ContentType.render .connect cfg.codec false
    unless contentType == expected do
      let code := if contentType.startsWith "application/" then Code.internal else .unknown
      throw (ConnectError.new code s!"invalid content-type \"{contentType}\"; expecting \"{expected}\"")
    let body ← RpcM.ofExcept (comp.decompressPayload body cfg.readMaxBytes)
    let message ← RpcM.ofIOExcept (cfg.codec.decode body)
    return { message, headers := userHeaders, trailers }
  finally
    ctl.finish
    RpcM.ignoreErrors exchange.close

/-! ## Enveloped calls: Connect streaming and gRPC-Web -/

/-- The shared machinery of an enveloped call, in bytes. -/
private structure Session where
  send : ByteArray → RpcM Unit
  closeSend : RpcM Unit
  responseHeaders : RpcM Headers
  receive : RpcM (Option ByteArray)
  trailers : BaseIO Headers
  cancel : Async Unit

/-- Opens an enveloped call. `cancellable`: whether its caller gets a `cancel`.
    A call with a single request passes it as `request`: it then goes out with
    the headers, as a body of known length, and the session sends nothing more. -/
private def openSession (c : Client) (spec : MethodSpec) (settings : CallSettings)
    (cancellable : Bool := true) (request : Option ByteArray := none) : RpcM Session := do
  let cfg := c.config
  let connect := cfg.protocol == .connect
  let timeout := settings.timeoutMs
  let deadline := timeout.map ((← IO.monoMsNow) + ·)
  let (encodingHeader, acceptHeader) :=
    if connect then (HeaderName.connectContentEncoding, HeaderName.connectAcceptEncoding)
    else (HeaderName.grpcEncoding, HeaderName.grpcAcceptEncoding)
  let mut headers := settings.headers
    |>.set HeaderName.contentType (ContentType.render cfg.protocol cfg.codec true)
    |>.set acceptHeader (acceptList c)
  if let some comp := cfg.sendCompression then headers := headers.set encodingHeader comp.name
  if connect then
    headers := headers.set HeaderName.connectProtocolVersion "1"
    if let some t := timeout then headers := headers.set HeaderName.connectTimeout (toString t)
  else
    if cfg.protocol == .grpc then headers := headers.set HeaderName.te "trailers"
    else headers := headers.set "x-grpc-web" "1"
    if let some t := timeout then headers := headers.set HeaderName.grpcTimeout (Timeout.renderGrpc t)
  let envelope (payload : ByteArray) : ByteArray :=
    let env : Envelope := match cfg.sendCompression with
      | some comp => { flags := Envelope.compressedFlag, payload := comp.compress payload }
      | none => { flags := 0, payload }
    env.encode
  let body := match request with
    | some payload => .fixed (envelope payload)
    | none => .chunked
  let ctl ← CallControl.new deadline settings.cancellation cancellable
  let exchange ← ctl.start (c.startExchange "POST" spec.procedure headers body)
  let headState ← IO.mkRef (none : Option (Headers × Compression))
  -- gRPC headers carrying a status: the whole answer, unless a body or
  -- trailers follow.
  let trailersOnly ← IO.mkRef (none : Option Headers)
  let bodySeen ← IO.mkRef false
  let readerRef ← IO.mkRef EnvelopeReader.empty
  let endedRef ← IO.mkRef false
  let trailersRef ← IO.mkRef Headers.empty
  let finish : RpcM Unit := do
    ctl.finish
    RpcM.ignoreErrors exchange.close
  let fail {α : Type} (e : ConnectError) : RpcM α := do
    endedRef.set true
    finish
    throw e
  let responseHeaders : RpcM Headers := do
    if let some (h, _) := ← headState.get then return h
    let (status, respHeaders) ← ctl.io exchange.head (race := false)
    let userHeaders := userMetadata respHeaders
    -- gRPC-Web may answer with the status in the headers ("trailers-only").
    -- It counts only if no body follows, which `receive` finds out.
    if !connect && respHeaders.contains HeaderName.grpcStatus then
      trailersOnly.set (some respHeaders)
      let comp := (c.responseCompression (respHeaders.get? encodingHeader)).toOption.getD
        Compression.identity
      headState.set (some (userHeaders, comp))
      return userHeaders
    if status != 200 then
      let code := Code.ofHttpStatus status
      fail { code, message := s!"HTTP status {status}", headers := userHeaders }
    let contentType := ContentType.normalize ((respHeaders.get? HeaderName.contentType).getD "")
    let expected := ContentType.render cfg.protocol cfg.codec true
    let bare := if cfg.protocol == .grpc then "application/grpc" else "application/grpc-web"
    let ok := contentType == expected || (!connect && cfg.codec == .proto && contentType == bare)
    unless ok do
      let prefixOk := if connect then contentType.startsWith "application/connect+"
        else contentType.startsWith bare
      fail (ConnectError.new (if prefixOk then .internal else .unknown)
        s!"invalid content-type \"{contentType}\"; expecting \"{expected}\"")
    let comp ← match c.responseCompression (respHeaders.get? encodingHeader) with
      | .ok comp => pure comp
      | .error e => fail e
    headState.set (some (userHeaders, comp))
    return userHeaders
  let rec receive (fuel : Nat) : RpcM (Option ByteArray) := do
    let headers ← responseHeaders
    if ← endedRef.get then return none
    -- Once canceled or past the deadline, stop, even with messages buffered.
    if (← ctl.state.get) == .cancelled || (← ctl.state.get) == .expired then
      if let some e ← ctl.early then fail e
    let comp := ((← headState.get).map (·.2)).getD Compression.identity
    let r ← readerRef.get
    if let some len := r.nextLength? then
      if len > cfg.readMaxBytes then
        fail (.resourceExhausted s!"message size {len} is larger than configured max {cfg.readMaxBytes}")
    match r.next? with
    | some (env, r') =>
      readerRef.set r'
      let payload ← if env.isCompressed then
          if comp.name == "identity" then
            fail (.internal "protocol error: received a compressed message without a compression")
          else match comp.decompressPayload env.payload cfg.readMaxBytes with
            | .ok p => pure p
            | .error e => fail e
        else pure env.payload
      if connect && Envelope.hasFlag env.flags Envelope.endStreamFlag then
        match EndStream.parse payload with
        | .error e => fail e
        | .ok (trailers, err) =>
          trailersRef.set trailers
          match err with
          | some e => fail { e with headers }
          | none => endedRef.set true; finish; return none
      else if !connect && Envelope.hasFlag env.flags Envelope.trailersFlag then
        let trailers := GrpcStatus.parseTrailerBlock payload
        trailersRef.set (userMetadata trailers)
        match GrpcStatus.ofTrailers trailers with
        | some e => fail { e with headers }
        | none => endedRef.set true; finish; return none
      else
        return some payload
    | none =>
      match ← ctl.io exchange.read (race := false) with
      | some bytes =>
        unless bytes.isEmpty do bodySeen.set true
        readerRef.modify (·.feed bytes)
      | none =>
        if r.pending > 0 then fail (.internal "protocol error: incomplete envelope")
        if connect then
          fail (.internal "protocol error: the stream ended without an end-of-stream message")
        -- gRPC: the status comes as HTTP trailers...
        let httpTrailers ← exchange.trailers
        if httpTrailers.contains HeaderName.grpcStatus then
          trailersRef.set (userMetadata httpTrailers)
          match GrpcStatus.ofTrailers httpTrailers with
          | some e => fail { e with headers }
          | none => endedRef.set true; finish; return none
        -- ...or, in a trailers-only response, in the headers, when there is
        -- no body at all.
        if let some h := ← trailersOnly.get then
          unless ← bodySeen.get do
            let userHeaders := userMetadata h
            trailersRef.set userHeaders
            match GrpcStatus.ofTrailers h with
            | some e => fail { e with headers := {}, trailers := userHeaders }
            | none => endedRef.set true; finish; return none
        fail (.internal "protocol error: the stream ended without a status")
      match fuel with
      | 0 => fail (.internal "stream made no progress")
      | fuel + 1 => receive fuel
  let send (payload : ByteArray) : RpcM Unit := ctl.io (exchange.write (envelope payload))
  return {
    send, responseHeaders
    closeSend := ctl.io exchange.finish
    receive := receive (2 ^ 62)
    trailers := trailersRef.get
    cancel := ctl.cancel }

private def encodeMessage [Message α] (c : Client) (msg : α) : RpcM ByteArray :=
  RpcM.ofIOExcept (c.config.codec.encode msg)

private def decodeMessage [Message α] (c : Client) (bytes : ByteArray) : RpcM α :=
  RpcM.ofIOExcept (c.config.codec.decode bytes)

/-- Receives the single response of a unary or client-streaming call. -/
private def receiveOne [Message Res] (c : Client) (s : Session) : RpcM Res := do
  let some bytes ← s.receive
    | throw (.unimplemented "unary response has zero messages")
  let res ← decodeMessage c bytes
  if (← s.receive).isSome then
    throw (.unimplemented "unary response has multiple messages")
  return res

/-! ## Calls

Each call runs as it is when the client has no interceptors, and otherwise
inside them, with a `Context` they may pass on changed. -/

/-- Whether a unary call uses `GET`. -/
private def usesGet (c : Client) (spec : MethodSpec) : Bool :=
  c.config.protocol == .connect && c.config.useHttpGet && spec.idempotency == .noSideEffects

/-- Keeps a call's response metadata in `ctx`, for interceptors: `headers` and
    `trailers` once it ended, or those of its error. -/
private def record (ctx : Context) (outcome : Except ConnectError Unit) (headers : RpcM Headers)
    (trailers : BaseIO Headers) : RpcM Unit := do
  match outcome with
  | .ok () =>
    if let .ok h ← RpcM.attempt headers then ctx.responseHeadersRef.set h
    ctx.responseTrailersRef.set (← trailers)
  | .error e =>
    ctx.responseHeadersRef.set e.headers
    ctx.responseTrailersRef.set e.trailers

private def unaryPlain [Message Req] [Message Res] (c : Client) (spec : MethodSpec) (req : Req)
    (settings : CallSettings) : RpcM (UnaryResponse Res) := do
  if c.config.protocol == .connect then
    unaryConnect c spec req settings
  else
    let s ← openSession c spec settings (cancellable := false)
      (request := some (← encodeMessage c req))
    -- Closes the exchange if the call fails before it ends by itself.
    try
      let message ← receiveOne c s
      return { message, headers := ← s.responseHeaders, trailers := ← s.trailers }
    finally
      s.cancel

/-- Calls a unary method, returning the response with its headers and trailers. -/
def unaryWithMetadata [Message Req] [Message Res] (c : Client) (spec : MethodSpec) (req : Req)
    (opts : CallOptions := {}) : RpcM (UnaryResponse Res) := do
  let interceptors := c.config.interceptors
  if interceptors.isEmpty then return ← c.unaryPlain spec req (c.settingsOf opts)
  let ctx ← c.callContext spec opts (if c.usesGet spec then "GET" else "POST")
  let call : UnaryFunc Req Res := fun ctx req => do
    match ← RpcM.attempt (c.unaryPlain spec req (← settingsFrom ctx)) with
    | .ok r =>
      record ctx (.ok ()) (pure r.headers) (pure r.trailers)
      return r.message
    | .error e =>
      record ctx (.error e) (pure {}) (pure {})
      throw e
  let message ← Interceptor.wrapUnary interceptors call ctx req
  return { message, headers := ← ctx.responseHeaders, trailers := ← ctx.responseTrailers }

/-- Calls a unary method. -/
def unary [Message Req] [Message Res] (c : Client) (spec : MethodSpec) (req : Req)
    (opts : CallOptions := {}) : RpcM Res :=
  (·.message) <$> c.unaryWithMetadata spec req opts

private def serverStreamPlain [Message Req] [Message Res] (c : Client) (spec : MethodSpec)
    (req : Req) (settings : CallSettings) : RpcM (ServerStreamCall Res) := do
  let s ← openSession c spec settings (request := some (← encodeMessage c req))
  return {
    responseHeaders := s.responseHeaders
    receive := do
      match ← s.receive with
      | none => return none
      | some bytes => return some (← decodeMessage c bytes)
    responseTrailers := s.trailers
    cancel := s.cancel }

/-- Calls a server-streaming method. -/
def serverStream [Message Req] [Message Res] (c : Client) (spec : MethodSpec) (req : Req)
    (opts : CallOptions := {}) : RpcM (ServerStreamCall Res) := do
  let interceptors := c.config.interceptors
  if interceptors.isEmpty then return ← c.serverStreamPlain spec req (c.settingsOf opts)
  let ctx ← c.callContext spec opts "POST"
  let start : ServerStreamCallFunc Req Res := fun ctx req => do
    let call ← c.serverStreamPlain spec req (← settingsFrom ctx)
    return { call with
      receive := do
        match ← RpcM.attempt call.receive with
        | .ok r =>
          if r.isNone then record ctx (.ok ()) call.responseHeaders call.responseTrailers
          return r
        | .error e => record ctx (.error e) (pure {}) (pure {}); throw e }
  Interceptor.wrapServerStreamCall interceptors start ctx req

private def clientStreamPlain [Message Req] [Message Res] (c : Client) (spec : MethodSpec)
    (settings : CallSettings) : RpcM (ClientStreamCall Req Res) := do
  let s ← openSession c spec settings
  return {
    send := fun req => do s.send (← encodeMessage c req)
    closeAndReceive := do s.closeSend; receiveOne c s
    responseHeaders := s.responseHeaders
    responseTrailers := s.trailers
    cancel := s.cancel }

/-- Starts a client-streaming call. -/
def clientStream [Message Req] [Message Res] (c : Client) (spec : MethodSpec)
    (opts : CallOptions := {}) : RpcM (ClientStreamCall Req Res) := do
  let interceptors := c.config.interceptors
  if interceptors.isEmpty then return ← c.clientStreamPlain spec (c.settingsOf opts)
  let ctx ← c.callContext spec opts "POST"
  let start : ClientStreamCallFunc Req Res := fun ctx => do
    let call ← c.clientStreamPlain spec (← settingsFrom ctx)
    return { call with
      closeAndReceive := do
        match ← RpcM.attempt call.closeAndReceive with
        | .ok res =>
          record ctx (.ok ()) call.responseHeaders call.responseTrailers
          return res
        | .error e => record ctx (.error e) (pure {}) (pure {}); throw e }
  Interceptor.wrapClientStreamCall interceptors start ctx

private def bidiStreamPlain [Message Req] [Message Res] (c : Client) (spec : MethodSpec)
    (settings : CallSettings) : RpcM (BidiStreamCall Req Res) := do
  let s ← openSession c spec settings
  return {
    send := fun req => do s.send (← encodeMessage c req)
    closeRequest := s.closeSend
    receive := do
      match ← s.receive with
      | none => return none
      | some bytes => return some (← decodeMessage c bytes)
    responseHeaders := s.responseHeaders
    responseTrailers := s.trailers
    cancel := s.cancel }

/-- Starts a bidirectional-streaming call. -/
def bidiStream [Message Req] [Message Res] (c : Client) (spec : MethodSpec)
    (opts : CallOptions := {}) : RpcM (BidiStreamCall Req Res) := do
  let interceptors := c.config.interceptors
  if interceptors.isEmpty then return ← c.bidiStreamPlain spec (c.settingsOf opts)
  let ctx ← c.callContext spec opts "POST"
  let start : BidiStreamCallFunc Req Res := fun ctx => do
    let call ← c.bidiStreamPlain spec (← settingsFrom ctx)
    return { call with
      receive := do
        match ← RpcM.attempt call.receive with
        | .ok r =>
          if r.isNone then record ctx (.ok ()) call.responseHeaders call.responseTrailers
          return r
        | .error e => record ctx (.error e) (pure {}) (pure {}); throw e }
  Interceptor.wrapBidiStreamCall interceptors start ctx

end Client

end Connect
