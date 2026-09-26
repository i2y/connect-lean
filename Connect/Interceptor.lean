module

public import Connect.Codec
public import Connect.Context
public import Connect.Call

public section

/-!
# Interceptors

Interceptors run around calls, on servers (`ServerOptions.interceptors`) and
on clients (`ClientConfig.interceptors`), the first in the list outermost.
As in connect-py, there are two kinds.

A **metadata interceptor** sees each call's `Context` as the call starts, and
its outcome as it ends:

```lean
def timing : MetadataInterceptor Nat where
  onStart _ := IO.monoMsNow
  onEnd started ctx err := do
    IO.eprintln s!"{ctx.spec.procedure}: {(← IO.monoMsNow) - started} ms, failed: {err.isSome}"
```

Throwing from `onStart` refuses the call; throwing from `onEnd` replaces its
outcome. On servers, the metadata interceptors at the front of the list start
before the request is read, so a call can be refused without reading its body,
and end before the response is written, so they can still set its headers and
trailers.

A **message interceptor** sees the messages too, with a hook for each kind of
call. A hook receives `next`, the rest of the chain, and returns what takes its
place: it may change the request, or the context it passes on (a client adds
request headers this way), change the response, answer without calling `next`,
or call it again.

```lean
def logging : MessageInterceptor where
  unary next ctx req := do
    IO.eprintln s!"{ctx.spec.procedure} ← {← Message.toJsonString req}"
    next ctx req
```

Hooks are polymorphic in the message types: they reach messages through
their `Message` instances (ProtoJSON, binary, the type's name). Code for one
method's own types belongs in that method's handler.

Unary calls look alike on both sides, so one hook serves both. A streaming
call is a handler on a server (`clientStream`, `serverStream`, `bidiStream`)
and a call handle on a client (`clientStreamCall`, `serverStreamCall`,
`bidiStreamCall`), so each side has its own hooks.
-/

namespace Connect

/-! ## Calls as interceptors see them -/

/-- A unary call: from the context and the request, the response. -/
abbrev UnaryFunc (Req Res : Type) := Context → Req → RpcM Res

/-- A client-streaming call, as a server handles it. -/
abbrev ClientStreamFunc (Req Res : Type) := Context → RequestStream Req → RpcM Res

/-- A server-streaming call, as a server handles it. -/
abbrev ServerStreamFunc (Req Res : Type) := Context → Req → ResponseStream Res → RpcM Unit

/-- A bidirectional-streaming call, as a server handles it. -/
abbrev BidiStreamFunc (Req Res : Type) :=
  Context → RequestStream Req → ResponseStream Res → RpcM Unit

/-- A client-streaming call, as a client opens it. -/
abbrev ClientStreamCallFunc (Req Res : Type) := Context → RpcM (ClientStreamCall Req Res)

/-- A server-streaming call, as a client opens it. -/
abbrev ServerStreamCallFunc (Req Res : Type) := Context → Req → RpcM (ServerStreamCall Res)

/-- A bidirectional-streaming call, as a client opens it. -/
abbrev BidiStreamCallFunc (Req Res : Type) := Context → RpcM (BidiStreamCall Req Res)

/-! ## The two kinds -/

/-- An interceptor of messages, with a hook for each kind of call. Hooks left
    out pass calls through. -/
structure MessageInterceptor where
  /-- Unary calls, on servers and clients. -/
  unary : {Req Res : Type} → [Message Req] → [Message Res] →
      UnaryFunc Req Res → UnaryFunc Req Res := fun next => next
  /-- Client-streaming calls a server handles. -/
  clientStream : {Req Res : Type} → [Message Req] → [Message Res] →
      ClientStreamFunc Req Res → ClientStreamFunc Req Res := fun next => next
  /-- Server-streaming calls a server handles. -/
  serverStream : {Req Res : Type} → [Message Req] → [Message Res] →
      ServerStreamFunc Req Res → ServerStreamFunc Req Res := fun next => next
  /-- Bidirectional-streaming calls a server handles. -/
  bidiStream : {Req Res : Type} → [Message Req] → [Message Res] →
      BidiStreamFunc Req Res → BidiStreamFunc Req Res := fun next => next
  /-- Client-streaming calls a client makes. -/
  clientStreamCall : {Req Res : Type} → [Message Req] → [Message Res] →
      ClientStreamCallFunc Req Res → ClientStreamCallFunc Req Res := fun next => next
  /-- Server-streaming calls a client makes. -/
  serverStreamCall : {Req Res : Type} → [Message Req] → [Message Res] →
      ServerStreamCallFunc Req Res → ServerStreamCallFunc Req Res := fun next => next
  /-- Bidirectional-streaming calls a client makes. -/
  bidiStreamCall : {Req Res : Type} → [Message Req] → [Message Res] →
      BidiStreamCallFunc Req Res → BidiStreamCallFunc Req Res := fun next => next

instance : Inhabited MessageInterceptor := ⟨{}⟩

/-- An interceptor of each call's metadata (connect-py's `MetadataInterceptor`):
    `onStart` runs as the call starts, and what it returns goes to `onEnd`,
    which runs as the call ends, with the call's error, if any. Throwing from
    `onStart` refuses the call; throwing from `onEnd` replaces its outcome.
    On clients, a streaming call ends when its responses run out, when it
    fails, or when it is cancelled. -/
