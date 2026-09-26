module

public import Lean.Data.Json
public import Connect.Codec
public import Connect.Error
public import Connect.Headers
public import Connect.Envelope

public section

/-!
# Protocols

Connect, gRPC and gRPC-Web share their RPC semantics (methods, codes, streams,
metadata) and differ only in how they put them on HTTP. This module holds those
differences as pure functions: content types, header names, timeouts, and how
each protocol spells the final status of an RPC.

| | Connect unary | Connect streaming | gRPC / gRPC-Web |
|---|---|---|---|
| content type | `application/proto` | `application/connect+proto` | `application/grpc(-web)+proto` |
| body | the message | envelopes | envelopes |
| status | HTTP status + JSON body | end-of-stream envelope (JSON) | `grpc-status` trailer (in an envelope for gRPC-Web) |
| timeout | `connect-timeout-ms` | `connect-timeout-ms` | `grpc-timeout` |
-/

namespace Connect

/-- A wire protocol. -/
inductive Protocol where
  | connect
  | grpc
  | grpcWeb
  deriving DecidableEq, Repr, Inhabited, Hashable

namespace Protocol

def name : Protocol → String
  | connect => "connect"
  | grpc => "grpc"
  | grpcWeb => "grpc-web"

instance : ToString Protocol := ⟨name⟩

end Protocol

/-! ## Content types -/

/-- What a request's content type says about it. -/
structure RequestKind where
  protocol : Protocol
  codec : Codec
  /-- Connect only: whether the body is enveloped (`application/connect+…`). -/
  streaming : Bool
  deriving DecidableEq, Repr

namespace ContentType

/-- Drops parameters such as `; charset=utf-8` and lower-cases. -/
def normalize (ct : String) : String :=
  ((ct.splitOn ";").head!.trimAscii.toString).toLower

private def grpcSuffix? (rest : String) : Option Codec :=
  if rest.isEmpty then some .proto
  else if rest.startsWith "+" then Codec.ofName? (rest.drop 1).toString
  else none

/-- Classifies a request content type. `none` means unsupported, which servers
    answer with 415 Unsupported Media Type. -/
def parse? (ct : String) : Option RequestKind :=
  let ct := normalize ct
  if ct.startsWith "application/grpc-web" then
    (grpcSuffix? (ct.drop "application/grpc-web".length).toString).map fun codec =>
      { protocol := .grpcWeb, codec, streaming := true }
  else if ct.startsWith "application/grpc" then
    (grpcSuffix? (ct.drop "application/grpc".length).toString).map fun codec =>
      { protocol := .grpc, codec, streaming := true }
  else if ct.startsWith "application/connect+" then
    (Codec.ofName? (ct.drop "application/connect+".length).toString).map fun codec =>
      { protocol := .connect, codec, streaming := true }
  else if ct.startsWith "application/" then
    (Codec.ofName? (ct.drop "application/".length).toString).map fun codec =>
      { protocol := .connect, codec, streaming := false }
  else
    none

/-- The content type for a message body of this kind. -/
def render (protocol : Protocol) (codec : Codec) (streaming : Bool) : String :=
  match protocol with
  | .connect => if streaming then s!"application/connect+{codec.name}" else s!"application/{codec.name}"
  | .grpc => s!"application/grpc+{codec.name}"
  | .grpcWeb => s!"application/grpc-web+{codec.name}"

/-- Every content type a server accepts, for the `Accept-Post` header. -/
def acceptPost : String :=
  "application/grpc, application/grpc+proto, application/grpc+json, application/grpc-web, " ++
  "application/grpc-web+proto, application/grpc-web+json, application/proto, application/json, " ++
  "application/connect+proto, application/connect+json"

end ContentType

/-! ## Header names -/

namespace HeaderName
def contentType := "content-type"
def contentEncoding := "content-encoding"
def acceptEncoding := "accept-encoding"
def userAgent := "user-agent"
def connectProtocolVersion := "connect-protocol-version"
def connectTimeout := "connect-timeout-ms"
def connectContentEncoding := "connect-content-encoding"
def connectAcceptEncoding := "connect-accept-encoding"
def grpcTimeout := "grpc-timeout"
def grpcEncoding := "grpc-encoding"
def grpcAcceptEncoding := "grpc-accept-encoding"
def grpcStatus := "grpc-status"
def grpcMessage := "grpc-message"
def grpcStatusDetails := "grpc-status-details-bin"
def te := "te"
/-- Connect unary responses carry trailers as headers with this prefix. -/
def trailerPrefix := "trailer-"
end HeaderName

