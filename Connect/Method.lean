module

public section

/-!
# Methods

What the runtime needs to know about an RPC, independent of its message types:
which service and method it is, how it streams, and whether calling it has side
effects. Generated code builds one `MethodSpec` per RPC.
-/

namespace Connect

/-- How many messages flow each way. -/
inductive StreamType where
  /-- One request, one response. -/
  | unary
  /-- Many requests, one response. -/
  | clientStream
  /-- One request, many responses. -/
  | serverStream
  /-- Many requests and many responses. -/
  | bidiStream
  deriving DecidableEq, Repr, Inhabited, Hashable

namespace StreamType

/-- Whether the client may send more than one message. -/
@[expose] def clientStreams : StreamType → Bool
  | clientStream | bidiStream => true
  | unary | serverStream => false

/-- Whether the server may send more than one message. -/
@[expose] def serverStreams : StreamType → Bool
  | serverStream | bidiStream => true
  | unary | clientStream => false

end StreamType

/-- The `idempotency_level` method option. Connect lets clients call methods
    with no side effects over HTTP GET, which caches and CDNs understand. -/
inductive Idempotency where
  | unknown
  | noSideEffects
  | idempotent
  deriving DecidableEq, Repr, Inhabited, Hashable

/-- Describes one RPC. -/
structure MethodSpec where
  /-- Fully-qualified service name, such as `connectrpc.eliza.v1.ElizaService`. -/
  service : String
  /-- Method name as declared in the proto file, such as `Say`. -/
  name : String
  streamType : StreamType
  idempotency : Idempotency := .unknown
  /-- Fully-qualified request message name. Informational. -/
  requestType : String := ""
  /-- Fully-qualified response message name. Informational. -/
  responseType : String := ""
  deriving Repr, Inhabited, BEq

/-- The URL path of the RPC: `/connectrpc.eliza.v1.ElizaService/Say`. -/
def MethodSpec.procedure (m : MethodSpec) : String :=
  "/" ++ m.service ++ "/" ++ m.name

end Connect
