import Connect
import Connect.Http2.Hpack
import Connect.Http2.Frame
import Tests.Harness

/-! HPACK against the examples in RFC 7541 Appendix C, and HTTP/2 framing. -/

namespace Tests.Http2
open Connect.Http2

instance : Repr (Array (UInt16 × Nat)) := ⟨fun a _ => repr a.toList⟩

private def hex (s : String) : ByteArray := Id.run do
  let digits := (s.toList.filter (· != ' ')).toArray
  let v (c : Char) : Nat := if c.isDigit then c.toNat - 48 else c.toNat - 87
  let mut out := ByteArray.empty
  for i in [0:digits.size / 2] do
    out := out.push (v digits[2 * i]! * 16 + v digits[2 * i + 1]!).toUInt8
  return out

private def decodeAll (blocks : List ByteArray) : IO (List (Array (String × String))) := do
  let mut d : Hpack.Decoder := {}
  let mut out := []
  for b in blocks do
    let (hs, d') ← expectOk (Hpack.Decoder.decode d b)
    d := d'
    out := out ++ [hs]
  return out

private def expected : List (Array (String × String)) := [
  #[(":method", "GET"), (":scheme", "http"), (":path", "/"), (":authority", "www.example.com")],
  #[(":method", "GET"), (":scheme", "http"), (":path", "/"), (":authority", "www.example.com"),
    ("cache-control", "no-cache")],
  #[(":method", "GET"), (":scheme", "https"), (":path", "/index.html"),
    (":authority", "www.example.com"), ("custom-key", "custom-value")]]

