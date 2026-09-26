module

public import Std.Sync
public import Connect.Rpc
public import Connect.Headers
public import Connect.Method
public import Connect.Protocol

public section

/-!
# Call context

A `Context` describes one call: the method, the protocol, the request headers
and the deadline. A handler receives one for the RPC it serves; through it, it
sets response headers and trailers, and learns when the client has gone away.
Interceptors receive one too, on servers and on clients (`isClient`).

Streaming handlers also receive a `RequestStream` to read the client's
messages, a `ResponseStream` to send their own, or both.
-/

namespace Connect

/-- What is known about a call: by a handler about the RPC it serves, or by an
    interceptor, on either side. -/
structure Context where
  /-- The method being called. -/
  spec : MethodSpec
  /-- The protocol the client speaks. -/
  protocol : Protocol
  /-- `POST`, or `GET` for Connect's cacheable unary calls. -/
  httpMethod : String
  /-- The request headers, including the client's custom metadata. On clients,
      the headers the call sends besides the protocol's own: an interceptor
      adds some by passing on `{ ctx with requestHeaders := … }`. -/
  requestHeaders : Headers
  /-- The other side's address, when known: the client's on servers, the
      server's on clients. -/
  peer : Option String := none
  /-- The timeout the client asked for, in milliseconds. -/
  timeoutMs : Option Nat := none
  /-- When the client stops waiting, in `IO.monoMsNow` milliseconds. -/
  deadline : Option Nat := none
  /-- On servers, cancelled when the client disconnects or the deadline
      passes. On clients, cancelling it cancels the call. -/
  cancellation : Std.CancellationContext
  /-- Headers to send before the first response message (on clients, the ones
      received). Prefer `setResponseHeader`. -/
  responseHeadersRef : IO.Ref Headers
  /-- Trailers to send after the last response message (on clients, the ones
      received). Prefer `setResponseTrailer`. -/
  responseTrailersRef : IO.Ref Headers
  /-- Whether this is a client's view of the call. -/
  isClient : Bool := false

namespace Context

/-- A context for `spec`, with fresh response metadata. `timeoutMs` becomes an
    absolute deadline. -/
def create (spec : MethodSpec) (protocol : Protocol) (httpMethod : String)
    (requestHeaders : Headers) (peer : Option String) (timeoutMs : Option Nat)
    (cancellation : Std.CancellationContext) (isClient := false) : BaseIO Context := do
  let now ← IO.monoMsNow
  return {
    spec, protocol, httpMethod, requestHeaders, peer, cancellation, timeoutMs, isClient
    deadline := timeoutMs.map (now + ·)
    responseHeadersRef := ← IO.mkRef {}
    responseTrailersRef := ← IO.mkRef {} }

/-- Sets a response header, replacing earlier values. Headers are sent with
    the first response message, so later changes are lost. -/
def setResponseHeader (ctx : Context) (name value : String) : BaseIO Unit :=
  ctx.responseHeadersRef.modify (·.set name value)

/-- Adds a response header value. -/
def addResponseHeader (ctx : Context) (name value : String) : BaseIO Unit :=
  ctx.responseHeadersRef.modify (·.add name value)

/-- Sets a response trailer, replacing earlier values. -/
def setResponseTrailer (ctx : Context) (name value : String) : BaseIO Unit :=
  ctx.responseTrailersRef.modify (·.set name value)

/-- Adds a response trailer value. -/
def addResponseTrailer (ctx : Context) (name value : String) : BaseIO Unit :=
  ctx.responseTrailersRef.modify (·.add name value)

def responseHeaders (ctx : Context) : BaseIO Headers := ctx.responseHeadersRef.get

def responseTrailers (ctx : Context) : BaseIO Headers := ctx.responseTrailersRef.get

/-- Milliseconds until the deadline; `none` without one. -/
def timeRemaining (ctx : Context) : BaseIO (Option Nat) := do
  match ctx.deadline with
  | none => return none
  | some d => return some (d - (← IO.monoMsNow))

/-- Whether the client has gone away or the deadline has passed. Long-running
    handlers should check this and stop early. -/
def isCancelled (ctx : Context) : BaseIO Bool :=
  ctx.cancellation.isCancelled

/-- Fails with `canceled` (or `deadline_exceeded`) if the RPC is no longer wanted. -/
def checkCancelled (ctx : Context) : RpcM Unit := do
  if ← ctx.cancellation.isCancelled then
    match ← ctx.cancellation.getCancellationReason with
    | some .deadline => throw (.deadlineExceeded "the deadline has passed")
    | _ => throw (.canceled "the client canceled the RPC")

end Context

/-- The messages a client streams to a handler. Iterate with `for msg in stream do`. -/
structure RequestStream (α : Type) where
  /-- The next message, or `none` once the client has finished sending. -/
  receive : RpcM (Option α)

namespace RequestStream

/-- Runs `f` on each message until the stream ends or `f` stops the loop. -/
@[specialize] protected partial def forIn {β : Type} (s : RequestStream α) (init : β)
    (f : α → β → RpcM (ForInStep β)) : RpcM β := do
  match ← s.receive with
  | none => return init
  | some a =>
    match ← f a init with
    | .done b => return b
    | .yield b => s.forIn b f

instance : ForIn RpcM (RequestStream α) α where
  forIn s init f := RequestStream.forIn s init f

/-- Receives every remaining message. -/
def toArray (s : RequestStream α) : RpcM (Array α) := do
  let mut out := #[]
  for a in s do out := out.push a
  return out

/-- A stream of the given messages; useful in tests. -/
def ofArray (msgs : Array α) : BaseIO (RequestStream α) := do
  let rest ← IO.mkRef msgs.toList
  return { receive := do
    match ← rest.get with
    | [] => return none
    | a :: as => rest.set as; return some a }

end RequestStream

/-- The messages a handler streams back to the client. -/
structure ResponseStream (α : Type) where
  /-- Sends one message. Response headers go out with the first one. -/
  send : α → RpcM Unit

end Connect
