module

public import Std.Data.HashMap
public import Connect.Codec
public import Connect.Compression
public import Connect.Server.Context

public section

/-!
# Services and routing

Generated code turns a service implementation into a `Service`: a list of
`Method`s whose message types have been erased to bytes. A `Router` maps each
method's URL path to it, and the HTTP layer dispatches through the router.

Interceptors wrap every call. They see the `Context`, so they fit
authentication, logging and metrics; they can reject a call by throwing.
-/

namespace Connect

/-- A method implementation with its message types erased. The codec decodes
    requests and encodes responses; payloads are already decompressed. -/
inductive MethodImpl where
  | unary (run : Context → Codec → ByteArray → RpcM ByteArray)
  | serverStream (run : Context → Codec → ByteArray → (ByteArray → RpcM Unit) → RpcM Unit)
  | clientStream (run : Context → Codec → RpcM (Option ByteArray) → RpcM ByteArray)
  | bidiStream (run : Context → Codec → RpcM (Option ByteArray) → (ByteArray → RpcM Unit) → RpcM Unit)

/-- One RPC of a service, ready to serve. -/
structure Method where
  spec : MethodSpec
  impl : MethodImpl

namespace Method

private def decodeRequest [Message α] (codec : Codec) (bytes : ByteArray) : RpcM α :=
  RpcM.ofIOExcept (codec.decode bytes)

private def encodeResponse [Message α] (codec : Codec) (msg : α) : RpcM ByteArray :=
  RpcM.ofIOExcept (codec.encode msg)

/-- A unary method: one request, one response. -/
def unary [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → Req → RpcM Res) : Method :=
  { spec, impl := .unary fun ctx codec bytes => do
      let req ← decodeRequest (α := Req) codec bytes
      encodeResponse codec (← handler ctx req) }

/-- A server-streaming method: one request, a stream of responses. -/
def serverStream [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → Req → ResponseStream Res → RpcM Unit) : Method :=
  { spec, impl := .serverStream fun ctx codec bytes send => do
      let req ← decodeRequest (α := Req) codec bytes
      handler ctx req { send := fun res => do send (← encodeResponse codec res) } }

/-- A client-streaming method: a stream of requests, one response. -/
def clientStream [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → RequestStream Req → RpcM Res) : Method :=
  { spec, impl := .clientStream fun ctx codec receive => do
      let requests : RequestStream Req := { receive := do
        match ← receive with
        | none => return none
        | some bytes => return some (← decodeRequest codec bytes) }
      encodeResponse codec (← handler ctx requests) }

/-- A bidirectional-streaming method. -/
def bidiStream [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → RequestStream Req → ResponseStream Res → RpcM Unit) : Method :=
  { spec, impl := .bidiStream fun ctx codec receive send => do
      let requests : RequestStream Req := { receive := do
        match ← receive with
        | none => return none
        | some bytes => return some (← decodeRequest codec bytes) }
      handler ctx requests { send := fun res => do send (← encodeResponse codec res) } }

end Method

/-- A service: a name and its methods. -/
structure Service where
  /-- Fully-qualified service name, such as `connectrpc.eliza.v1.ElizaService`. -/
  name : String
  methods : Array Method

/-- Implementations that can be served. Generated code provides an instance for
    each service's implementation structure. -/
class ToService (σ : Type) where
  toService : σ → Service

instance : ToService Service := ⟨id⟩

/-- Runs around every call a server handles. -/
structure Interceptor where
  /-- Wraps the call. The wrapped action reads the requests, runs the handler
      and writes the responses; the interceptor may run code before and after
      it, catch its error, or throw instead of calling it. -/
  wrap : {α : Type} → Context → RpcM α → RpcM α

namespace Interceptor

/-- Runs `check` before each call; throwing from it rejects the call. -/
def before (check : Context → RpcM Unit) : Interceptor :=
  ⟨fun ctx call => do check ctx; call⟩

/-- Runs `f` after each call with its outcome, then passes the outcome on. -/
def after (f : Context → Option ConnectError → RpcM Unit) : Interceptor :=
  ⟨fun {α} ctx (call : RpcM α) => do
    let r : Except ConnectError α ← tryCatch (Except.ok <$> call) (fun e => pure (.error e))
    match r with
    | .ok a => f ctx none; return a
    | .error e => f ctx (some e); throw e⟩

/-- Applies interceptors to a call, the first one outermost. -/
def applyAll (interceptors : Array Interceptor) (ctx : Context) (call : RpcM α) : RpcM α :=
  interceptors.foldr (fun i acc => i.wrap ctx acc) call

end Interceptor

/-- Maps URL paths to methods. -/
structure Router where
  methods : Std.HashMap String Method := {}
  /-- Names of the registered services, in registration order. -/
  services : Array String := #[]

namespace Router

def empty : Router := {}

/-- Adds every method of a service. A later service replaces an earlier one's
    methods on a path clash. -/
def add (r : Router) (svc : Service) : Router :=
  { methods := svc.methods.foldl (fun m method => m.insert method.spec.procedure method) r.methods
    services := if r.services.contains svc.name then r.services else r.services.push svc.name }

/-- Adds an implementation of a generated service. -/
def register [ToService σ] (r : Router) (impl : σ) : Router :=
  r.add (ToService.toService impl)

def find? (r : Router) (path : String) : Option Method :=
  r.methods[path]?

end Router

/-- Server behaviour shared by every protocol. -/
structure ServerOptions where
  /-- Largest request message accepted, before and after decompression. -/
  readMaxBytes : Nat := 4 * 1024 * 1024
  /-- Compressions offered besides `identity`. -/
  compressions : Array Compression := Compression.defaults
  /-- Responses smaller than this are sent uncompressed. -/
  compressMinBytes : Nat := 0
  /-- Wrap every call, the first one outermost. -/
  interceptors : Array Interceptor := #[]
  /-- Reject Connect requests without `connect-protocol-version: 1`. -/
  requireConnectProtocolHeader : Bool := false

end Connect