/-- Headers that describe the transport or protocol rather than the application.
    They are never passed through as user metadata. -/
def isProtocolHeader (name : String) : Bool :=
  let n := Headers.normalize name
  n == "content-type" || n == "content-length" || n == "content-encoding" ||
  n == "accept-encoding" || n == "transfer-encoding" || n == "connection" || n == "te" ||
  n == "host" || n == "keep-alive" || n == "trailer" || n == "upgrade" || n == "date" ||
  n == HeaderName.connectProtocolVersion || n == HeaderName.connectTimeout ||
  n == HeaderName.connectContentEncoding || n == HeaderName.connectAcceptEncoding ||
  n == HeaderName.grpcTimeout || n == HeaderName.grpcEncoding ||
  n == HeaderName.grpcAcceptEncoding || n == HeaderName.grpcStatus ||
  n == HeaderName.grpcMessage || n == HeaderName.grpcStatusDetails

/-- The user metadata in a header block. -/
def userMetadata (h : Headers) : Headers :=
  h.filter fun k _ => !isProtocolHeader k

/-! ## Timeouts -/

namespace Timeout

private def allDigits (s : String) : Bool := !s.isEmpty && s.all Char.isDigit

/-- Parses `connect-timeout-ms`: at most ten digits of milliseconds. -/
def parseConnect? (s : String) : Option Nat :=
  if allDigits s && s.length ≤ 10 then s.toNat? else none

/-- Parses `grpc-timeout`: up to eight digits and a unit (`H`, `M`, `S`, `m`,
    `u`, `n`). Rounds sub-millisecond timeouts up, so a positive timeout never
    becomes zero. -/
def parseGrpc? (s : String) : Option Nat := do
  if s.length < 2 then none
  let unit := s.back
  let digits := (s.dropEnd 1).toString
  unless allDigits digits && digits.length ≤ 8 do none
  let v ← digits.toNat?
  match unit with
  | 'H' => some (v * 3600000)
  | 'M' => some (v * 60000)
  | 'S' => some (v * 1000)
  | 'm' => some v
  | 'u' => some ((v + 999) / 1000)
  | 'n' => some ((v + 999999) / 1000000)
  | _ => none

/-- Renders milliseconds as a `grpc-timeout` value, choosing the finest unit
    that fits in eight digits. -/
def renderGrpc (ms : Nat) : String :=
  if ms < 100000000 then s!"{ms}m"
  else if ms / 1000 < 100000000 then s!"{ms / 1000}S"
  else if ms / 60000 < 100000000 then s!"{ms / 60000}M"
  else s!"{min (ms / 3600000) 99999999}H"

end Timeout

/-! ## Percent-encoding -/

namespace Percent

private def hexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat (48 + n) else Char.ofNat (55 + n)

private def hexValue? (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - 48)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 87)
  else if 'A' ≤ c ∧ c ≤ 'F' then some (c.toNat - 55)
  else none

private def encodeWith (keep : UInt8 → Bool) (s : String) : String := Id.run do
  let mut out := ""
  for b in s.toUTF8 do
    if keep b then out := out.push (Char.ofNat b.toNat)
    else out := out.push '%' |>.push (hexDigit (b.toNat / 16)) |>.push (hexDigit (b.toNat % 16))
  return out

/-- The `grpc-message` encoding: printable ASCII except `%` stays as is. -/
def encodeGrpcMessage (s : String) : String :=
  encodeWith (fun b => b ≥ 0x20 && b ≤ 0x7e && b != 0x25) s

/-- URL query encoding: only unreserved characters stay as is. -/
def encodeQuery (s : String) : String :=
  encodeWith (fun b =>
    (b ≥ 0x41 && b ≤ 0x5a) || (b ≥ 0x61 && b ≤ 0x7a) || (b ≥ 0x30 && b ≤ 0x39) ||
    b == 0x2d || b == 0x2e || b == 0x5f || b == 0x7e) s

/-- Percent-decodes to bytes. Malformed escapes are kept literally, as gRPC
    asks of `grpc-message`. `plusAsSpace` applies form encoding. -/
