module

public import Std.Data.HashMap
public import Connect.Codec
public import Connect.Compression
public import Connect.Context
public import Connect.Interceptor

public section

/-!
# Services and routing

Generated code turns a service implementation into a `Service`: a list of
`Method`s whose message types have been erased to bytes. A `Router` maps each
method's URL path to it, and the HTTP layer dispatches through the router.

A method still knows its message types inside, so it applies the interceptors
(see `Connect.Interceptor`) to the typed handler after decoding the request.
-/

namespace Connect

/-- A method implementation with its message types erased. It runs the
    handler inside the given interceptors; the codec decodes requests and
    encodes responses; payloads are already decompressed. -/
inductive MethodImpl where
  | unary (run : Array Interceptor → Context → Codec → ByteArray → RpcM ByteArray)
  | serverStream (run : Array Interceptor → Context → Codec → ByteArray →
      (ByteArray → RpcM Unit) → RpcM Unit)
  | clientStream (run : Array Interceptor → Context → Codec → RpcM (Option ByteArray) →
      RpcM ByteArray)
  | bidiStream (run : Array Interceptor → Context → Codec → RpcM (Option ByteArray) →
      (ByteArray → RpcM Unit) → RpcM Unit)

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
  { spec, impl := .unary fun chain ctx codec bytes => do
      let req ← decodeRequest (α := Req) codec bytes
      encodeResponse codec (← Interceptor.wrapUnary chain handler ctx req) }

/-- A server-streaming method: one request, a stream of responses. -/
def serverStream [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → Req → ResponseStream Res → RpcM Unit) : Method :=
  { spec, impl := .serverStream fun chain ctx codec bytes send => do
      let req ← decodeRequest (α := Req) codec bytes
      Interceptor.wrapServerStream chain handler ctx req
        { send := fun res => do send (← encodeResponse codec res) } }

/-- A client-streaming method: a stream of requests, one response. -/
def clientStream [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → RequestStream Req → RpcM Res) : Method :=
  { spec, impl := .clientStream fun chain ctx codec receive => do
      let requests : RequestStream Req := { receive := do
        match ← receive with
        | none => return none
        | some bytes => return some (← decodeRequest codec bytes) }
      encodeResponse codec (← Interceptor.wrapClientStream chain handler ctx requests) }

/-- A bidirectional-streaming method. -/
def bidiStream [Message Req] [Message Res] (spec : MethodSpec)
    (handler : Context → RequestStream Req → ResponseStream Res → RpcM Unit) : Method :=
  { spec, impl := .bidiStream fun chain ctx codec receive send => do
      let requests : RequestStream Req := { receive := do
        match ← receive with
        | none => return none
        | some bytes => return some (← decodeRequest codec bytes) }
      Interceptor.wrapBidiStream chain handler ctx requests
        { send := fun res => do send (← encodeResponse codec res) } }

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
  /-- Run around every call, the first outermost. Metadata interceptors at the
      front run before the request is read. -/
  interceptors : Array Interceptor := #[]
  /-- Reject Connect requests without `connect-protocol-version: 1`. -/
  requireConnectProtocolHeader : Bool := false

end Connect