structure MetadataInterceptor (τ : Type) where
  onStart : Context → RpcM τ
  onEnd : τ → Context → Option ConnectError → RpcM Unit := fun _ _ _ => pure ()

namespace MessageInterceptor

/-- The type behind `Boxed`. -/
opaque BoxedImpl : NonemptyType.{0}

/-- A `MessageInterceptor`, held in `Type`. Its hooks quantify over message
    types, which puts it in `Type 1`, but servers and clients must stay in
    `Type`: a `Client` is returned from `IO`. A box is the same object, so
    boxing and unboxing do nothing at run time. -/
def Boxed : Type := BoxedImpl.type

instance : Nonempty Boxed := BoxedImpl.property

/-- The run-time implementation of `box`. -/
unsafe def boxUnsafe (i : MessageInterceptor) : Boxed := unsafeCast i

/-- The run-time implementation of `Boxed.unbox`. -/
unsafe def unboxUnsafe (b : Boxed) : MessageInterceptor := unsafeCast b

/-- Boxes an interceptor. -/
@[implemented_by boxUnsafe] opaque box (i : MessageInterceptor) : Boxed

/-- The boxed interceptor. -/
@[implemented_by unboxUnsafe] opaque Boxed.unbox (b : Boxed) : MessageInterceptor

end MessageInterceptor

/-- An interceptor, as servers and clients take it. `MetadataInterceptor`s and
    `MessageInterceptor`s coerce to one; `before` and `after` make simple
    metadata interceptors. -/
inductive Interceptor where
  | private metadata (start : Context → RpcM (Option ConnectError → RpcM Unit))
  | private messages (hooks : MessageInterceptor.Boxed)

namespace Interceptor

/-- A metadata interceptor. -/
def ofMetadata (i : MetadataInterceptor τ) : Interceptor :=
  .metadata fun ctx => do
    let token ← i.onStart ctx
    return fun err => i.onEnd token ctx err

/-- A message interceptor. -/
def ofMessages (i : MessageInterceptor) : Interceptor :=
  .messages i.box

/-- Runs `check` as each call starts; throwing from it refuses the call. -/
def before (check : Context → RpcM Unit) : Interceptor :=
  ofMetadata { onStart := check }

/-- Runs `f` as each call ends, with its error, if any; throwing from it
    replaces the call's outcome. -/
def after (f : Context → Option ConnectError → RpcM Unit) : Interceptor :=
  ofMetadata { onStart := fun _ => pure (), onEnd := fun _ ctx err => f ctx err }

end Interceptor

instance : CoeOut (MetadataInterceptor τ) Interceptor := ⟨Interceptor.ofMetadata⟩

instance : CoeOut MessageInterceptor Interceptor := ⟨Interceptor.ofMessages⟩

/-! ## Running interceptors

For the server and the client. -/

namespace Interceptor

/-- Ends a started metadata interceptor, given the call's error. -/
abbrev Finish := Option ConnectError → RpcM Unit

/-- Splits the list into the metadata interceptors at its front and the rest.
    Servers start the former before they read the request. -/
def splitLeading (is : Array Interceptor) : Array Interceptor × Array Interceptor :=
  let n := (is.findIdx? fun | .messages _ => true | .metadata _ => false).getD is.size
  (is.extract 0 n, is.extract n is.size)

/-- Starts metadata interceptors in order. Returns what ends those that
    started and, if one refused the call, its error. -/
def startAll (is : Array Interceptor) (ctx : Context) :
    Std.Async.Async (Array Finish × Option ConnectError) := do
  let mut started := #[]
  for i in is do
    if let .metadata start := i then
      match ← RpcM.run (start ctx) with
      | .ok finish => started := started.push finish
      | .error e => return (started, some e)
  return (started, none)

/-- Ends started interceptors, the last started first, with the call's
    outcome. One that throws replaces the error the rest see, and the outcome. -/