def tests : List Test := [
  ("integers (C.1)", do
    expectEq (Hpack.encodeInt .empty 5 0 10) ⟨#[10]⟩
    expectEq (Hpack.encodeInt .empty 5 0 1337) ⟨#[31, 154, 10]⟩
    expectEq (Hpack.decodeInt ⟨#[31, 154, 10]⟩ 0 5 |>.toOption) (some (1337, 3))),
  ("requests without Huffman coding (C.3)", do
    let got ← decodeAll [hex "828684410f7777772e6578616d706c652e636f6d",
      hex "828684be58086e6f2d6361636865",
      hex "828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565"]
    expectEq got expected),
  ("requests with Huffman coding (C.4)", do
    let got ← decodeAll [hex "828684418cf1e3c2e5f23a6ba0ab90f4ff",
      hex "828684be5886a8eb10649cbf",
      hex "828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf"]
    expectEq got expected),
  ("Huffman encoding", do
    expectEq (Hpack.huffmanEncode "www.example.com".toUTF8) (hex "f1e3c2e5f23a6ba0ab90f4ff")
    for s in ["", "a", "custom-value", "application/grpc+proto", "\x00\xff ünïcode"] do
      let b := s.toUTF8
      expectEq (Hpack.huffmanDecode (Hpack.huffmanEncode b) |>.toOption) (some b) s),
  ("our encoding decodes to the same headers", do
    let hs := #[(":status", "200"), ("content-type", "application/grpc+proto"),
      ("grpc-status", "0"), ("authorization", "Bearer x"), ("x-custom", "v")]
    let (back, _) ← expectOk (Hpack.Decoder.decode {} (Hpack.encode hs))
    expectEq back hs),
  ("invalid input is rejected", do
    expectError (Hpack.Decoder.decode {} ⟨#[0x80]⟩) "index 0"
    expectError (Hpack.Decoder.decode {} ⟨#[0xff, 0x7f]⟩) "index out of range"
    expectError (Hpack.huffmanDecode ⟨#[0x00]⟩) "padding"
    -- EOS (thirty one-bits) may not appear in a string (RFC 7541 §5.2).
    expectError (Hpack.huffmanDecode ⟨#[0xff, 0xff, 0xff, 0xff]⟩) "EOS"
    -- At most five continuation bytes.
    expectError (Hpack.decodeInt ⟨#[0xff, 0x80, 0x80, 0x80, 0x80, 0x80, 0x00]⟩ 0 7) "long integer"
    -- A table size update after a field, with entries in the table (§4.2).
    expectError (Hpack.Decoder.decode {} ⟨#[0x40, 0x01, 0x61, 0x01, 0x62, 0x20]⟩) "late size update"),
  ("a table size update at the start of a block is accepted", do
    let (hs, d) ← expectOk (Hpack.Decoder.decode {} ⟨#[0x20, 0x40, 0x01, 0x61, 0x01, 0x62]⟩)
    expectEq hs #[("a", "b")]
    expectEq d.maxSize 0
    expectEq d.entries #[])
]

private def frames (bytes : ByteArray) (chunk : Nat) : IO (Array Frame) := do
  let mut r := FrameReader.empty
  let mut out := #[]
  let mut i := 0
  while i < bytes.size do
    r := r.feed (bytes.extract i (i + chunk))
    i := i + chunk
    repeat
      match r.next? 16384 with
      | .ok (some (f, r')) => out := out.push f; r := r'
      | .ok none => break
      | .error code => throw (IO.userError s!"frame error {code}")
  return out

def frameTests : List Test := [
  ("frames survive any chunking", do
    let fs : Array Frame := #[dataFrame 1 "hello".toUTF8 false, dataFrame 3 .empty true,
      settingsFrame #[(SettingId.initialWindowSize, 65535), (SettingId.maxFrameSize, 16384)],
      settingsAck, pingFrame ⟨#[1, 2, 3, 4, 5, 6, 7, 8]⟩ false, windowUpdateFrame 0 1000,
      rstStreamFrame 5 ErrorCode.cancel, goawayFrame 7 ErrorCode.noError "bye"]
    let wire := fs.foldl (fun acc f => acc ++ f.encode) ByteArray.empty
    for chunk in [1, 2, 7, 64, wire.size] do
      let got ← frames wire chunk
      expectEq got.size fs.size s!"chunk {chunk}"
      for (a, b) in got.zip fs do
        expectEq a.type b.type
        expectEq a.flags b.flags
        expectEq a.streamId b.streamId
        expectEq a.payload b.payload),
  ("oversized frames are refused", do
    let big := dataFrame 1 (ByteArray.mk (Array.replicate 20000 0)) false
    match FrameReader.empty.feed big.encode |>.next? 16384 with
    | .error code => expectEq code ErrorCode.frameSizeError
    | _ => throw (IO.userError "expected FRAME_SIZE_ERROR")),
  ("draining after each chunk returns what draining once does", do
    let fs : Array Frame := #[dataFrame 1 "hello".toUTF8 false, settingsAck,
      pingFrame ⟨#[1, 2, 3, 4, 5, 6, 7, 8]⟩ false,
      dataFrame 3 (ByteArray.mk (Array.replicate 20000 0)) false, dataFrame 5 .empty true]
    let wire := fs.foldl (fun acc f => acc ++ f.encode) ByteArray.empty
    let (whole, last) := (FrameReader.empty.feed wire).drain 16384
    expectEq whole.length 3 "frames before the oversized one"
    expect (match last with | .error code => code == ErrorCode.frameSizeError | .ok _ => false)
      "the oversized frame is refused"
    for step in [1, 2, 9, 100, 4096] do
      let mut r := FrameReader.empty
      let mut got : List Frame := []
      let mut refused := false
      let mut i := 0
      while i < wire.size && !refused do
        let (more, next) := (r.feed (wire.extract i (i + step))).drain 16384
        got := got ++ more
        match next with
        | .ok r' => r := r'
        | .error code =>
          expectEq code ErrorCode.frameSizeError
          refused := true
        i := i + step
      expect refused s!"chunks of {step}: refused"
      expectEq got.length whole.length s!"chunks of {step}"
      for (a, b) in got.zip whole do
        expectEq a.type b.type
        expectEq a.streamId b.streamId
        expectEq a.payload b.payload),
  ("header blocks split into CONTINUATION frames", do
    let block := ByteArray.mk ((Array.range 40000).map (·.toUInt8))
    let fs := headerFrames 9 block true 16384
    expectEq fs.size 3
    expectEq fs[0]!.type FrameType.headers
    expect (fs[0]!.hasFlag Flag.endStream) "END_STREAM on HEADERS"
    expect (!fs[0]!.hasFlag Flag.endHeaders) "no END_HEADERS yet"
    expectEq fs[2]!.type FrameType.continuation
    expect (fs[2]!.hasFlag Flag.endHeaders) "END_HEADERS on the last"
    expectEq (fs.foldl (fun acc f => acc ++ f.payload) ByteArray.empty) block),
  ("settings round trip", do
    let ps := #[(SettingId.headerTableSize, 4096), (SettingId.enablePush, 0),
      (SettingId.maxConcurrentStreams, 100)]
    expectEq ((parseSettings (settingsFrame ps).payload).toOption) (some ps)),
  ("padding and priority are removed", do
    -- A padded HEADERS frame with priority: pad length 2, 5 priority bytes.
    let payload : ByteArray := ⟨#[2, 0, 0, 0, 3, 16, 0x82, 0x86, 0, 0]⟩
    let f : Frame := { type := FrameType.headers, flags := Flag.padded ||| Flag.priority ||| Flag.endHeaders,
                       streamId := 1, payload }
    expectEq ((framePayload f).toOption) (some ⟨#[0x82, 0x86]⟩)
    let bad : Frame := { f with payload := ⟨#[9, 0x82]⟩ }
    expect (framePayload bad).toOption.isNone "padding longer than the frame")
]

end Tests.Http2
