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

/-- Appends the bytes of `b` from `i` on: as themselves those `keep` accepts,
    the others as `%` and two hex digits. -/
private def encodeFrom (keep : UInt8 → Bool) (b : ByteArray) (i : Nat) (out : String) : String :=
  if h : i < b.size then
    let x := b[i]
    let out :=
      if keep x then out.push (Char.ofNat x.toNat)
      else out.push '%' |>.push (hexDigit (x.toNat / 16)) |>.push (hexDigit (x.toNat % 16))
    encodeFrom keep b (i + 1) out
  else out
termination_by b.size - i

private def encodeWith (keep : UInt8 → Bool) (s : String) : String :=
  encodeFrom keep s.toUTF8 0 ""

/-- The `grpc-message` encoding: printable ASCII except `%` stays as is. -/
def encodeGrpcMessage (s : String) : String :=
  encodeWith (fun b => b ≥ 0x20 && b ≤ 0x7e && b != 0x25) s

/-- URL query encoding: only unreserved characters stay as is. -/
def encodeQuery (s : String) : String :=
  encodeWith (fun b =>
    (b ≥ 0x41 && b ≤ 0x5a) || (b ≥ 0x61 && b ≤ 0x7a) || (b ≥ 0x30 && b ≤ 0x39) ||
    b == 0x2d || b == 0x2e || b == 0x5f || b == 0x7e) s

