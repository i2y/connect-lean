module

public import Std.Async
public import Connect.Envelope
public import Connect.Race
public import Connect.Server.Service

public section

/-!
# Serving an RPC

What a server does with one request, independent of the HTTP version it arrived
over. A transport hands in a `ServerRequest` and a `ResponseWriter`; `handle`
finds the method, works out the protocol and codec from the content type, and
serves the call:

* **Connect unary** (`application/proto`, `application/json`, or a GET with the
  message in the query): read the whole body, run the handler, answer with the
  message, or with an HTTP error status and a JSON error.
* **Streams** (Connect streaming, gRPC and gRPC-Web, unary calls included for
  the latter two): read and write envelopes as they come, and end with the
  RPC's status: an end-of-stream message for Connect, a trailers frame for
  gRPC-Web, HTTP trailers for gRPC. The HTTP status is 200 even when the RPC
  fails.

gRPC needs trailers, so it is served only over HTTP/2.
-/

namespace Connect

open Std.Async (Async)

/-- A request, as a transport delivers it. -/
structure ServerRequest where
  /-- `POST`, `GET`, … -/
  method : String
  /-- The path, without the query. -/
  path : String
  /-- The raw query, without `?`. -/
  query : String := ""
  headers : Headers
  peer : Option String := none
  /-- The next piece of the body; `none` at its end. -/
  body : Async (Option ByteArray)
  /-- Cancelled when the client goes away. -/
  cancellation : Std.CancellationContext
  /-- HTTP/2: the response can have trailers, and the request can still be read
      after the response has started. -/
  http2 : Bool := false

/-- How a transport sends a response. Either `respond` once, or `start`, any
    number of `write`s, then `finish`. -/
structure ResponseWriter where
  /-- Sends a complete response. -/
  respond : (status : Nat) → Headers → ByteArray → Async Unit
  /-- Sends the status and headers of a streamed response. -/
  start : (status : Nat) → Headers → Async Unit
  write : ByteArray → Async Unit
  /-- Ends a streamed response, with trailers when the transport has them. -/
  finish : (trailers : Headers) → Async Unit
  /-- Sends a complete response and its trailers, when the transport has them. -/
  respondWithTrailers : (status : Nat) → Headers → ByteArray → (trailers : Headers) → Async Unit :=
    fun status headers body trailers => do
      start status headers
      unless body.isEmpty do write body
      finish trailers

namespace Server

/-- How long after a call's deadline its `deadline_exceeded` answer goes out.
    The client's deadline is a little later than ours (the timeout it sent was
    rounded down, and the request spent time in transit), so an answer sent
    right at our deadline can reach it just as it gives up, when it may read
    the headers but not the body. Waiting briefly lets the client's own
    deadline decide. -/
def deadlineGraceMs : Nat := 20

/-- Runs the call until the context's deadline. When the deadline wins, the
    context is cancelled so a cooperative handler can stop, and the call fails
    `deadlineGraceMs` later; when the call wins, the timer is stopped at once
    rather than left holding the call's state. -/
def withDeadline (ctx : Context) (call : RpcM α) : RpcM α := ExceptT.mk do
  match ← ctx.timeRemaining with
  | none => RpcM.run call
  | some ms =>
    let expired : ConnectError := .deadlineExceeded "the deadline has passed"
    if ms == 0 then
      ctx.cancellation.cancel .deadline
      return .error expired
    match ← runWithin ms (RpcM.run call) with
    | some r => return r
    | none =>
      ctx.cancellation.cancel .deadline
      Std.Async.sleep (Std.Time.Millisecond.Offset.ofNat deadlineGraceMs)
      return .error expired

/-- Reads a whole body, failing once it passes `limit` bytes. -/
partial def readAll (body : Async (Option ByteArray)) (limit : Nat) (acc : ByteArray := .empty) :
    RpcM ByteArray := do
  match ← body with
  | none => return acc
  | some chunk =>
    let acc := acc ++ chunk
    if acc.size > limit then
      throw (.resourceExhausted s!"request message is larger than configured max {limit}")
    readAll body limit acc

