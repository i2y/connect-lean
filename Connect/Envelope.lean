module

public section

/-!
# Envelopes

Streaming Connect, gRPC and gRPC-Web all frame each message the same way: one
flags byte, a four-byte big-endian length, then the payload.

```
+-------+----------------+-------------------+
| flags | length (BE32)  | payload (length)  |
+-------+----------------+-------------------+
```

The flags say whether the payload is compressed (`0x01`) and whether it ends
the stream: `0x02` marks Connect's end-of-stream message and `0x80` marks
gRPC-Web's trailers.

`parseAt?_encode` is the contract the rest of the library relies on: parsing
the bytes `encode` produced, wherever they sit in a buffer, gives back the same
envelope and the offset right after it.
-/

namespace Connect

/-- A framed message: flags and payload. -/
structure Envelope where
  flags : UInt8
  payload : ByteArray
  deriving Inhabited

namespace Envelope

/-- The payload is compressed with the stream's negotiated compression. -/
@[expose] def compressedFlag : UInt8 := 0x01

/-- Connect: this is the end-of-stream message, a JSON object. -/
@[expose] def endStreamFlag : UInt8 := 0x02

/-- gRPC-Web: this frame carries the trailers, as an HTTP/1-style header block. -/
@[expose] def trailersFlag : UInt8 := 0x80

/-- Length of the prefix before the payload. -/
@[expose] def prefixSize : Nat := 5

/-- Largest payload a four-byte length can describe. -/
@[expose] def maxPayloadSize : Nat := 2 ^ 32 - 1

/-- Whether `flag` is set in `flags`. -/
@[expose] def hasFlag (flags flag : UInt8) : Bool := (flags &&& flag) != 0

def isCompressed (e : Envelope) : Bool := hasFlag e.flags compressedFlag

/-- The five-byte prefix for a payload of `len` bytes. -/
@[expose] def header (flags : UInt8) (len : Nat) : ByteArray :=
  ⟨#[flags, (len / 2 ^ 24).toUInt8, (len / 2 ^ 16).toUInt8, (len / 2 ^ 8).toUInt8, len.toUInt8]⟩

/-- The wire form of an envelope. -/
@[expose] def encode (e : Envelope) : ByteArray :=
  header e.flags e.payload.size ++ e.payload

/-- Reads a big-endian 32-bit length. -/
@[expose] def readLength (b0 b1 b2 b3 : UInt8) : Nat :=
  b0.toNat * 2 ^ 24 + b1.toNat * 2 ^ 16 + b2.toNat * 2 ^ 8 + b3.toNat

/-- The payload length announced by the prefix at `off`, once the prefix has
    arrived. Lets a reader refuse an oversized message before buffering it. -/
@[expose] def peekLength? (bytes : ByteArray) (off : Nat) : Option Nat :=
  if h : off + 5 ≤ bytes.size then
    some (readLength bytes[off + 1] bytes[off + 2] bytes[off + 3] bytes[off + 4])
  else
    none

/-- Parses the envelope starting at `off`. Returns it with the offset just past
    it, or `none` when the buffer does not yet hold the whole envelope. -/
@[expose] def parseAt? (bytes : ByteArray) (off : Nat) : Option (Envelope × Nat) :=
  if h : off + 5 ≤ bytes.size then
    let len := readLength bytes[off + 1] bytes[off + 2] bytes[off + 3] bytes[off + 4]
    if off + 5 + len ≤ bytes.size then
      some ({ flags := bytes[off], payload := bytes.extract (off + 5) (off + 5 + len) },
        off + 5 + len)
    else
      none
  else
    none

/-! ## Encoding and parsing agree -/

@[simp] theorem size_header (flags : UInt8) (len : Nat) : (header flags len).size = 5 := rfl

theorem size_encode (e : Envelope) : e.encode.size = 5 + e.payload.size := by
  simp [encode, ByteArray.size_append]

/-- The four length bytes of `header` decode to the length, for any length a
    frame can carry. -/
