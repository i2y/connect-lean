import Connect
import Conformance.Common
import ConformanceGen.connectrpc.conformance.v1.service_connect
import ConformanceGen.connectrpc.conformance.v1.client_compat

/-!
# The conformance client

The runner (`connectconformance --mode client`) writes `ClientCompatRequest`s to
this program's stdin, one per test case. Each says which RPC to make, how, and
when to cancel it; the program makes the call with `Connect.Client` and writes
back a `ClientCompatResponse` with what it saw.
-/

open Connect Conformance
open connectrpc.conformance.v1

namespace Conformance.Client

/-- What a call observed. -/
structure Outcome where
  headers : Connect.Headers := {}
  trailers : Connect.Headers := {}
  payloads : Array ConformancePayload := #[]
  error : Option ConnectError := none
  unsent : Nat := 0

def decodeAny [Protobuf.ProtoMessage α] (a : google.protobuf.Any) : RpcM α :=
  match Protobuf.decode a.value with
  | .ok m => pure m
  | .error _ => throw (.internal s!"cannot decode request message {a.type_url}")

def delay (ms : UInt32) : RpcM Unit := do
  if ms > 0 then Std.Async.sleep (Std.Time.Millisecond.Offset.ofNat ms.toNat)

/-- Runs one call and records what came back. -/
def call (req : ClientCompatRequest) (client : Connect.Client) (cancel : Std.CancellationContext) :
    Std.Async.Async Outcome := do
  let opts : CallOptions := {
    headers := headersFrom req.request_headers
    timeoutMs := req.timeout_ms.map (·.toNat)
    cancellation := some cancel }
  let cancelTiming := req.cancel.bind (·.cancel_timing)
  let cancelNow : RpcM Unit := cancel.cancel .cancel
  -- Cancels after a delay, once the requests are all sent.
  let cancelAfterClose : RpcM Unit := do
    if let some (.after_close_send_ms ms) := cancelTiming then
      let timer : Std.Async.Async Unit :=
        Std.Async.background (t := Std.Async.AsyncTask) do
          Std.Async.sleep (Std.Time.Millisecond.Offset.ofNat ms.toNat)
          cancel.cancel .cancel
      timer
  let afterResponses (n : Nat) : RpcM Unit := do
    if let some (.after_num_responses k) := cancelTiming then
      if n ≥ k.toNat then cancelNow
  let out ← IO.mkRef ({} : Outcome)
  let record (p : Option ConformancePayload) : RpcM Unit := do
    out.modify fun o => { o with payloads := o.payloads.push (p.getD {}) }
    afterResponses (← out.get).payloads.size
  let method := req.method.getD ""
  let msgs := req.request_messages
  let result ← RpcM.run (show RpcM Unit from do
    match method with
    | "Unary" | "IdempotentUnary" | "Unimplemented" =>
      let some first := msgs[0]? | throw (.internal "no request message")
      cancelAfterClose
      let client := { client with config.useHttpGet := req.use_get_http_method }
      match method with
      | "Unary" =>
        let r ← client.unaryWithMetadata (Res := UnaryResponse) ConformanceService.Spec.unary
          (← decodeAny (α := UnaryRequest) first) opts
        out.modify ({ · with headers := r.headers, trailers := r.trailers })
        record r.message.payload
      | "IdempotentUnary" =>
        let r ← client.unaryWithMetadata (Res := IdempotentUnaryResponse)
          ConformanceService.Spec.idempotentUnary (← decodeAny (α := IdempotentUnaryRequest) first) opts
        out.modify ({ · with headers := r.headers, trailers := r.trailers })
        record r.message.payload
      | _ =>
        let r ← client.unaryWithMetadata (Res := UnimplementedResponse)
          ConformanceService.Spec.unimplemented (← decodeAny (α := UnimplementedRequest) first) opts
        out.modify ({ · with headers := r.headers, trailers := r.trailers })
    | "ServerStream" =>
      let some first := msgs[0]? | throw (.internal "no request message")
      let stream ← client.serverStream (Res := ServerStreamResponse) ConformanceService.Spec.serverStream
        (← decodeAny (α := ServerStreamRequest) first) opts
      cancelAfterClose
      try
        let headers ← stream.responseHeaders
        out.modify ({ · with headers })
        for res in stream do record res.payload
      finally
        let trailers ← stream.responseTrailers
        out.modify ({ · with trailers })
    | "ClientStream" =>
      let stream ← client.clientStream (Req := ClientStreamRequest) (Res := ClientStreamResponse)
        ConformanceService.Spec.clientStream opts
      try
        for m in msgs, i in [0:msgs.size] do
          delay req.request_delay_ms
          try stream.send (← decodeAny m)
          catch e =>
            out.modify ({ · with unsent := msgs.size - i })
            throw e
        if let some (.before_close_send _) := cancelTiming then cancelNow
        -- The timer starts as the request stream closes.
        cancelAfterClose
        let res ← stream.closeAndReceive
        record res.payload
      finally
        try
          let headers ← stream.responseHeaders
          out.modify ({ · with headers })
        catch _ => pure ()
        let trailers ← stream.responseTrailers
        out.modify ({ · with trailers })
    | "BidiStream" =>
      let stream ← client.bidiStream (Req := BidiStreamRequest) (Res := BidiStreamResponse)
        ConformanceService.Spec.bidiStream opts
      let fullDuplex := req.stream_type == .STREAM_TYPE_FULL_DUPLEX_BIDI_STREAM
      try
        for m in msgs, i in [0:msgs.size] do
          delay req.request_delay_ms
          try stream.send (← decodeAny m)
          catch e =>
            out.modify ({ · with unsent := msgs.size - i })
            throw e
          if fullDuplex then
            if let some res ← stream.receive then record res.payload
        if let some (.before_close_send _) := cancelTiming then cancelNow
        stream.closeRequest
        cancelAfterClose
        while true do
          let some res ← stream.receive | break
          record res.payload
      finally
        try
          let headers ← stream.responseHeaders
          out.modify ({ · with headers })
        catch _ => pure ()
        let trailers ← stream.responseTrailers
        out.modify ({ · with trailers })
    | other => throw (.unimplemented s!"unknown method {other}"))
  match result with
  | .ok () => out.get
  | .error e =>
    let o ← out.get
    return { o with
      error := some e
      headers := if o.headers.isEmpty then e.headers else o.headers
      trailers := if o.trailers.isEmpty then e.trailers else o.trailers }