/-- Decodes `cs` onto `out`. -/
private def decodeChars (plusAsSpace : Bool) : List Char → ByteArray → ByteArray
  | [], out => out
  | '%' :: rest@(h :: l :: rest'), out =>
    match hexValue? h, hexValue? l with
    | some hi, some lo => decodeChars plusAsSpace rest' (out.push (hi * 16 + lo).toUInt8)
    | _, _ => decodeChars plusAsSpace rest (out.push 0x25)
  | c :: rest, out =>
    decodeChars plusAsSpace rest
      (if c == '+' && plusAsSpace then out.push 0x20 else out ++ c.toString.toUTF8)

/-- Percent-decodes to bytes. Malformed escapes are kept literally, as gRPC
    asks of `grpc-message`. `plusAsSpace` applies form encoding. -/
def decodeBytes (s : String) (plusAsSpace : Bool := false) : ByteArray :=
  decodeChars plusAsSpace s.toList .empty

/-- Percent-decodes to a string, replacing invalid UTF-8 as a whole with the input. -/
def decode (s : String) (plusAsSpace : Bool := false) : String :=
  (String.fromUTF8? (decodeBytes s plusAsSpace)).getD s

/-! ### Decoding undoes encoding -/

/-- The characters `encodeFrom` writes for a byte. -/
private def encodeByte (keep : UInt8 → Bool) (x : UInt8) : List Char :=
  if keep x then [Char.ofNat x.toNat]
  else ['%', hexDigit (x.toNat / 16), hexDigit (x.toNat % 16)]

/-- The byte at `i` of `b`, as a list. -/
private theorem drop_toList (b : ByteArray) (i : Nat) (h : i < b.size) :
    b.data.toList.drop i = b[i] :: b.data.toList.drop (i + 1) := by
  rw [List.drop_eq_getElem_cons (by simpa using h)]
  simp [ByteArray.getElem_eq_getElem_data]

private theorem encodeFrom_toList (keep : UInt8 → Bool) (b : ByteArray) (i : Nat) (out : String) :
    (encodeFrom keep b i out).toList =
      out.toList ++ (b.data.toList.drop i).flatMap (encodeByte keep) := by
  fun_induction encodeFrom keep b i out with
  | case1 i out h x out' ih =>
    rw [ih, drop_toList b i h, List.flatMap_cons, ← List.append_assoc]
    congr 1
    simp only [out', encodeByte, x]
    split <;> simp
  | case2 i out h =>
    rw [List.drop_eq_nil_of_le (by simp; omega)]
    simp

private theorem hexValue?_hexDigit : ∀ n < 16, hexValue? (hexDigit n) = some n := by
  decide +kernel

/-- What decoding needs of the bytes an encoding keeps: they are ASCII, not `%`,
    and not `+` when that means a space. -/
private def Safe (keep : UInt8 → Bool) (plusAsSpace : Bool) : Prop :=
  ∀ n < 256, keep n.toUInt8 = true → n < 128 ∧ n ≠ 0x25 ∧ (plusAsSpace = true → n ≠ 0x2b)

/-- An ASCII character is its code point, and is one byte in UTF-8. -/
private theorem ascii : ∀ n < 128, (Char.ofNat n).toNat = n ∧
    String.utf8EncodeChar (Char.ofNat n) = [n.toUInt8] := by
  decide +kernel

private theorem decodeChars_encodeByte (keep : UInt8 → Bool) (p : Bool) (hsafe : Safe keep p)
    (x : UInt8) (rest : List Char) (out : ByteArray) :
    decodeChars p (encodeByte keep x ++ rest) out = decodeChars p rest (out.push x) := by
  have hx := x.toNat_lt
  unfold encodeByte
  split
  · rename_i hk
    obtain ⟨hlt, hpct, hplus⟩ := hsafe x.toNat hx (by simpa using hk)
    obtain ⟨hval, henc⟩ := ascii x.toNat hlt
    have hc : Char.ofNat x.toNat ≠ '%' := fun h => hpct (by rw [← hval, h]; rfl)
    have hsp : (Char.ofNat x.toNat == '+' && p) = false := by
      cases p
      · simp
      · have : Char.ofNat x.toNat ≠ '+' := fun h => hplus rfl (by rw [← hval, h]; rfl)
        simpa using this
    rw [List.singleton_append, decodeChars.eq_3 _ _ _ _ (fun _ _ _ h _ => hc h), hsp]
    congr 1
    simp only [Bool.false_eq_true, ↓reduceIte]
    apply ByteArray.ext
    apply Array.ext'
    simp [Char.toString_eq_singleton, String.toByteArray_singleton, List.utf8Encode_singleton, henc]
  · have h₁ : x.toNat / 16 < 16 := by omega
    have h₂ : x.toNat % 16 < 16 := Nat.mod_lt _ (by decide)
    simp only [List.cons_append, decodeChars, hexValue?_hexDigit _ h₁, hexValue?_hexDigit _ h₂]
    congr 2
    rw [show x.toNat / 16 * 16 + x.toNat % 16 = x.toNat by omega]
    simp

private theorem decodeChars_encodeBytes (keep : UInt8 → Bool) (p : Bool) (hsafe : Safe keep p) :
    ∀ (l : List UInt8) (out : ByteArray),
    decodeChars p (l.flatMap (encodeByte keep)) out = l.foldl ByteArray.push out := by
  intro l
  induction l with
  | nil => intro out; simp [decodeChars]
  | cons x l ih =>
    intro out
    rw [List.flatMap_cons, decodeChars_encodeByte keep p hsafe, ih]
    rfl

private theorem data_foldl_push (l : List UInt8) :
    ∀ out : ByteArray, (l.foldl ByteArray.push out).data.toList = out.data.toList ++ l := by
  induction l with
  | nil => intro out; simp
  | cons x l ih => intro out; simp [ih, ByteArray.data_push]

private theorem decode_encodeWith (keep : UInt8 → Bool) (p : Bool) (hsafe : Safe keep p)
    (s : String) : decode (encodeWith keep s) p = s := by
  have hbytes : decodeBytes (encodeWith keep s) p = s.toUTF8 := by
    unfold decodeBytes encodeWith
    rw [encodeFrom_toList, String.toList_empty, List.nil_append, List.drop_zero,
      decodeChars_encodeBytes keep p hsafe]
    apply ByteArray.ext
    apply Array.ext'
    rw [data_foldl_push]
    rfl
  have hutf8 : String.fromUTF8? s.toUTF8 = some s := by
    simp only [String.fromUTF8?, String.toUTF8_eq_toByteArray, dite_eq_left s.isValidUTF8]
    rfl
  simp only [decode, hbytes, hutf8, Option.getD_some]

/-- Decoding gives back what `encodeGrpcMessage` wrote. -/
theorem decode_encodeGrpcMessage (s : String) : decode (encodeGrpcMessage s) = s :=
  decode_encodeWith _ false (by unfold Safe; decide +kernel) s

/-- Decoding gives back what `encodeQuery` wrote, whether or not `+` means a
    space. -/
theorem decode_encodeQuery (s : String) (plusAsSpace : Bool) :
    decode (encodeQuery s) plusAsSpace = s :=
  decode_encodeWith _ plusAsSpace (by cases plusAsSpace <;> (unfold Safe; decide +kernel)) s

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