theorem readLength_header (n : Nat) (h : n < 2 ^ 32) :
    readLength (n / 2 ^ 24).toUInt8 (n / 2 ^ 16).toUInt8 (n / 2 ^ 8).toUInt8 n.toUInt8 = n := by
  simp only [readLength, Nat.toUInt8_eq, UInt8.toNat_ofNat']
  omega

private theorem getElem_prefix {pre mid rest : ByteArray} {i : Nat} (hi : i < mid.size)
    (h : pre.size + i < (pre ++ mid ++ rest).size) :
    (pre ++ mid ++ rest)[pre.size + i] = mid[i] := by
  rw [ByteArray.getElem_append_left (by simp; omega)]
  rw [ByteArray.getElem_append_right (by omega)]
  simp

/-- Parsing an encoded envelope, preceded by anything and followed by anything,
    yields the envelope and the offset right after it. -/
theorem parseAt?_encode (pre rest : ByteArray) (e : Envelope)
    (h : e.payload.size < 2 ^ 32) :
    parseAt? (pre ++ e.encode ++ rest) pre.size = some (e, pre.size + 5 + e.payload.size) := by
  have hsize : (pre ++ e.encode ++ rest).size = pre.size + 5 + e.payload.size + rest.size := by
    simp [ByteArray.size_append, size_encode]; omega
  unfold parseAt?
  have h5 : pre.size + 5 ≤ (pre ++ e.encode ++ rest).size := by omega
  simp only [h5, ↓reduceDIte]
  -- The four length bytes are the header's.
  have hb : ∀ (i : Nat) (hi : i < 5), (pre ++ e.encode ++ rest)[pre.size + i]'(by omega) =
      (header e.flags e.payload.size)[i]'(by simp; omega) := by
    intro i hi
    rw [getElem_prefix (mid := e.encode) (by rw [size_encode]; omega)]
    simp only [encode]
    rw [ByteArray.getElem_append_left (by simp; omega)]
  have hlen : readLength (pre ++ e.encode ++ rest)[pre.size + 1] (pre ++ e.encode ++ rest)[pre.size + 2]
      (pre ++ e.encode ++ rest)[pre.size + 3] (pre ++ e.encode ++ rest)[pre.size + 4] =
      e.payload.size := by
    rw [hb 1 (by decide), hb 2 (by decide), hb 3 (by decide), hb 4 (by decide)]
    exact readLength_header _ h
  simp only [hlen]
  have hfit : pre.size + 5 + e.payload.size ≤ (pre ++ e.encode ++ rest).size := by omega
  simp only [hfit, ↓reduceIte]
  have hflags : (pre ++ e.encode ++ rest)[pre.size]'(by omega) = e.flags := by
    have := hb 0 (by decide)
    simp only [Nat.add_zero] at this
    rw [this]
    rfl
  have hpayload : (pre ++ e.encode ++ rest).extract (pre.size + 5) (pre.size + 5 + e.payload.size) =
      e.payload := by
    rw [ByteArray.append_assoc, Nat.add_assoc, ByteArray.extract_append_size_add]
    simp only [encode]
    rw [ByteArray.append_assoc]
    have h0 : (5 : Nat) = (header e.flags e.payload.size).size + 0 := rfl
    have h1 : 5 + e.payload.size = (header e.flags e.payload.size).size + e.payload.size := rfl
    rw [h1, h0, ByteArray.extract_append_size_add]
    exact ByteArray.extract_append_eq_left rfl
  simp only [hflags, hpayload]

end Envelope

/-- Reassembles envelopes from a byte stream that arrives in arbitrary chunks. -/
structure EnvelopeReader where
  private buffer : ByteArray := .empty
  /-- Offset of the first unread byte in `buffer`. -/
  private offset : Nat := 0
  deriving Inhabited

namespace EnvelopeReader

/-- A reader that has seen no bytes. -/
def empty : EnvelopeReader := {}

/-- Adds bytes that arrived from the network. -/
def feed (r : EnvelopeReader) (bytes : ByteArray) : EnvelopeReader :=
  if r.offset == 0 then
    { r with buffer := r.buffer ++ bytes }
  else
    -- Drop what was already consumed so the buffer does not grow without bound.
    { buffer := r.buffer.extract r.offset r.buffer.size ++ bytes, offset := 0 }

/-- The next complete envelope, if one has arrived. -/
def next? (r : EnvelopeReader) : Option (Envelope × EnvelopeReader) :=
  match Envelope.parseAt? r.buffer r.offset with
  | some (e, off) => some (e, { r with offset := off })
  | none => none

/-- The length announced by the next envelope's prefix, once it has arrived. -/
def nextLength? (r : EnvelopeReader) : Option Nat :=
  Envelope.peekLength? r.buffer r.offset

/-- Bytes received but not yet returned as an envelope. -/
def pending (r : EnvelopeReader) : Nat := r.buffer.size - r.offset

end EnvelopeReader

end Connect
