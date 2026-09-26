module

public import Std.Sync
public import Connect.Http2.Connection
public import Connect.Client.Transport

public section

/-!
# An HTTP/2 client transport

Calls to one server share a single HTTP/2 connection without TLS ("h2c", with
prior knowledge), each call on its own stream. The connection is opened on
first use and replaced when it closes or the server sends GOAWAY.
-/

namespace Connect.Http2Client

open Std.Async (Async)
open Connect.Transport

/-- The shared connection to one endpoint. -/
structure Pool where
  endpoint : Endpoint
  settings : Http2.Settings := {}
  /-- The connection, or the attempt to open one, that calls should use, with a
      number telling attempts apart. -/
  private current : Std.Mutex (Nat × Option (IO.Promise (Except String Http2.Connection)))

namespace Pool

def new (endpoint : Endpoint) (settings : Http2.Settings := {}) : BaseIO Pool := do
  return { endpoint, settings, current := ← Std.Mutex.new (0, none) }

private def dial (p : Pool) : Async Http2.Connection := do
  let socket ← connectTcp p.endpoint.host p.endpoint.port
  let transport : Http2.Transport := {
    send := socket.sendAll
    recv := socket.recv? 65536
    close := try socket.shutdown catch _ => pure () }
  Http2.Connection.connect transport p.settings

/-- A usable connection, opening one if needed. Concurrent callers share one
    attempt to connect. -/
partial def connection (p : Pool) : Async Http2.Connection := do
  let fresh : IO.Promise (Except String Http2.Connection) ← IO.Promise.new
  let (gen, promise, mine) ← p.current.atomically do
    match ← get with
    | (gen, some pr) => return (gen, pr, false)
    | (gen, none) => set (gen + 1, some fresh); return (gen + 1, fresh, true)
  if mine then
    try promise.resolve (.ok (← p.dial))
    catch e => promise.resolve (.error (toString e))
  -- Forgets this attempt, unless another caller already replaced it.
  let forget : Async Unit := p.current.atomically do
    let (g, _) ← get
    if g == gen then set (g, (none : Option (IO.Promise (Except String Http2.Connection))))
  match ← Std.Async.await promise.result! with
  | .ok c =>
    if ← c.isUsable then return c
    forget
    connection p
  | .error e =>
    forget
    throw (IO.userError e)

/-- Closes the shared connection. -/
def close (p : Pool) : Async Unit := do
  let pr ← p.current.atomically (modifyGet fun (g, pr) => (pr, (g, none)))
  if let some pr := pr then
    match ← Std.Async.await pr.result! with
    | .ok c => c.close
    | .error _ => pure ()

end Pool

private def isConnectionHeader (name : String) : Bool :=
  name == "connection" || name == "keep-alive" || name == "proxy-connection" ||
  name == "transfer-encoding" || name == "upgrade" || name == "host"

/-- The error for a stream the server reset: the gRPC protocol's mapping of
    HTTP/2 error codes, which connect-go follows too. -/
def resetError (code : UInt32) : ConnectError :=
  let named (name : String) := s!"the server reset the stream with {name}"
  if code == Http2.ErrorCode.refusedStream then .unavailable (named "REFUSED_STREAM")
  else if code == Http2.ErrorCode.cancel then .canceled (named "CANCEL")
  else if code == Http2.ErrorCode.enhanceYourCalm then .resourceExhausted (named "ENHANCE_YOUR_CALM")
  else if code == Http2.ErrorCode.inadequateSecurity then
    .permissionDenied (named "INADEQUATE_SECURITY")
  else .internal (named s!"error code {code}")

/-- Starts a request on a new stream of the pool's connection. -/
def start (pool : Pool) (method path : String) (headers : Headers) (body : RequestBody) :
    Async Exchange := do
  let conn ← pool.connection
  let ep := pool.endpoint
  let host := if ep.host.contains ':' then s!"[{ep.host}]" else ep.host
  let authority := if ep.port == 80 then host else s!"{host}:{ep.port}"
  let hs : Http2.HeaderList := #[(":method", method), (":scheme", "http"),
    (":authority", authority), (":path", ep.pathPrefix ++ path)] ++
    (headers.entries.filter fun (k, _) => !isConnectionHeader k)
  let noBody := match body with | .empty => true | _ => false
  let stream ← conn.openStream hs noBody
  -- A server that resets the stream before reading the body has its reason,
  -- which the response side reports.
  if let .fixed bytes := body then
    try stream.sendData bytes true
    catch e => if (← stream.peerResetCode).isNone then throw e
  let headRef ← IO.mkRef (none : Option (Nat × Headers))
  return {
    write := fun data => stream.sendData data false
    finish := stream.sendData .empty true
    head := do
      if let some h := ← headRef.get then return h
      let hs ← stream.headers
      let status := ((hs.find? (·.1 == ":status")).bind (·.2.toNat?)).getD 0
      let h := (status, ({ entries := hs.filter (!·.1.startsWith ":") } : Headers))
      headRef.set (some h)
      return h
    read := stream.read
    trailers := do return { entries := (← stream.trailers) }
    close := stream.reset Http2.ErrorCode.cancel
    failure := return (← stream.peerResetCode).map resetError }

end Connect.Http2Client