private def parseConnectTimeout (headers : Headers) : Except ConnectError (Option Nat) :=
  match headers.get? HeaderName.connectTimeout with
  | none => .ok none
  | some t => match Timeout.parseConnect? t with
    | some ms => .ok (some ms)
    | none => .error (.invalidArgument s!"protocol error: invalid connect-timeout-ms \"{t}\"")

private def parseGrpcTimeout (headers : Headers) : Except ConnectError (Option Nat) :=
  match headers.get? HeaderName.grpcTimeout with
  | none => .ok none
  | some t => match Timeout.parseGrpc? t with
    | some ms => .ok (some ms)
    | none => .error (.invalidArgument s!"protocol error: invalid grpc-timeout \"{t}\"")

private def checkProtocolVersion (opts : ServerOptions) (headers : Headers) :
    Except ConnectError Unit :=
  match headers.get? HeaderName.connectProtocolVersion with
  | some "1" => .ok ()
  | some v => .error (.invalidArgument s!"connect-protocol-version must be \"1\": got \"{v}\"")
  | none =>
    if opts.requireConnectProtocolHeader then
      .error (.invalidArgument "missing required header: set connect-protocol-version to \"1\"")
    else .ok ()

private def findCompression (opts : ServerOptions) (name : String) : Except ConnectError Compression :=
  match Compression.find? opts.compressions name with
  | some c => .ok c
  | none => .error (.unimplemented
      s!"unknown compression \"{name}\": supported encodings are {Compression.acceptList opts.compressions}")

/-! ## Connect unary -/

/-- The response to a Connect unary call that failed. Headers and trailers the
    handler set are kept, with the error's own; trailers become `trailer-` headers. -/
private def connectUnaryError (res : ResponseWriter) (e : ConnectError) (headers trailers : Headers) :
    Async Unit :=
  let h := (headers.append (userMetadata e.headers)).set HeaderName.contentType "application/json"
  let trailers := trailers.append (userMetadata e.trailers)
  let h := trailers.entries.foldl (fun h (k, v) => h.add (HeaderName.trailerPrefix ++ k) v) h
  res.respond e.code.httpStatus h e.toJson.compress.toUTF8

/-- How a Connect unary request carries its message. -/
private inductive UnaryInput where
  | post (codec : Codec)
  | get

