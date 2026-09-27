import Connect
import Tests.Harness

/-! Unit tests for the pure parts: codes, base64, headers, envelopes, errors and
    the protocol helpers. -/

namespace Tests.Core
open Connect

private def bytes (s : String) : ByteArray := s.toUTF8

def codeTests : List Test := [
  ("names round-trip", do
    for c in Code.all do
      expectEq (Code.ofName? c.name) (some c) c.name),
  ("gRPC numbers round-trip", do
    for c in Code.all do
      expectEq (Code.ofGrpc? c.toGrpc) (some c) c.name
    expectEq (Code.ofGrpc? 0) none "OK is not an error"
    expectEq (Code.ofGrpc? 17) none "17"),
  ("HTTP statuses", do
    expectEq Code.unimplemented.httpStatus 501
    expectEq Code.canceled.httpStatus 499
    expectEq (Code.ofHttpStatus 404) .unimplemented
    expectEq (Code.ofHttpStatus 503) .unavailable
    expectEq (Code.ofHttpStatus 418) .unknown)
]

def base64Tests : List Test := [
  ("RFC 4648 vectors", do
    let cases := [("", ""), ("f", "Zg=="), ("fo", "Zm8="), ("foo", "Zm9v"), ("foob", "Zm9vYg=="),
      ("fooba", "Zm9vYmE="), ("foobar", "Zm9vYmFy")]
    for (plain, enc) in cases do
      expectEq (Base64.encode (bytes plain)) enc plain
      expectEq (Base64.decode? enc) (some (bytes plain)) enc),
  ("URL alphabet, unpadded", do
    let b : ByteArray := ⟨#[0xfb, 0xff, 0xfe]⟩
    expectEq (Base64.encode b) "+//+"
    expectEq (Base64.encodeUrl b) "-__-"
    expectEq (Base64.decode? "-__-") (some b)
    expectEq (Base64.decode? "Zm8") (some (bytes "fo"))),
  ("round trip over all lengths", do
    for n in [0:70] do
      let b := ByteArray.mk ((Array.range n).map (fun i => (i * 37 + 11).toUInt8))
      expectEq (Base64.decode? (Base64.encode b)) (some b) s!"std {n}"
      expectEq (Base64.decode? (Base64.encodeUrl b)) (some b) s!"url {n}"),
  ("rejects garbage", do
    expectEq (Base64.decode? "a") none "length 1"
    expectEq (Base64.decode? "ab!c") none "bad char")
]

