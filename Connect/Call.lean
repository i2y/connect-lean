module

public import Connect.Headers
public import Connect.Rpc

public section

/-!
# Client calls

What a client call returns: a unary response with its metadata, or a handle on
a streaming call to send, receive, and cancel with. Client interceptors see
and may wrap the same handles.
-/

namespace Connect

open Std.Async (Async)

/-- A unary response with its metadata. -/
structure UnaryResponse (α : Type) where
  message : α
  headers : Headers
  trailers : Headers

/-- A call returning a stream of responses. Iterate with `for res in call do`. -/
structure ServerStreamCall (Res : Type) where
  /-- The response headers; waits for the response to start. -/
  responseHeaders : RpcM Headers
  /-- The next response, or `none` once the stream ended successfully. Throws
      the RPC's error if it failed. -/
  receive : RpcM (Option Res)
  /-- The trailers, once `receive` returned `none` or threw. -/
  responseTrailers : BaseIO Headers
  /-- Abandons the call. -/
  cancel : Async Unit

/-- A call sending a stream of requests for one response. -/
structure ClientStreamCall (Req Res : Type) where
  send : Req → RpcM Unit
  /-- Ends the requests and waits for the response. -/
  closeAndReceive : RpcM Res
  responseHeaders : RpcM Headers
  responseTrailers : BaseIO Headers
  cancel : Async Unit

/-- A call streaming both ways. -/
structure BidiStreamCall (Req Res : Type) where
  send : Req → RpcM Unit
  /-- Ends the requests; responses can still be received. -/
  closeRequest : RpcM Unit
  receive : RpcM (Option Res)
  responseHeaders : RpcM Headers
  responseTrailers : BaseIO Headers
  cancel : Async Unit

namespace ServerStreamCall

@[specialize] protected partial def forIn {β : Type} (s : ServerStreamCall Res) (init : β)
    (f : Res → β → RpcM (ForInStep β)) : RpcM β := do
  match ← s.receive with
  | none => return init
  | some a =>
    match ← f a init with
    | .done b => return b
    | .yield b => s.forIn b f

instance : ForIn RpcM (ServerStreamCall Res) Res where
  forIn s init f := ServerStreamCall.forIn s init f

/-- Receives every remaining response. -/
def toArray (s : ServerStreamCall Res) : RpcM (Array Res) := do
  let mut out := #[]
  for r in s do out := out.push r
  return out

end ServerStreamCall

end Connect
