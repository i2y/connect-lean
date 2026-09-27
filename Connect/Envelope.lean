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

/-! ## Parsing and the bytes around an envelope -/

/-- A parsed envelope ends within the buffer, at least five bytes on. -/
theorem le_size_of_parseAt? {b : ByteArray} {off : Nat} {e : Envelope} {n : Nat}
    (h : parseAt? b off = some (e, n)) : off + 5 ≤ n ∧ n ≤ b.size := by
  unfold parseAt? at h
  split at h
  · dsimp only at h
    split at h
    · simp only [Option.some.injEq, Prod.mk.injEq] at h
      omega
    · simp at h
  · simp at h

/-- Parsing at `off` is parsing the bytes from `off` on. -/
theorem parseAt?_extract (b : ByteArray) (off : Nat) :
    parseAt? b off = (parseAt? (b.extract off b.size) 0).map fun (e, n) => (e, off + n) := by
  unfold parseAt?
  by_cases h5 : off + 5 ≤ b.size
  · have h5' : 0 + 5 ≤ (b.extract off b.size).size := by simp; omega
    rw [dite_eq_left h5, dite_eq_left h5']
    simp only [ByteArray.getElem_extract, Nat.add_zero, Nat.zero_add, ByteArray.size_extract,
      Nat.min_self]
    split
    · rename_i hfit
      rw [ite_eq_left (by omega)]
      simp only [Option.map_some, ByteArray.extract_extract, Option.some.injEq, Prod.mk.injEq,
        Envelope.mk.injEq, true_and]
      constructor
      · congr 1 <;> omega
      · omega
    · rw [ite_eq_right (by omega)]
      rfl
  · rw [dite_eq_right h5, dite_eq_right (by simp; omega)]
    rfl

/-- Bytes after an envelope do not change it. -/
theorem parseAt?_append {b : ByteArray} {off : Nat} {e : Envelope} {n : Nat} (more : ByteArray)
    (h : parseAt? b off = some (e, n)) : parseAt? (b ++ more) off = some (e, n) := by
  unfold parseAt? at h ⊢
  split at h
  · rename_i h5
    dsimp only at h
    split at h
    · rename_i hfit
      have h5' : off + 5 ≤ (b ++ more).size := by simp [ByteArray.size_append]; omega
      rw [dite_eq_left h5']
      dsimp only
      simp (disch := omega) only [ByteArray.getElem_append_left]
      rw [ite_eq_left (by simp [ByteArray.size_append]; omega), ← h]
      congr 3
      rw [ByteArray.extract_append, (ByteArray.extract_eq_empty_iff (b := more)).2 (by omega),
        ByteArray.append_empty]
    · simp at h
  · simp at h

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

/-- The length `nextLength?` announces is the size of the payload `next?`
    returns, so a limit checked on the first holds for the second. -/
theorem nextLength?_of_next? {r : EnvelopeReader} {e : Envelope} {r' : EnvelopeReader}
    (h : r.next? = some (e, r')) : r.nextLength? = some e.payload.size := by
  simp only [next?] at h
  split at h
  · rename_i e' off hparse
    simp only [Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, -⟩ := h
    simp only [Envelope.parseAt?] at hparse
    split at hparse
    · rename_i h5
      split at hparse
      · rename_i hfit
        simp only [Option.some.injEq, Prod.mk.injEq] at hparse
        obtain ⟨rfl, -⟩ := hparse
        simp only [nextLength?, Envelope.peekLength?, h5, ↓reduceDIte, ByteArray.size_extract,
          Option.some.injEq]
        omega
      · simp at hparse
    · simp at hparse
  · simp at h

/-! ## How the bytes are split does not matter

The reader holds the bytes it has received but not yet returned (`unread`).
Feeding appends to them (`unread_feed`), `next?` parses them and nothing else
(`next?_eq`), and an envelope that has arrived is not changed by the bytes
after it (`next?_feed`). So the envelopes a reader returns depend only on the
bytes that arrived, not on how the network split them (`drain_feed`). -/

/-- The bytes received but not yet returned as envelopes. -/
def unread (r : EnvelopeReader) : ByteArray := r.buffer.extract r.offset r.buffer.size

theorem size_unread (r : EnvelopeReader) : r.unread.size = r.pending := by
  simp [unread, pending]

@[simp] theorem unread_empty : empty.unread = .empty := by
  simp only [unread, empty]
  exact ByteArray.extract_zero_size

/-- Feeding appends to the unread bytes. -/
theorem unread_feed (r : EnvelopeReader) (bytes : ByteArray) :
    (r.feed bytes).unread = r.unread ++ bytes := by
  unfold feed unread
  split
  · rename_i h
    simp only [beq_iff_eq] at h
    dsimp only
    rw [h, ByteArray.extract_zero_size, ByteArray.extract_zero_size]
  · dsimp only
    rw [ByteArray.extract_zero_size]

/-- `next?` parses the unread bytes: what it returns, and what it leaves
    unread, depend on nothing else. -/
theorem next?_eq (r : EnvelopeReader) :
    r.next?.map (fun (e, r') => (e, r'.unread)) =
      (Envelope.parseAt? r.unread 0).map fun (e, n) => (e, r.unread.extract n r.unread.size) := by
  unfold next? unread
  rw [Envelope.parseAt?_extract r.buffer r.offset]
  cases Envelope.parseAt? (r.buffer.extract r.offset r.buffer.size) 0 with
  | none => rfl
  | some p =>
    obtain ⟨e, n⟩ := p
    simp only [Option.map_some, ByteArray.extract_extract, ByteArray.size_extract, Nat.min_self,
      Option.some.injEq, Prod.mk.injEq, true_and]
    congr 1
    omega

private theorem next?_parseAt? {r r' : EnvelopeReader} {e : Envelope} (h : r.next? = some (e, r')) :
    ∃ n, Envelope.parseAt? r.unread 0 = some (e, n) ∧
      r'.unread = r.unread.extract n r.unread.size := by
  have h₁ := next?_eq r
  rw [h] at h₁
  cases hp : Envelope.parseAt? r.unread 0 with
  | none => simp [hp] at h₁
  | some p =>
    obtain ⟨e', n⟩ := p
    simp only [hp, Option.map_some, Option.some.injEq, Prod.mk.injEq] at h₁
    obtain ⟨rfl, hu⟩ := h₁
    exact ⟨n, rfl, hu⟩

/-- An envelope that has arrived is returned whatever arrives after it, and
    those bytes are left unread after it. -/
theorem next?_feed {r r' : EnvelopeReader} {e : Envelope} (h : r.next? = some (e, r'))
    (bytes : ByteArray) :
    ∃ r'', (r.feed bytes).next? = some (e, r'') ∧ r''.unread = r'.unread ++ bytes := by
  obtain ⟨n, hp, hu⟩ := next?_parseAt? h
  have hn := Envelope.le_size_of_parseAt? hp
  have h₁ := next?_eq (r.feed bytes)
  rw [unread_feed, Envelope.parseAt?_append bytes hp] at h₁
  cases h₂ : (r.feed bytes).next? with
  | none => simp [h₂] at h₁
  | some p =>
    obtain ⟨e', r''⟩ := p
    simp only [h₂, Option.map_some, Option.some.injEq, Prod.mk.injEq] at h₁
    obtain ⟨rfl, hu'⟩ := h₁
    refine ⟨r'', rfl, ?_⟩
    rw [hu', hu, ByteArray.extract_append, ByteArray.size_append,
      show n - r.unread.size = 0 by omega,
      show r.unread.size + bytes.size - r.unread.size = bytes.size by omega,
      ByteArray.extract_zero_size]
    congr 1
    apply ByteArray.ext
    rw [ByteArray.data_extract, ByteArray.data_extract, Array.extract_eq_extract_right]
    simp only [ByteArray.size_data]
    omega

/-- A returned envelope leaves at least five fewer bytes unread. -/
theorem size_unread_next? {r r' : EnvelopeReader} {e : Envelope} (h : r.next? = some (e, r')) :
    r'.unread.size + 5 ≤ r.unread.size := by
  obtain ⟨n, hp, hu⟩ := next?_parseAt? h
  have := Envelope.le_size_of_parseAt? hp
  rw [hu, ByteArray.size_extract]
  omega

/-- Every envelope that has fully arrived, in order, and the reader left. -/
def drain (r : EnvelopeReader) : List Envelope × EnvelopeReader :=
  match h : r.next? with
  | some (e, r') =>
    have := size_unread_next? h
    (e :: (drain r').1, (drain r').2)
  | none => ([], r)
termination_by r.unread.size

theorem drain_of_next?_none {r : EnvelopeReader} (h : r.next? = none) : r.drain = ([], r) := by
  rw [drain]
  split <;> simp_all

theorem drain_of_next?_some {r r' : EnvelopeReader} {e : Envelope} (h : r.next? = some (e, r')) :
    r.drain = (e :: r'.drain.1, r'.drain.2) := by
  rw [drain]
  split <;> simp_all

/-- Draining depends only on the unread bytes. -/
theorem drain_congr {r s : EnvelopeReader} (h : r.unread = s.unread) :
    r.drain.1 = s.drain.1 ∧ r.drain.2.unread = s.drain.2.unread := by
  induction r using drain.induct generalizing s with
  | case1 r e r' hr _ ih =>
    have h₁ := next?_eq s
    rw [← h, ← next?_eq r, hr] at h₁
    cases hs : s.next? with
    | none => simp [hs] at h₁
    | some p =>
      obtain ⟨e', s'⟩ := p
      simp only [hs, Option.map_some, Option.some.injEq, Prod.mk.injEq] at h₁
      obtain ⟨rfl, hu⟩ := h₁
      rw [drain_of_next?_some hr, drain_of_next?_some hs]
      have := ih hu.symm
      simp [this.1, this.2]
  | case2 r hr =>
    have h₁ := next?_eq s
    rw [← h, ← next?_eq r, hr] at h₁
    cases hs : s.next? with
    | none => simp [drain_of_next?_none hr, drain_of_next?_none hs, h]
    | some p => simp [hs] at h₁

/-- Draining, then feeding more bytes and draining again, returns the same
    envelopes, and leaves the same bytes unread, as feeding the bytes first and
    draining once. So by induction, feeding a stream in any number of pieces,
    draining after each, returns what feeding it whole would. -/
theorem drain_feed (r : EnvelopeReader) (bytes : ByteArray) :
    r.drain.1 ++ (r.drain.2.feed bytes).drain.1 = (r.feed bytes).drain.1 ∧
      (r.drain.2.feed bytes).drain.2.unread = (r.feed bytes).drain.2.unread := by
  induction r using drain.induct with
  | case1 r e r' hr _ ih =>
    obtain ⟨t, ht, htu⟩ := next?_feed hr bytes
    have hc := drain_congr (r := r'.feed bytes) (s := t) (by rw [htu, unread_feed])
    rw [drain_of_next?_some hr, drain_of_next?_some ht]
    simp only [List.cons_append, List.cons.injEq, true_and]
    exact ⟨ih.1.trans hc.1, ih.2.trans hc.2⟩
  | case2 r hr =>
    simp [drain_of_next?_none hr]

end EnvelopeReader

end Connect
