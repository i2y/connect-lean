import Connect.Compression.Gzip
import Tests.Harness

namespace Tests.Gzip
open Connect

private def bytes (s : String) : ByteArray := s.toUTF8

private def sample : ByteArray := Id.run do
  let mut b := ByteArray.empty
  for i in [0:20000] do
    b := b.push ((i * 7 + i / 13) % 251).toUInt8
  return b

private def text : ByteArray :=
  bytes (String.join (List.replicate 200 "Connect is a slim library for building browser and gRPC-compatible HTTP APIs. "))

/-- Runs a shell pipeline with `input` on stdin and returns its stdout. -/
private def pipe (cmd : String) (args : Array String) (input : ByteArray) : IO ByteArray := do
  let child ← IO.Process.spawn { cmd, args, stdin := .piped, stdout := .piped, stderr := .inherit }
  let (stdin, child) ← child.takeStdin
  stdin.write input
  stdin.flush
  let _ := stdin
  let out ← child.stdout.readBinToEnd
  let code ← child.wait
  unless code == 0 do throw (IO.userError s!"{cmd} exited with {code}")
  return out

private def roundTrip (data : ByteArray) : IO Unit := do
  let z := Gzip.compress data
  let back ← expectOk (Gzip.decompress z) "decompress"
  expect (back == data) s!"round trip changed {data.size} bytes"

def tests : List Test := [
  ("crc32 of known input", do
    expectEq (Gzip.crc32 (bytes "123456789")) 0xcbf43926 "crc32"),
  ("round trip: empty", roundTrip .empty),
  ("round trip: one byte", roundTrip (bytes "a")),
  ("round trip: text", roundTrip text),
  ("round trip: pseudo-random bytes", roundTrip sample),
  ("compresses repetitive text", do
    let z := Gzip.compress text
    expect (z.size * 10 < text.size) s!"compressed {text.size} to {z.size}"),
  ("system gzip reads our output", do
    let out ← pipe "gzip" #["-dc"] (Gzip.compress text)
    expect (out == text) "gzip -dc disagreed"),
  ("we read system gzip output (dynamic Huffman)", do
    for level in ["-1", "-6", "-9"] do
      let z ← pipe "gzip" #["-c", level] text
      let back ← expectOk (Gzip.decompress z) s!"decompress gzip {level}"
      expect (back == text) s!"gzip {level} round trip"
    let z ← pipe "gzip" #["-c"] sample
    let back ← expectOk (Gzip.decompress z) "decompress random"
    expect (back == sample) "random round trip"),
  ("concatenated members", do
    let z := Gzip.compress (bytes "hello, ") ++ Gzip.compress (bytes "world")
    let back ← expectOk (Gzip.decompress z)
    expect (back == bytes "hello, world") "members"),
  ("output limit is enforced", do
    let z := Gzip.compress text
    expectError (Gzip.decompress z (limit := 100)) "limit"),
  ("corrupt input is rejected", do
    let z := Gzip.compress text
    let bad := z.set! 20 (z[20]! ^^^ 0xff)
    expectError (Gzip.decompress bad) "corrupt"
    expectError (Gzip.decompress (bytes "not gzip at all")) "garbage")
]

end Tests.Gzip