def decodeBytes (s : String) (plusAsSpace : Bool := false) : ByteArray := Id.run do
  let cs := s.toList.toArray
  let mut out := ByteArray.empty
  let mut i := 0
  while i < cs.size do
    let c := cs[i]!
    if c == '%' && i + 2 < cs.size then
      match hexValue? cs[i + 1]!, hexValue? cs[i + 2]! with
      | some hi, some lo =>
        out := out.push (hi * 16 + lo).toUInt8
        i := i + 3
        continue
      | _, _ => pure ()
    if c == '+' && plusAsSpace then
      out := out.push 0x20
    else
      out := out ++ c.toString.toUTF8
    i := i + 1
  return out

/-- Percent-decodes to a string, replacing invalid UTF-8 as a whole with the input. -/
def decode (s : String) (plusAsSpace : Bool := false) : String :=
  (String.fromUTF8? (decodeBytes s plusAsSpace)).getD s

end Percent

/-! ## URL queries (Connect GET) -/

/-- Splits a raw query string into decoded key/value pairs. -/
def parseQuery (q : String) : Array (String × String) :=
  (q.splitOn "&").toArray.filterMap fun part =>
    if part.isEmpty then none
    else match part.splitOn "=" with
      | [k] => some (Percent.decode k true, "")
      | k :: rest => some (Percent.decode k true, Percent.decode ("=".intercalate rest) true)
      | [] => none

/-- Looks up a raw query parameter's bytes (the message may be binary JSON bytes). -/
def queryParamBytes? (q : String) (key : String) : Option ByteArray :=
  (q.splitOn "&").findSome? fun part =>
    match part.splitOn "=" with
    | k :: rest => if Percent.decode k true == key
        then some (Percent.decodeBytes ("=".intercalate rest) true) else none
    | [] => none

/-! ## gRPC status -/

namespace GrpcStatus

/-! `grpc-status-details-bin` holds a binary `google.rpc.Status`:

```
message Status { int32 code = 1; string message = 2; repeated google.protobuf.Any details = 3; }
message Any { string type_url = 1; bytes value = 2; }
```

The runtime only needs these two tiny messages, so they are encoded here by
hand rather than generated. -/

private def putVarint (out : ByteArray) (n : Nat) : ByteArray := Id.run do
  let mut out := out
  let mut n := n
  while n ≥ 0x80 do
    out := out.push ((n % 0x80) + 0x80).toUInt8
    n := n / 0x80
  return out.push n.toUInt8

private def putField (out : ByteArray) (field : Nat) (payload : ByteArray) : ByteArray :=
  putVarint (putVarint out (field * 8 + 2)) payload.size ++ payload

private def getVarint (b : ByteArray) (i : Nat) : Option (Nat × Nat) := Id.run do
  let mut v := 0
  let mut shift := 0
  let mut i := i
  while i < b.size && shift < 64 do
    let byte := b[i]!.toNat
    v := v + (byte % 0x80) * 2 ^ shift
    i := i + 1
    if byte < 0x80 then return some (v, i)
    shift := shift + 7
  return none

/-- Splits a message into `(field, wireType, value, lengthDelimitedBytes)`
    records, skipping nothing. -/
private partial def fields (b : ByteArray) (i : Nat := 0)
    (acc : Array (Nat × Nat × ByteArray) := #[]) : Option (Array (Nat × Nat × ByteArray)) := do
  if i ≥ b.size then return acc
  let (tag, i) ← getVarint b i
  let field := tag / 8
  match tag % 8 with
  | 0 =>
    let (v, i) ← getVarint b i
    fields b i (acc.push (field, v, .empty))
  | 1 => if i + 8 ≤ b.size then fields b (i + 8) acc else none
  | 2 =>
    let (len, i) ← getVarint b i
    if i + len ≤ b.size then fields b (i + len) (acc.push (field, 0, b.extract i (i + len)))
    else none
  | 5 => if i + 4 ≤ b.size then fields b (i + 4) acc else none
  | _ => none

/-- Encodes an error as a binary `google.rpc.Status`. -/
def encode (e : ConnectError) : ByteArray := Id.run do
  let mut out := putVarint (putVarint .empty 8) e.code.toGrpc
  if !e.message.isEmpty then
    out := putField out 2 e.message.toUTF8
  for d in e.details do
    let any := putField (putField .empty 1 d.typeUrl.toUTF8) 2 d.value
    out := putField out 3 any
  return out

/-- Decodes a binary `google.rpc.Status`: gRPC number, message and details. -/
def decode? (b : ByteArray) : Option (Nat × String × Array ErrorDetail) := do
  let fs ← fields b
  let mut code := 0
  let mut message := ""
  let mut details := #[]
  for (field, v, bytes) in fs do
    if field == 1 then code := v
    else if field == 2 then message := (String.fromUTF8? bytes).getD ""
    else if field == 3 then
      let anyFields ← fields bytes
      let mut url := ""
      let mut value := ByteArray.empty
      for (f, _, bs) in anyFields do
        if f == 1 then url := (String.fromUTF8? bs).getD ""
        else if f == 2 then value := bs
      details := details.push (ErrorDetail.ofTypeUrl url value)
  return (code, message, details)

/-- The gRPC trailers for an RPC's outcome, after the user trailers (which
    should already include any the error carries). -/