def headerTests : List Test := [
  ("case-insensitive, multi-valued, ordered", do
    let h := Headers.empty.add "X-Foo" "1" |>.add "x-foo" "2" |>.add "Other" "3"
    expectEq (h.get? "X-FOO") (some "1")
    expectEq (h.getAll "x-foo") #["1", "2"]
    expectEq ((h.set "X-Foo" "9").getAll "x-foo") #["9"]
    expectEq (h.erase "x-foo").size 1
    expectEq h.names #["x-foo", "other"]),
  ("binary headers", do
    let b : ByteArray := ⟨#[0, 1, 2, 255]⟩
    let h := Headers.empty.addBin "trace-bin" b
    expectEq (h.getBin? "trace-bin") (some b))
]

def envelopeTests : List Test := [
  ("encode and parse", do
    let e : Envelope := { flags := 1, payload := bytes "hello" }
    let wire := e.encode
    expectEq wire.size 10
    match Envelope.parseAt? wire 0 with
    | some (e', off) =>
      expectEq e'.flags 1
      expectEq e'.payload (bytes "hello")
      expectEq off 10
    | none => throw (IO.userError "no envelope")),
  ("reassembles envelopes split at every byte", do
    let es : Array Envelope := #[{ flags := 0, payload := bytes "one" },
      { flags := 1, payload := .empty }, { flags := 2, payload := bytes "three!" }]
    let wire := es.foldl (fun acc e => acc ++ e.encode) ByteArray.empty
    let mut r := EnvelopeReader.empty
    let mut got := #[]
    for i in [0:wire.size] do
      r := r.feed (wire.extract i (i + 1))
      while true do
        match r.next? with
        | some (e, r') => got := got.push e; r := r'
        | none => break
    expectEq got.size 3
    for (a, b) in got.zip es do
      expectEq a.flags b.flags
      expectEq a.payload b.payload),
  ("announced length is visible before the payload", do
    let r := EnvelopeReader.empty.feed ((Envelope.encode { flags := 0, payload := ByteArray.mk (Array.replicate 1000 7) }).extract 0 5)
    expectEq r.nextLength? (some 1000)
    expect r.next?.isNone),
  ("draining after each chunk returns what draining once does", do
    let es : Array Envelope := (Array.range 20).map fun i =>
      { flags := (i % 3).toUInt8, payload := ByteArray.mk (Array.replicate (i * 7 % 23) i.toUInt8) }
    let wire := es.foldl (fun acc e => acc ++ e.encode) ByteArray.empty ++ bytes "\x00\x00"
    let (whole, rest) := (EnvelopeReader.empty.feed wire).drain
    expectEq whole.length 20
    expectEq rest.unread (bytes "\x00\x00")
    for step in [1, 2, 3, 5, 8, 13, 100] do
      let mut r := EnvelopeReader.empty
      let mut got : List Envelope := []
      let mut i := 0
      while i < wire.size do
        let (more, r') := (r.feed (wire.extract i (i + step))).drain
        got := got ++ more
        r := r'
        i := i + step
      expectEq got.length whole.length s!"chunks of {step}"
      for (a, b) in got.zip whole do
        expectEq a.flags b.flags
        expectEq a.payload b.payload
      expectEq r.unread rest.unread s!"chunks of {step}")
]

def errorTests : List Test := [
  ("JSON round trip with details", do
    let e : ConnectError := {
      code := .notFound
      «message» := "no such user"
      details := #[{ typeName := "google.rpc.RetryInfo", value := ⟨#[8, 1]⟩ }] }
    let back := ConnectError.ofJson e.toJson .unknown
    expectEq back.code .notFound
    expectEq back.message "no such user"
    expectEq back.details.size 1
    expectEq back.details[0]!.typeName "google.rpc.RetryInfo"
    expectEq back.details[0]!.value ⟨#[8, 1]⟩),
  ("unknown codes fall back", do
    let j := Lean.Json.mkObj [("code", "bogus"), ("message", "x")]
    expectEq (ConnectError.ofJson j .unavailable).code .unavailable),
  ("type URLs", do
    let d := ErrorDetail.ofTypeUrl "type.googleapis.com/google.rpc.BadRequest" .empty
    expectEq d.typeName "google.rpc.BadRequest"
    expectEq d.typeUrl "type.googleapis.com/google.rpc.BadRequest")
]

def protocolTests : List Test := [
  ("content types", do
    let k := ContentType.parse? "application/json; charset=utf-8"
    expectEq k (some { protocol := .connect, codec := .json, streaming := false })
    expectEq (ContentType.parse? "application/connect+proto")
      (some { protocol := .connect, codec := .proto, streaming := true })
    expectEq (ContentType.parse? "application/grpc")
      (some { protocol := .grpc, codec := .proto, streaming := true })
    expectEq (ContentType.parse? "application/grpc-web+json")
      (some { protocol := .grpcWeb, codec := .json, streaming := true })
    expectEq (ContentType.parse? "application/xml") none
    expectEq (ContentType.parse? "text/plain") none
    for p in [Protocol.connect, .grpc, .grpcWeb] do
      for c in [Codec.proto, .json] do
        for s in [false, true] do
          let kind := ContentType.parse? (ContentType.render p c s)
          expectEq (kind.map (·.codec)) (some c) (ContentType.render p c s)
          expectEq (kind.map (·.protocol)) (some p) (ContentType.render p c s)),
  ("timeouts", do
    expectEq (Timeout.parseConnect? "1500") (some 1500)
    expectEq (Timeout.parseConnect? "12345678901") none "11 digits"
    expectEq (Timeout.parseGrpc? "2S") (some 2000)
    expectEq (Timeout.parseGrpc? "1H") (some 3600000)
    expectEq (Timeout.parseGrpc? "1500u") (some 2)
    expectEq (Timeout.parseGrpc? "123456789m") none "9 digits"
    expectEq (Timeout.parseGrpc? "5x") none "unit"
    for ms in [0, 1, 999, 100000000, 5000000000] do
      let r := Timeout.parseGrpc? (Timeout.renderGrpc ms)
      expect (r.isSome && r.get! ≤ ms) s!"grpc timeout {ms}"),
  ("grpc-message percent-encoding", do
    let s := "héllo 100% ✓\n"
    let enc := Percent.encodeGrpcMessage s
    expect (enc.all fun c => c.toNat ≥ 0x20 && c.toNat ≤ 0x7e) "printable"
    expectEq (Percent.decode enc) s
    expectEq (Percent.decode "bad %zz escape") "bad %zz escape"),
  ("gRPC status round trip", do
    let e : ConnectError := {
      code := .resourceExhausted
      «message» := "slow down"
      details := #[{ typeName := "google.rpc.QuotaFailure", value := ⟨#[1, 2, 3]⟩ }] }
    let t := GrpcStatus.trailers (Headers.empty.add "x-extra" "1") (some e)
    expectEq (t.get? "grpc-status") (some "8")
    let parsed : Option ConnectError := GrpcStatus.ofTrailers t
    expect parsed.isSome "expected an error"
    let e' := parsed.get!
    expectEq e'.code .resourceExhausted
    expectEq e'.message "slow down"
    expectEq e'.details.size 1
    expectEq (e'.details.map (·.value)) #[⟨#[1, 2, 3]⟩]
    expectEq (e'.trailers.get? "x-extra") (some "1")
    expect (GrpcStatus.ofTrailers (GrpcStatus.trailers {} none)).isNone "success"
    expectEq ((GrpcStatus.ofTrailers {}).map (·.code)) (some .internal) "missing status"),
  ("gRPC-Web trailer blocks", do
    let h := Headers.empty.add "grpc-status" "0" |>.add "x-a" "b c"
    expectEq (GrpcStatus.parseTrailerBlock (GrpcStatus.renderTrailerBlock h)) h),
  ("Connect end-of-stream", do
    let trailers := Headers.empty.add "x-t" "1" |>.add "x-t" "2"
    let r : Headers × Option ConnectError ←
      expectOk (EndStream.parse (EndStream.render trailers (some (.aborted "conflict"))))
    expectEq (r.1.getAll "x-t") #["1", "2"]
    expect r.2.isSome "expected an error"
    expectEq r.2.get!.code .aborted
    expectEq r.2.get!.message "conflict"
    let r : Headers × Option ConnectError ← expectOk (EndStream.parse (EndStream.render {} none))
    expect r.2.isNone "success end-of-stream"),
  ("query strings", do
    let q := parseQuery "encoding=json&message=%7B%22a%22%3A1%7D&base64=0&plus=a+b"
    expectEq q #[("encoding", "json"), ("message", "{\"a\":1}"), ("base64", "0"), ("plus", "a b")]
    expectEq (queryParamBytes? "x=1&message=%00%FF" "message") (some ⟨#[0, 255]⟩)),
  ("URLs", do
    let ep ← expectOk (Transport.Endpoint.parse "http://localhost:8080/api/")
    expectEq ep.host "localhost"
    expectEq ep.port 8080
    expectEq ep.pathPrefix "/api"
    let ep ← expectOk (Transport.Endpoint.parse "http://[::1]:9000")
    expectEq ep.host "::1"
    expectEq ep.port 9000
    expectError (Transport.Endpoint.parse "ftp://x"))
]

end Tests.Core