def finishAll (started : Array Finish) (outcome : Except ConnectError α) :
    Std.Async.Async (Except ConnectError α) := do
  let mut err := match outcome with | .ok _ => none | .error e => some e
  for finish in started.reverse do
    if let .error e ← RpcM.run (finish err) then err := some e
  return match err with
    | some e => .error e
    | none => outcome

/-- Runs `act` between the start and the end of a metadata interceptor. -/
private def around (start : Context → RpcM Finish) (ctx : Context) (act : RpcM α) : RpcM α := do
  let finish ← start ctx
  match ← RpcM.attempt act with
  | .ok a => finish none; return a
  | .error e => finish (some e); throw e

/-- Applies interceptors to a unary call, the first outermost. -/
def wrapUnary [Message Req] [Message Res] (is : Array Interceptor) (f : UnaryFunc Req Res) :
    UnaryFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx req => around start ctx (next ctx req)
    | .messages hooks => hooks.unbox.unary next

/-- Applies interceptors to a client-streaming call a server handles. -/
def wrapClientStream [Message Req] [Message Res] (is : Array Interceptor)
    (f : ClientStreamFunc Req Res) : ClientStreamFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx reqs => around start ctx (next ctx reqs)
    | .messages hooks => hooks.unbox.clientStream next

/-- Applies interceptors to a server-streaming call a server handles. -/
def wrapServerStream [Message Req] [Message Res] (is : Array Interceptor)
    (f : ServerStreamFunc Req Res) : ServerStreamFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx req out => around start ctx (next ctx req out)
    | .messages hooks => hooks.unbox.serverStream next

/-- Applies interceptors to a bidirectional-streaming call a server handles. -/
def wrapBidiStream [Message Req] [Message Res] (is : Array Interceptor)
    (f : BidiStreamFunc Req Res) : BidiStreamFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx reqs out => around start ctx (next ctx reqs out)
    | .messages hooks => hooks.unbox.bidiStream next

/-! A client's streaming call outlives the function that opens it, so a
metadata interceptor ends with the call: when its responses run out, when one
of its steps fails, or when it is cancelled. -/

/-- `finish`, made to run at most once. -/
private def once (finish : Finish) : BaseIO Finish := do
  let done ← IO.mkRef false
  return fun err => do
    unless ← done.modifyGet (fun d => (d, true)) do finish err

/-- Runs a step of a call, ending the interceptor if the step fails. -/
private def ending (finish : Finish) (step : RpcM α) : RpcM α := do
  match ← RpcM.attempt step with
  | .ok a => return a
  | .error e => finish (some e); throw e

/-- Ends the interceptor of a call being cancelled. -/
private def cancelling (finish : Finish) (cancel : Std.Async.Async Unit) :
    Std.Async.Async Unit := do
  cancel
  discard (RpcM.run (finish (some (.canceled "the call was canceled"))))

/-- Applies interceptors to a client-streaming call a client makes. -/
def wrapClientStreamCall [Message Req] [Message Res] (is : Array Interceptor)
    (f : ClientStreamCallFunc Req Res) : ClientStreamCallFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx => do
      let finish ← once (← start ctx)
      let call ← ending finish (next ctx)
      return { call with
        send := fun req => ending finish (call.send req)
        closeAndReceive := do
          let res ← ending finish call.closeAndReceive
          finish none
          return res
        cancel := cancelling finish call.cancel }
    | .messages hooks => hooks.unbox.clientStreamCall next

/-- Applies interceptors to a server-streaming call a client makes. -/
def wrapServerStreamCall [Message Req] [Message Res] (is : Array Interceptor)
    (f : ServerStreamCallFunc Req Res) : ServerStreamCallFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx req => do
      let finish ← once (← start ctx)
      let call ← ending finish (next ctx req)
      return { call with
        receive := do
          let r ← ending finish call.receive
          if r.isNone then finish none
          return r
        cancel := cancelling finish call.cancel }
    | .messages hooks => hooks.unbox.serverStreamCall next

/-- Applies interceptors to a bidirectional-streaming call a client makes. -/
def wrapBidiStreamCall [Message Req] [Message Res] (is : Array Interceptor)
    (f : BidiStreamCallFunc Req Res) : BidiStreamCallFunc Req Res :=
  is.foldr (init := f) fun i next => match i with
    | .metadata start => fun ctx => do
      let finish ← once (← start ctx)
      let call ← ending finish (next ctx)
      return { call with
        send := fun req => ending finish (call.send req)
        closeRequest := ending finish call.closeRequest
        receive := do
          let r ← ending finish call.receive
          if r.isNone then finish none
          return r
        cancel := cancelling finish call.cancel }
    | .messages hooks => hooks.unbox.bidiStreamCall next

end Interceptor

end Connect
