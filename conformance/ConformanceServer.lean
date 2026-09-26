import Connect
import Conformance.Common
import ConformanceGen.connectrpc.conformance.v1.service_connect
import ConformanceGen.connectrpc.conformance.v1.server_compat

/-!
# The conformance server

The runner (`connectconformance --mode server`) starts this program, writes a
`ServerCompatRequest` to its stdin, and reads back a `ServerCompatResponse`
with the port. It then sends RPCs whose requests say what to answer: which
headers, trailers, messages, delays and errors.
-/

open Connect Conformance
open connectrpc.conformance.v1

namespace Conformance.Server

def requestInfo (ctx : Context) (reqs : Array google.protobuf.Any) : ConformancePayload.RequestInfo :=
  { request_headers := headersOf ctx.requestHeaders
    timeout_ms := ctx.timeoutMs.map (·.toInt64)
    requests := reqs }

def sendMetadata (ctx : Context) (headers trailers : Array Header) : RpcM Unit := do
  for h in headers do
    for v in h.value do ctx.addResponseHeader h.name v
  for t in trailers do
    for v in t.value do ctx.addResponseTrailer t.name v

def errorOf (e : Error) (extra : Array google.protobuf.Any) : ConnectError :=
  { code := codeToConnect e.code
    «message» := e.message.getD ""
    details := (e.details ++ extra).map detailOfAny }

def delay (ms : UInt32) : RpcM Unit := do
  if ms > 0 then Std.Async.sleep (Std.Time.Millisecond.Offset.ofNat ms.toNat)

/-- The shared behaviour of unary and client-streaming methods. -/
def unaryResponse (ctx : Context) (d : UnaryResponseDefinition) (reqs : Array google.protobuf.Any) :
    RpcM ConformancePayload := do
  sendMetadata ctx d.response_headers d.response_trailers
  let info := requestInfo ctx reqs
  match d.response with
  | some (.error e) => throw (errorOf e #[packAny info])
  | some (.response_data data) =>
    delay d.response_delay_ms
    return { data, request_info := some info }
  | none =>
    delay d.response_delay_ms
    return { request_info := some info }

def service : ConformanceService where
  unary ctx req := do
    let payload ← unaryResponse ctx (req.response_definition.getD {}) #[packAny req]
    return { payload := some payload }

  idempotentUnary ctx req := do
    let payload ← unaryResponse ctx (req.response_definition.getD {}) #[packAny req]
    return { payload := some payload }

  clientStream ctx requests := do
    let mut reqs := #[]
    let mut definition : Option UnaryResponseDefinition := none
    for req in requests do
      reqs := reqs.push (packAny req)
      if definition.isNone then definition := some (req.response_definition.getD {})
    let payload ← unaryResponse ctx (definition.getD {}) reqs
    return { payload := some payload }

  serverStream ctx req responses := do
    let d := req.response_definition.getD {}
    sendMetadata ctx d.response_headers d.response_trailers
    let info := requestInfo ctx #[packAny req]
    let mut sent := false
    for data in d.response_data do
      delay d.response_delay_ms
      responses.send { payload := some { data, request_info := if sent then none else some info } }
      sent := true
    if let some e := d.error then
      throw (errorOf e (if sent then #[] else #[packAny info]))

  bidiStream ctx requests responses := do
    let mut definition : Option StreamResponseDefinition := none
    let mut fullDuplex := false
    let mut reqs := #[]
    let mut index := 0
    for req in requests do
      if definition.isNone then
        let d := req.response_definition.getD {}
        definition := some d
        sendMetadata ctx d.response_headers d.response_trailers
        fullDuplex := req.full_duplex
      reqs := reqs.push (packAny req)
      if !fullDuplex then continue
      let d := definition.getD {}
      if index ≥ d.response_data.size then break
      delay d.response_delay_ms
      responses.send { payload := some {
        data := d.response_data[index]!, request_info := some (requestInfo ctx #[packAny req]) } }
      index := index + 1
      reqs := #[]
    let some d := definition | return
    let info := requestInfo ctx reqs
    for i in [index:d.response_data.size] do
      delay d.response_delay_ms
      responses.send { payload := some {
        data := d.response_data[i]!, request_info := if i == 0 then some info else none } }
    if let some e := d.error then
      throw (errorOf e (if d.response_data.isEmpty then #[packAny info] else #[]))

end Conformance.Server

def main : IO UInt32 := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  let some bytes ← readFramed stdin | return 0
  let req ← match Protobuf.decodeThe ServerCompatRequest bytes with
    | .ok r => pure r
    | .error _ => throw (IO.userError "cannot decode ServerCompatRequest")
  if req.use_tls then
    IO.eprintln "TLS is not supported"
    return 1
  let limit := req.message_receive_limit.toNat
  let opts : ServerOptions := if limit > 0 then { readMaxBytes := limit } else {}
  let running ← Server.start (Router.empty.register Conformance.Server.service) opts
    { host := "127.0.0.1", port := 0 }
  writeFramed stdout (encode! ({ host := "127.0.0.1", port := running.port.toUInt32 } : ServerCompatResponse))
  running.wait
  return 0