/-- The body of `connectUnary`, once the context exists. -/
private def connectUnaryCall (opts : ServerOptions) (req : ServerRequest)
    (run : Context → Codec → ByteArray → RpcM ByteArray) (input : UnaryInput) (res : ResponseWriter)
    (ctx : Context) : Async Unit := do
  let outcome ← RpcM.run do
    let (codec, payload) ← match input with
      | .post codec => do
        let comp ← RpcM.ofExcept (findCompression opts
          ((req.headers.get? HeaderName.contentEncoding).getD "identity"))
        let raw ← readAll req.body opts.readMaxBytes
        pure (codec, ← RpcM.ofExcept (comp.decompressPayload raw opts.readMaxBytes))
      | .get => do
        let params := parseQuery req.query
        let param (k : String) := params.findSome? fun (k', v) => if k' == k then some v else none
        if let some v := param "connect" then
          unless v == "v1" do
            throw (.invalidArgument s!"connect must be \"v1\": got \"{v}\"")
        let codec ← match param "encoding" >>= Codec.ofName? with
          | some c => pure c
          | none => throw (.invalidArgument "missing or unsupported encoding query parameter")
        let some message := queryParamBytes? req.query "message"
          | throw (.invalidArgument "missing message query parameter")
        let message ← if param "base64" == some "1" then
            match (String.fromUTF8? message) >>= Base64.decode? with
            | some b => pure b
            | none => throw (.invalidArgument "message query parameter is not valid base64")
          else pure message
        if message.size > opts.readMaxBytes then
          throw (.resourceExhausted
            s!"request message is larger than configured max {opts.readMaxBytes}")
        let comp ← RpcM.ofExcept (findCompression opts ((param "compression").getD "identity"))
        pure (codec, ← RpcM.ofExcept (comp.decompressPayload message opts.readMaxBytes))
    let response ← withDeadline ctx <|
      Interceptor.applyAll opts.interceptors ctx (run ctx codec payload)
    return (codec, response)
  let headers ← ctx.responseHeaders
  let trailers ← ctx.responseTrailers
  match outcome with
  | .error e => connectUnaryError res e headers trailers
  | .ok (codec, response) =>
    let accept := (req.headers.get? HeaderName.acceptEncoding).getD ""
    let (body, h) := match Compression.negotiate opts.compressions accept with
      | some c =>
        if response.size ≥ opts.compressMinBytes then
          (c.compress response, headers.set HeaderName.contentEncoding c.name)
        else (response, headers)
      | none => (response, headers)
    let h := h.set HeaderName.contentType (ContentType.render .connect codec false)
    let h := trailers.entries.foldl (fun h (k, v) => h.add (HeaderName.trailerPrefix ++ k) v) h
    res.respond 200 h body

/-- Serves a Connect unary call, from a POST body or a GET query. -/
private def connectUnary (opts : ServerOptions) (req : ServerRequest) (method : Method)
    (run : Context → Codec → ByteArray → RpcM ByteArray) (input : UnaryInput) (res : ResponseWriter) :
    Async Unit := do
  let httpMethod := match input with | .post _ => "POST" | .get => "GET"
  let checked : Except ConnectError (Option Nat) := do
    if let .post _ := input then checkProtocolVersion opts req.headers
    parseConnectTimeout req.headers
  let timeout ← match checked with
    | .ok t => pure t
    | .error e => return ← connectUnaryError res e {} {}
  let ctx ← Context.create method.spec .connect httpMethod req.headers req.peer timeout
    (← req.cancellation.fork)
  -- A forked context lives in its parent's table until cancelled.
  try connectUnaryCall opts req run input res ctx
  finally ctx.cancellation.cancel .cancel

/-! ## Streams -/

/-- Enveloped request messages, read from the body as the handler asks for them. -/
private structure RequestBody where
  /-- The next message, decompressed, or `none` after the last one. -/
  receive : Compression → RpcM (Option ByteArray)
  /-- Reads the rest of the body into memory. Over HTTP/1.1 the unread request
      body is lost once the response starts, so a handler that answers before it
      has read every request must have them buffered first. -/
  drain : Async Unit

private def requestBody (opts : ServerOptions) (body : Async (Option ByteArray)) :
    BaseIO RequestBody := do
  let readerRef ← IO.mkRef EnvelopeReader.empty
  let eofRef ← IO.mkRef false
  let pull : Async Unit := do
    match ← body with
    | some chunk => readerRef.modify (·.feed chunk)
    | none => eofRef.set true
  let rec drain (fuel : Nat) : Async Unit := do
    match fuel with
    | 0 => return
    | fuel + 1 =>
      if ← eofRef.get then return
      pull
      drain fuel
  let rec receive (comp : Compression) (fuel : Nat) : RpcM (Option ByteArray) := do
    let r ← readerRef.get
    if let some len := r.nextLength? then
      if len > opts.readMaxBytes then
        throw (.resourceExhausted
          s!"message size {len} is larger than configured max {opts.readMaxBytes}")
    match r.next? with
    | some (env, r') =>
      readerRef.set r'
      if Envelope.hasFlag env.flags (Envelope.endStreamFlag ||| Envelope.trailersFlag) then
        throw (.invalidArgument "protocol error: unexpected end-of-stream flag in a request")
      if env.isCompressed then
        if comp.name == "identity" then
          throw (.internal "protocol error: received compressed message without a compression")
        return some (← RpcM.ofExcept (comp.decompressPayload env.payload opts.readMaxBytes))
      return some env.payload
    | none =>
      if ← eofRef.get then
        if r.pending > 0 then
          throw (.invalidArgument "protocol error: incomplete envelope")
        return none
      pull
      match fuel with
      | 0 => throw (.internal "envelope reader made no progress")
      | fuel + 1 => receive comp fuel
  return { receive := fun comp => receive comp (2 ^ 62), drain := drain (2 ^ 62) }

/-- Reads the single request message of a unary or server-streaming call. -/
private def receiveOne (receive : RpcM (Option ByteArray)) : RpcM ByteArray := do
  let some first ← receive
    | throw (.unimplemented "unary request has zero messages")
  if (← receive).isSome then
    throw (.unimplemented "unary request has multiple messages")
  return first

/-- Serves an enveloped call: Connect streaming, gRPC or gRPC-Web. -/
private def streaming (opts : ServerOptions) (req : ServerRequest) (method : Method)
    (kind : RequestKind) (res : ResponseWriter) : Async Unit := do
  let protocol := kind.protocol
  let connect := protocol == .connect
  let (encodingHeader, acceptHeader) :=
    if connect then (HeaderName.connectContentEncoding, HeaderName.connectAcceptEncoding)
    else (HeaderName.grpcEncoding, HeaderName.grpcAcceptEncoding)
  let setup : Except ConnectError (Option Nat × Compression) := do
    if connect then checkProtocolVersion opts req.headers
    let timeout ← if connect then parseConnectTimeout req.headers else parseGrpcTimeout req.headers
    let comp ← findCompression opts ((req.headers.get? encodingHeader).getD "identity")
    return (timeout, comp)
  let respComp := Compression.negotiate opts.compressions ((req.headers.get? acceptHeader).getD "")
  let ctx ← Context.create method.spec protocol "POST" req.headers req.peer
    (match setup with | .ok (t, _) => t | .error _ => none) (← req.cancellation.fork)
  let reqBody ← requestBody opts req.body
  let headSent ← IO.mkRef false
  -- Headers carried by an error that comes before the response started.
  let errorHeaders ← IO.mkRef Headers.empty
  let responseHeaders : Async Headers := do
    let h := (← ctx.responseHeaders).append (← errorHeaders.get)
    let h := h.set HeaderName.contentType (ContentType.render protocol kind.codec true)
    let h := match respComp with
      | some c => h.set encodingHeader c.name
      | none => h
    return h.set acceptHeader (Compression.acceptList opts.compressions)
  -- Over HTTP/1.1, the rest of the request is read before the response starts
  -- (see `Std.Http`'s half-duplex note in the module doc of `Http1Server`).
  let drainRequest : Async Unit := do
    if !req.http2 && method.spec.streamType.clientStreams then
      try reqBody.drain catch _ => pure ()
  let sendHead : Async Unit := do
    unless ← headSent.get do
      headSent.set true
      drainRequest
      res.start 200 (← responseHeaders)
  -- A method with a single response (unary, client streaming) answers in one
  -- piece, which goes out in one write: messages are held until the end.
  let whole := !method.spec.streamType.serverStreams
  let held ← IO.mkRef ByteArray.empty
  let send (payload : ByteArray) : RpcM Unit := do
    let env : Envelope := match respComp with
      | some c =>
        if payload.size ≥ opts.compressMinBytes then
          { flags := Envelope.compressedFlag, payload := c.compress payload }
        else { flags := 0, payload }
      | none => { flags := 0, payload }
    if whole then held.modify (· ++ env.encode)
    else
      sendHead
      res.write env.encode
  let call : RpcM Unit := do
    let (_, comp) ← RpcM.ofExcept setup
    let receive := reqBody.receive comp
    let codec := kind.codec
    withDeadline ctx <| Interceptor.applyAll opts.interceptors ctx <|
      match method.impl with
      | .unary run => do send (← run ctx codec (← receiveOne receive))
      | .serverStream run => do run ctx codec (← receiveOne receive) send
      | .clientStream run => do send (← run ctx codec receive)
      | .bidiStream run => run ctx codec receive send
  let outcome ← RpcM.run call
  let err := match outcome with | .ok () => none | .error e => some e
  let mut trailers ← ctx.responseTrailers
  if let some e := err then
    -- The error's headers go out with the head if it has not been sent yet.
    if ← headSent.get then trailers := trailers.append (userMetadata e.headers)
    else errorHeaders.set (userMetadata e.headers)
    trailers := trailers.append (userMetadata e.trailers)
  let finalTrailers := trailers
  -- Ends an enveloped response with its last envelope.
  let finishWith (last : Envelope) : Async Unit := do
    if whole then
      drainRequest
      res.respond 200 (← responseHeaders) ((← held.get) ++ last.encode)
    else
      sendHead
      res.write last.encode
      res.finish {}
  try
    match protocol with
    | .connect =>
      finishWith { flags := Envelope.endStreamFlag, payload := EndStream.render finalTrailers err }
    | .grpcWeb =>
      let block := GrpcStatus.renderTrailerBlock (GrpcStatus.trailers finalTrailers err)
      finishWith { flags := Envelope.trailersFlag, payload := block }
    | .grpc =>
      -- Headers, then trailers, even without messages: clients then find the
      -- response headers where they expect them, as with connect-go and
      -- connect-rust.
      let status := GrpcStatus.trailers finalTrailers err
      if whole then res.respondWithTrailers 200 (← responseHeaders) (← held.get) status
      else
        sendHead
        res.finish status
  catch _ => pure ()
  -- A forked context lives in its parent's table until cancelled.
  ctx.cancellation.cancel .cancel

/-! ## Dispatch -/

private def plain (res : ResponseWriter) (status : Nat) (headers : Headers := {}) : Async Unit :=
  res.respond status headers .empty

/-- Serves one request. -/
def handle (router : Router) (opts : ServerOptions) (req : ServerRequest) (res : ResponseWriter) :
    Async Unit := do
  let some method := router.find? req.path
    | plain res 404
  let spec := method.spec
  let getAllowed := spec.streamType == .unary && spec.idempotency == .noSideEffects
  let allow := if getAllowed then "GET, POST" else "POST"
  let unsupported := plain res 415 (Headers.empty.add "accept-post" ContentType.acceptPost)
  match req.method with
  | "POST" =>
    match ContentType.parse? ((req.headers.get? HeaderName.contentType).getD "") with
    | none => unsupported
    | some kind =>
      match kind.protocol, method.impl with
      | .connect, .unary run =>
        if kind.streaming then unsupported
        else connectUnary opts req method run (.post kind.codec) res
      | .connect, _ =>
        if kind.streaming then streaming opts req method kind res else unsupported
      | .grpcWeb, _ => streaming opts req method kind res
      | .grpc, _ =>
        if req.http2 then streaming opts req method kind res
        else
          -- gRPC needs trailers; answer in the headers ("trailers-only").
          let h := Headers.empty
            |>.set HeaderName.contentType (ContentType.render .grpc kind.codec true)
            |>.set HeaderName.grpcStatus (toString Code.unimplemented.toGrpc)
            |>.set HeaderName.grpcMessage
              (Percent.encodeGrpcMessage "gRPC requires HTTP/2")
          res.respond 200 h .empty
  | "GET" =>
    match method.impl with
    | .unary run =>
      if getAllowed then connectUnary opts req method run .get res
      else plain res 405 (Headers.empty.add "allow" allow)
    | _ => plain res 405 (Headers.empty.add "allow" allow)
  | _ => plain res 405 (Headers.empty.add "allow" allow)

end Server

end Connect