def configFor (req : ClientCompatRequest) : Except String ClientConfig := do
  let protocol ← match req.protocol with
    | .PROTOCOL_CONNECT => pure Protocol.connect
    | .PROTOCOL_GRPC_WEB => pure .grpcWeb
    | .PROTOCOL_GRPC => pure .grpc
    | _ => throw "unsupported protocol"
  let codec ← match req.codec with
    | .CODEC_PROTO => pure Codec.proto
    | .CODEC_JSON => pure .json
    | _ => throw "unsupported codec"
  let sendCompression ← match req.compression with
    | .COMPRESSION_IDENTITY | .COMPRESSION_UNSPECIFIED => pure none
    | .COMPRESSION_GZIP => pure (some Compression.gzip)
    | _ => throw "unsupported compression"
  if !req.server_tls_cert.isEmpty then throw "TLS is not supported"
  let httpVersion ← match req.http_version with
    | .HTTP_VERSION_1 => pure Transport.HttpVersion.http1
    | .HTTP_VERSION_2 => pure .http2
    | _ => throw "unsupported HTTP version"
  let limit := req.message_receive_limit.toNat
  return {
    baseUrl := s!"http://{req.host}:{req.port}", protocol, codec, sendCompression, httpVersion
    readMaxBytes := if limit > 0 then limit else 4 * 1024 * 1024 }

def run (req : ClientCompatRequest) : Std.Async.Async ClientCompatResponse := do
  let fail (msg : String) : ClientCompatResponse :=
    { test_name := req.test_name, result := some (.error { «message» := msg }) }
  let config ← match configFor req with
    | .ok c => pure c
    | .error e => return fail e
  let client ← match ← (Connect.Client.create config).toBaseIO with
    | .ok c => pure c
    | .error e => return fail (toString e)
  let cancel ← Std.CancellationContext.new
  let outcome : Except IO.Error Outcome ←
    try pure (.ok (← call req client cancel)) catch e => pure (.error e)
  match outcome with
  | .error e => return fail (toString e)
  | .ok o =>
    let error : Option Error := o.error.map fun e =>
      { code := codeOfConnect e.code, «message» := some e.message
        details := e.details.map anyOfDetail }
    return { test_name := req.test_name, result := some (.response {
      response_headers := headersOf o.headers
      response_trailers := headersOf o.trailers
      payloads := o.payloads
      error
      num_unsent_requests := o.unsent.toInt32 }) }

end Conformance.Client

def main : IO UInt32 := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  let lock ← Std.Mutex.new ()
  -- Enough concurrency for the runner, without starving the timers of the
  -- tests that measure deadlines.
  let permits ← Std.Semaphore.new 32
  Std.Async.Async.block do
    let mut tasks := #[]
    repeat
      let some bytes ← readFramed stdin | break
      let req ← match Protobuf.decodeThe ClientCompatRequest bytes with
        | .ok r => pure r
        | .error _ => throw (IO.userError "cannot decode ClientCompatRequest")
      Std.Async.await (← permits.acquire)
      tasks := tasks.push (← Std.Async.async (t := Std.Async.AsyncTask) do
        try
          let res ← Conformance.Client.run req
          lock.atomically (writeFramed stdout (encode! res))
        finally
          permits.release)
    for t in tasks do
      let _ ← Std.Async.await t
  return 0
