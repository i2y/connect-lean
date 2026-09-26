import Connect
import ConformanceGen.connectrpc.conformance.v1.service
import ConformanceGen.connectrpc.conformance.v1.config
import ConformanceGen.google.protobuf.any

/-! Helpers shared by the conformance server and client. -/

namespace Conformance

open connectrpc.conformance.v1

/-- Reads a message framed with a four-byte big-endian length, as the
    conformance runner writes them. `none` at end of input. -/
def readFramed (h : IO.FS.Stream) : IO (Option ByteArray) := do
  let size ← h.read 4
  if size.size < 4 then return none
  let n := Connect.Envelope.readLength size[0]! size[1]! size[2]! size[3]!
  let mut buf := ByteArray.empty
  while buf.size < n do
    let more ← h.read (n - buf.size).toUSize
    if more.isEmpty then throw (IO.userError "truncated message on stdin")
    buf := buf ++ more
  return some buf

def writeFramed (h : IO.FS.Stream) (bytes : ByteArray) : IO Unit := do
  h.write ((Connect.Envelope.header 0 bytes.size).extract 1 5)
  h.write bytes
  h.flush

def encode! [Protobuf.ProtoMessage α] (m : α) : ByteArray :=
  match Protobuf.encode m with
  | .ok b => b
  | .error _ => .empty

/-- Packs a message into `google.protobuf.Any`. -/
def packAny [Protobuf.ProtoMessage α] [Connect.Message α] (m : α) : google.protobuf.Any :=
  { type_url := "type.googleapis.com/" ++ Connect.Message.typeName α, value := encode! m }

def detailOfAny (a : google.protobuf.Any) : Connect.ErrorDetail :=
  Connect.ErrorDetail.ofTypeUrl a.type_url a.value

def anyOfDetail (d : Connect.ErrorDetail) : google.protobuf.Any :=
  { type_url := d.typeUrl, value := d.value }

def codeToConnect (c : connectrpc.conformance.v1.Code) : Connect.Code :=
  (Connect.Code.ofGrpc? (Protobuf.Reflection.ReflectEnum.toInt32 c).toNatClampNeg).getD .unknown

def codeOfConnect (c : Connect.Code) : connectrpc.conformance.v1.Code :=
  Protobuf.Reflection.ReflectEnum.fromInt32 c.toGrpc.toInt32

/-- Groups header values by name, in order of first appearance. -/
def headersOf (h : Connect.Headers) : Array Header :=
  h.names.map fun n => { name := n, value := h.getAll n }

def headersFrom (hs : Array Header) : Connect.Headers :=
  hs.foldl (init := Connect.Headers.empty) fun acc h =>
    h.value.foldl (init := acc) fun acc v => acc.add h.name v

end Conformance