def trailers (userTrailers : Headers) (error : Option ConnectError) : Headers :=
  match error with
  | none => userTrailers.set HeaderName.grpcStatus "0"
  | some e =>
    let h := userTrailers.set HeaderName.grpcStatus
      (toString e.code.toGrpc)
    let h := if e.message.isEmpty then h
      else h.set HeaderName.grpcMessage (Percent.encodeGrpcMessage e.message)
    if e.details.isEmpty then h else h.addBin HeaderName.grpcStatusDetails (encode e)

/-- Reads the outcome from gRPC trailers. `none` means success; a missing or
    unparseable `grpc-status` is an `internal` error. -/
def ofTrailers (trailers : Headers) : Option ConnectError :=
  match trailers.get? HeaderName.grpcStatus with
  | none => some { code := .internal, message := "protocol error: no grpc-status trailer",
                   trailers := userMetadata trailers }
  | some "0" => none
  | some s =>
    let message := Percent.decode ((trailers.get? HeaderName.grpcMessage).getD "")
    let code := (s.toNat? >>= Code.ofGrpc?).getD .unknown
    let base : ConnectError := { code, message, trailers := userMetadata trailers }
    match trailers.getBin? HeaderName.grpcStatusDetails >>= decode? with
    | some (_, msg, details) =>
      some { base with message := if msg.isEmpty then message else msg, details }
    | none => some base

/-- A gRPC-Web trailers frame body: one `name: value` line per trailer. -/
def renderTrailerBlock (h : Headers) : ByteArray :=
  String.join (h.entries.toList.map fun (k, v) => s!"{k}: {v}\r\n") |>.toUTF8

/-- Parses a gRPC-Web trailers frame body. -/
def parseTrailerBlock (b : ByteArray) : Headers := Id.run do
  let text := (String.fromUTF8? b).getD ""
  let mut h := Headers.empty
  for line in text.splitOn "\n" do
    let line := (line.trimAsciiEnd.toString)
    if line.isEmpty then continue
    match line.splitOn ":" with
    | k :: rest => h := h.add k.trimAscii.toString (":".intercalate rest).trimAscii.toString
    | [] => pure ()
  return h

end GrpcStatus

/-! ## Connect end-of-stream -/

namespace EndStream

/-- The JSON object that ends a Connect stream: the error, if any, and the
    trailers as `metadata`. -/
def render (trailers : Headers) (error : Option ConnectError) : ByteArray :=
  let metadata := trailers.names.toList.map fun k =>
    (k, Lean.Json.arr ((trailers.getAll k).map Lean.Json.str))
  let fields : List (String × Lean.Json) :=
    (match error with
      | some e => [("error", e.toJson)]
      | none => []) ++
    (if metadata.isEmpty then [] else [("metadata", Lean.Json.mkObj metadata)])
  (Lean.Json.mkObj fields).compress.toUTF8

/-- Parses an end-of-stream message into trailers and the error, if any. -/
def parse (payload : ByteArray) : Except ConnectError (Headers × Option ConnectError) := do
  let some text := String.fromUTF8? payload
    | throw (.internal "protocol error: end-of-stream message is not UTF-8")
  let json ← (Lean.Json.parse text).mapError fun e =>
    ConnectError.internal s!"protocol error: invalid end-of-stream message: {e}"
  let mut trailers := Headers.empty
  if let .ok (.obj kvs) := json.getObjVal? "metadata" then
    for (k, v) in kvs.toArray do
      if let .arr vs := v then
        for x in vs do
          if let .str s := x then trailers := trailers.add k s
  match json.getObjVal? "error" with
  | .ok e@(.obj _) =>
    let err := ConnectError.ofJson e .unknown
    let err : ConnectError := { err with trailers }
    return (trailers, some err)
  | _ => return (trailers, none)

end EndStream

end Connect
