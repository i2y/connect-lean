module

public section

/-!
# HTTP/2 frames

Every HTTP/2 frame (RFC 9113 §4) is a nine-byte header, then a payload:

```
+-----------------------------------------------+
|                 Length (24)                   |
+---------------+---------------+---------------+
|   Type (8)    |   Flags (8)   |
+-+-------------+---------------+-------------------------------+
|R|                 Stream Identifier (31)                      |
+=+=============================================================+
|                   Frame Payload (0...)                      ...
+---------------------------------------------------------------+
```

This module reads and writes that framing, and the payloads of the frame types
the connection handles itself (settings, pings, window updates, resets and
goaways).
-/

namespace Connect.Http2

/-- The client's first bytes on a connection. -/
def preface : ByteArray := "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n".toUTF8

namespace FrameType
def data : UInt8 := 0x0
def headers : UInt8 := 0x1
def priority : UInt8 := 0x2
def rstStream : UInt8 := 0x3
def settings : UInt8 := 0x4
def pushPromise : UInt8 := 0x5
def ping : UInt8 := 0x6
def goaway : UInt8 := 0x7
def windowUpdate : UInt8 := 0x8
def continuation : UInt8 := 0x9
end FrameType

namespace Flag
def endStream : UInt8 := 0x1
def ack : UInt8 := 0x1
def endHeaders : UInt8 := 0x4
def padded : UInt8 := 0x8
def priority : UInt8 := 0x20
end Flag

-- Error codes (§7).
namespace ErrorCode
def noError : UInt32 := 0x0
def protocolError : UInt32 := 0x1
def internalError : UInt32 := 0x2
def flowControlError : UInt32 := 0x3
def settingsTimeout : UInt32 := 0x4
def streamClosed : UInt32 := 0x5
def frameSizeError : UInt32 := 0x6
def refusedStream : UInt32 := 0x7
def cancel : UInt32 := 0x8
def compressionError : UInt32 := 0x9
def connectError : UInt32 := 0xa
def enhanceYourCalm : UInt32 := 0xb
def inadequateSecurity : UInt32 := 0xc
def http11Required : UInt32 := 0xd
end ErrorCode

-- Settings identifiers (§6.5.2).
namespace SettingId
def headerTableSize : UInt16 := 0x1
def enablePush : UInt16 := 0x2
def maxConcurrentStreams : UInt16 := 0x3
def initialWindowSize : UInt16 := 0x4
def maxFrameSize : UInt16 := 0x5
def maxHeaderListSize : UInt16 := 0x6
end SettingId

/-- The largest flow-control window. -/
def maxWindow : Nat := 2 ^ 31 - 1

structure Frame where
  type : UInt8
  flags : UInt8
  streamId : Nat
  payload : ByteArray
  deriving Inhabited

/-- A big-endian 32-bit value at `i`. -/
def getBE32 (b : ByteArray) (i : Nat) : Nat :=
  b[i]!.toNat * 2 ^ 24 + b[i + 1]!.toNat * 2 ^ 16 + b[i + 2]!.toNat * 2 ^ 8 + b[i + 3]!.toNat

namespace Frame

def hasFlag (f : Frame) (flag : UInt8) : Bool := (f.flags &&& flag) != 0

/-- The nine-byte header: length, type, flags, stream. -/
@[expose] def header (f : Frame) : ByteArray :=
  let len := f.payload.size
  let id := f.streamId % 2 ^ 31
  ⟨#[(len / 2 ^ 16 % 256).toUInt8, (len / 2 ^ 8 % 256).toUInt8, (len % 256).toUInt8, f.type, f.flags,
     (id / 2 ^ 24 % 256).toUInt8, (id / 2 ^ 16 % 256).toUInt8, (id / 2 ^ 8 % 256).toUInt8,
     (id % 256).toUInt8]⟩

/-- The frame on the wire. -/
@[expose] def encode (f : Frame) : ByteArray := f.header ++ f.payload

/-- Parses the frame starting at `off`: the frame and the offset just past it,
    `none` while it has not fully arrived, or `FRAME_SIZE_ERROR` when it is
    longer than `maxSize`. -/
@[expose] def parseAt? (b : ByteArray) (off : Nat) (maxSize : Nat) :
    Except UInt32 (Option (Frame × Nat)) :=
  if h : off + 9 ≤ b.size then
    let len := b[off].toNat * 2 ^ 16 + b[off + 1].toNat * 2 ^ 8 + b[off + 2].toNat
    if len > maxSize then .error ErrorCode.frameSizeError
    else if off + 9 + len ≤ b.size then
      .ok (some ({ type := b[off + 3], flags := b[off + 4]
                   streamId := (b[off + 5].toNat * 2 ^ 24 + b[off + 6].toNat * 2 ^ 16 +
                     b[off + 7].toNat * 2 ^ 8 + b[off + 8].toNat) % 2 ^ 31
                   payload := b.extract (off + 9) (off + 9 + len) }, off + 9 + len))
    else .ok none
  else .ok none

@[simp] theorem size_header (f : Frame) : f.header.size = 9 := rfl

/-- A parsed frame is never longer than `maxSize`. -/
theorem parseAt?_size_le {b : ByteArray} {off maxSize : Nat} {f : Frame} {next : Nat}
    (h : parseAt? b off maxSize = .ok (some (f, next))) : f.payload.size ≤ maxSize := by
  unfold parseAt? at h
  split at h
  · dsimp only at h
    split at h
    · simp at h
    · rename_i hle
      split at h
      · simp only [Except.ok.injEq, Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, -⟩ := h
        simp only [ByteArray.size_extract]
        omega
      · simp at h
  · simp at h

private theorem getElem_mid {pre mid rest : ByteArray} {i : Nat} (hi : i < mid.size)
    (h : pre.size + i < (pre ++ mid ++ rest).size) :
    (pre ++ mid ++ rest)[pre.size + i] = mid[i] := by
  rw [ByteArray.getElem_append_left (by simp; omega)]
  rw [ByteArray.getElem_append_right (by omega)]
  simp

/-- Parsing an encoded frame, preceded by anything and followed by anything,
    yields the frame and the offset right after it — for every frame whose
    length and stream fit their fields and whose length is within the limit. -/
theorem parseAt?_encode (pre rest : ByteArray) (f : Frame) (maxSize : Nat)
    (hlen : f.payload.size < 2 ^ 24) (hmax : f.payload.size ≤ maxSize) (hid : f.streamId < 2 ^ 31) :
    parseAt? (pre ++ f.encode ++ rest) pre.size maxSize =
      .ok (some (f, pre.size + 9 + f.payload.size)) := by
  have hsize : (pre ++ f.encode ++ rest).size = pre.size + 9 + f.payload.size + rest.size := by
    simp [ByteArray.size_append, encode]; omega
  have hb : ∀ (i : Nat) (hi : i < 9), (pre ++ f.encode ++ rest)[pre.size + i]'(by omega) =
      f.header[i]'(by simp; omega) := by
    intro i hi
    rw [getElem_mid (mid := f.encode) (by simp [encode, ByteArray.size_append]; omega)]
    simp only [encode]
    rw [ByteArray.getElem_append_left (by simp; omega)]
  unfold parseAt?
  have h9 : pre.size + 9 ≤ (pre ++ f.encode ++ rest).size := by omega
  simp only [h9, ↓reduceDIte]
  have hl : (pre ++ f.encode ++ rest)[pre.size]'(by omega) = (f.payload.size / 2 ^ 16 % 256).toUInt8 := by
    have := hb 0 (by decide)
    simp only [Nat.add_zero] at this
    exact this
  have hl1 : (pre ++ f.encode ++ rest)[pre.size + 1] = (f.payload.size / 2 ^ 8 % 256).toUInt8 :=
    hb 1 (by decide)
  have hl2 : (pre ++ f.encode ++ rest)[pre.size + 2] = (f.payload.size % 256).toUInt8 :=
    hb 2 (by decide)
  have hlenEq : (pre ++ f.encode ++ rest)[pre.size].toNat * 2 ^ 16 +
      (pre ++ f.encode ++ rest)[pre.size + 1].toNat * 2 ^ 8 +
      (pre ++ f.encode ++ rest)[pre.size + 2].toNat = f.payload.size := by
    rw [hl, hl1, hl2]
    simp only [Nat.toUInt8_eq, UInt8.toNat_ofNat']
    omega
  simp only [hlenEq]
  have hnot : ¬ (f.payload.size > maxSize) := by omega
  have hfit : pre.size + 9 + f.payload.size ≤ (pre ++ f.encode ++ rest).size := by omega
  simp only [hnot, hfit, ↓reduceIte]
  have hid' : f.streamId % 2 ^ 31 = f.streamId := Nat.mod_eq_of_lt hid
  have hs5 : (pre ++ f.encode ++ rest)[pre.size + 5] = (f.streamId % 2 ^ 31 / 2 ^ 24 % 256).toUInt8 :=
    hb 5 (by decide)
  have hs6 : (pre ++ f.encode ++ rest)[pre.size + 6] = (f.streamId % 2 ^ 31 / 2 ^ 16 % 256).toUInt8 :=
    hb 6 (by decide)
  have hs7 : (pre ++ f.encode ++ rest)[pre.size + 7] = (f.streamId % 2 ^ 31 / 2 ^ 8 % 256).toUInt8 :=
    hb 7 (by decide)
  have hs8 : (pre ++ f.encode ++ rest)[pre.size + 8] = (f.streamId % 2 ^ 31 % 256).toUInt8 :=
    hb 8 (by decide)
  have hidEq : ((pre ++ f.encode ++ rest)[pre.size + 5].toNat * 2 ^ 24 +
      (pre ++ f.encode ++ rest)[pre.size + 6].toNat * 2 ^ 16 +
      (pre ++ f.encode ++ rest)[pre.size + 7].toNat * 2 ^ 8 +
      (pre ++ f.encode ++ rest)[pre.size + 8].toNat) % 2 ^ 31 = f.streamId := by
    rw [hs5, hs6, hs7, hs8]
    simp only [Nat.toUInt8_eq, UInt8.toNat_ofNat', hid']
    omega
  have htype : (pre ++ f.encode ++ rest)[pre.size + 3] = f.type := hb 3 (by decide)
  have hflags : (pre ++ f.encode ++ rest)[pre.size + 4] = f.flags := hb 4 (by decide)
  have hpayload : (pre ++ f.encode ++ rest).extract (pre.size + 9) (pre.size + 9 + f.payload.size) =
      f.payload := by
    rw [ByteArray.append_assoc, Nat.add_assoc, ByteArray.extract_append_size_add]
    simp only [encode]
    rw [ByteArray.append_assoc]
    have h0 : (9 : Nat) = f.header.size + 0 := rfl
    have h1 : 9 + f.payload.size = f.header.size + f.payload.size := rfl
    rw [h1, h0, ByteArray.extract_append_size_add]
    exact ByteArray.extract_append_eq_left rfl
  simp only [hidEq, htype, hflags, hpayload]

/-! ### Parsing and the bytes around a frame -/

/-- A parsed frame ends within the buffer, at least nine bytes on. -/
theorem le_size_of_parseAt? {b : ByteArray} {off maxSize : Nat} {f : Frame} {n : Nat}
    (h : parseAt? b off maxSize = .ok (some (f, n))) : off + 9 ≤ n ∧ n ≤ b.size := by
  unfold parseAt? at h
  split at h
  · dsimp only at h
    split at h
    · simp at h
    · split at h
      · simp only [Except.ok.injEq, Option.some.injEq, Prod.mk.injEq] at h
        omega
      · simp at h
  · simp at h

/-- Parsing at `off` is parsing the bytes from `off` on. -/
theorem parseAt?_extract (b : ByteArray) (off maxSize : Nat) :
    parseAt? b off maxSize =
      (parseAt? (b.extract off b.size) 0 maxSize).map (Option.map fun (f, n) => (f, off + n)) := by
  unfold parseAt?
  by_cases h9 : off + 9 ≤ b.size
  · have h9' : 0 + 9 ≤ (b.extract off b.size).size := by simp; omega
    rw [dite_eq_left h9, dite_eq_left h9']
    simp only [ByteArray.getElem_extract, Nat.add_zero, Nat.zero_add, ByteArray.size_extract,
      Nat.min_self]
    split
    · rfl
    · split
      · rename_i hfit
        rw [ite_eq_left (by omega)]
        simp only [Except.map, Option.map_some, ByteArray.extract_extract, Except.ok.injEq,
          Option.some.injEq, Prod.mk.injEq, Frame.mk.injEq, true_and]
        constructor
        · congr 1 <;> omega
        · omega
      · rw [ite_eq_right (by omega)]
        rfl
  · rw [dite_eq_right h9, dite_eq_right (by simp; omega)]
    rfl

/-- Bytes after a frame change neither the frame nor the refusal of an
    oversized one. -/
theorem parseAt?_append {b : ByteArray} {off maxSize : Nat} (more : ByteArray)
    (h : parseAt? b off maxSize ≠ .ok none) :
    parseAt? (b ++ more) off maxSize = parseAt? b off maxSize := by
  unfold parseAt? at h ⊢
  by_cases h9 : off + 9 ≤ b.size
  · have h9' : off + 9 ≤ (b ++ more).size := by simp [ByteArray.size_append]; omega
    rw [dite_eq_left h9', dite_eq_left h9]
    rw [dite_eq_left h9] at h
    simp (disch := omega) only [ByteArray.getElem_append_left]
    by_cases hmax : b[off].toNat * 2 ^ 16 + b[off + 1].toNat * 2 ^ 8 + b[off + 2].toNat > maxSize
    · simp only [hmax, ↓reduceIte]
    · simp only [hmax, ↓reduceIte] at h ⊢
      by_cases hfit : off + 9 + (b[off].toNat * 2 ^ 16 + b[off + 1].toNat * 2 ^ 8 +
          b[off + 2].toNat) ≤ b.size
      · have hfit' : off + 9 + (b[off].toNat * 2 ^ 16 + b[off + 1].toNat * 2 ^ 8 +
            b[off + 2].toNat) ≤ (b ++ more).size := by simp [ByteArray.size_append]; omega
        simp only [hfit, hfit', ↓reduceIte]
        congr 4
        rw [ByteArray.extract_append, (ByteArray.extract_eq_empty_iff (b := more)).2 (by omega),
          ByteArray.append_empty]
      · simp only [hfit, ↓reduceIte] at h
        exact absurd rfl h
  · rw [dite_eq_right h9] at h
    exact absurd rfl h

end Frame

/-- Reassembles frames from bytes arriving in arbitrary pieces. -/
structure FrameReader where
  private buffer : ByteArray := .empty
  private offset : Nat := 0
  deriving Inhabited

namespace FrameReader

def empty : FrameReader := {}

def feed (r : FrameReader) (bytes : ByteArray) : FrameReader :=
  if r.offset == 0 then { r with buffer := r.buffer ++ bytes }
  else { buffer := r.buffer.extract r.offset r.buffer.size ++ bytes, offset := 0 }

/-- The next complete frame. Fails when a frame is longer than `maxSize`. -/
def next? (r : FrameReader) (maxSize : Nat) : Except UInt32 (Option (Frame × FrameReader)) := do
  match ← Frame.parseAt? r.buffer r.offset maxSize with
  | some (frame, off) => return some (frame, { r with offset := off })
  | none => return none

/-- A frame the reader returns is never longer than `maxSize`: a longer one is
    refused before its payload is buffered. -/
theorem next?_size_le {r : FrameReader} {maxSize : Nat} {f : Frame} {r' : FrameReader}
    (h : r.next? maxSize = .ok (some (f, r'))) : f.payload.size ≤ maxSize := by
  simp only [next?, bind, Except.bind, pure, Except.pure] at h
  split at h
  · simp at h
  · rename_i res hparse
    split at h
    · rename_i f' off
      simp only [Except.ok.injEq, Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, -⟩ := h
      exact Frame.parseAt?_size_le hparse
    · simp at h

/-! ### How the bytes are split does not matter

As for envelopes (see `EnvelopeReader`): feeding appends to the unread bytes,
`next?` parses them and nothing else, and neither a frame that has arrived nor
the refusal of an oversized one is changed by the bytes after it. So the frames
a reader returns, and whether it refuses one, depend only on the bytes that
arrived (`drain_feed`, `drain_feed_error`). -/

/-- The bytes received but not yet returned as frames. -/
def unread (r : FrameReader) : ByteArray := r.buffer.extract r.offset r.buffer.size

@[simp] theorem unread_empty : empty.unread = .empty := by
  simp only [unread, empty]
  exact ByteArray.extract_zero_size

/-- Feeding appends to the unread bytes. -/
theorem unread_feed (r : FrameReader) (bytes : ByteArray) :
    (r.feed bytes).unread = r.unread ++ bytes := by
  unfold feed unread
  split
  · rename_i h
    simp only [beq_iff_eq] at h
    dsimp only
    rw [h, ByteArray.extract_zero_size, ByteArray.extract_zero_size]
  · dsimp only
    rw [ByteArray.extract_zero_size]

private theorem next?_def (r : FrameReader) (maxSize : Nat) :
    r.next? maxSize = (Frame.parseAt? r.buffer r.offset maxSize).map
      (Option.map fun (f, off) => (f, { r with offset := off })) := by
  simp only [next?, bind, Except.bind, pure, Except.pure]
  cases Frame.parseAt? r.buffer r.offset maxSize with
  | error e => rfl
  | ok o => cases o <;> rfl

/-- `next?` parses the unread bytes: what it returns, and what it leaves
    unread, depend on nothing else. -/
theorem next?_eq (r : FrameReader) (maxSize : Nat) :
    (r.next? maxSize).map (Option.map fun (f, r') => (f, r'.unread)) =
      (Frame.parseAt? r.unread 0 maxSize).map
        (Option.map fun (f, n) => (f, r.unread.extract n r.unread.size)) := by
  rw [next?_def]
  unfold unread
  rw [Frame.parseAt?_extract r.buffer r.offset maxSize]
  cases Frame.parseAt? (r.buffer.extract r.offset r.buffer.size) 0 maxSize with
  | error e => rfl
  | ok o =>
    cases o with
    | none => rfl
    | some p =>
      obtain ⟨f, n⟩ := p
      simp only [Except.map, Option.map_some, ByteArray.extract_extract, ByteArray.size_extract,
        Nat.min_self, Except.ok.injEq, Option.some.injEq, Prod.mk.injEq, true_and]
      congr 1
      omega

private theorem next?_parseAt? {r r' : FrameReader} {maxSize : Nat} {f : Frame}
    (h : r.next? maxSize = .ok (some (f, r'))) :
    ∃ n, Frame.parseAt? r.unread 0 maxSize = .ok (some (f, n)) ∧
      r'.unread = r.unread.extract n r.unread.size := by
  have h₁ := next?_eq r maxSize
  rw [h] at h₁
  cases hp : Frame.parseAt? r.unread 0 maxSize with
  | error e => simp [hp, Except.map] at h₁
  | ok o =>
    cases o with
    | none => simp [hp, Except.map] at h₁
    | some p =>
      obtain ⟨f', n⟩ := p
      simp only [hp, Except.map, Option.map_some, Except.ok.injEq, Option.some.injEq,
        Prod.mk.injEq] at h₁
      obtain ⟨rfl, hu⟩ := h₁
      exact ⟨n, rfl, hu⟩

private theorem next?_error_iff {r : FrameReader} {maxSize : Nat} {code : UInt32} :
    r.next? maxSize = .error code ↔ Frame.parseAt? r.unread 0 maxSize = .error code := by
  have h₁ := next?_eq r maxSize
  constructor
  · intro h
    rw [h] at h₁
    cases hp : Frame.parseAt? r.unread 0 maxSize with
    | error e => simp_all [Except.map]
    | ok o => simp [hp, Except.map] at h₁
  · intro h
    rw [h] at h₁
    cases hn : r.next? maxSize with
    | error e => simp_all [Except.map]
    | ok o => simp [hn, Except.map] at h₁

/-- A frame that has arrived is returned whatever arrives after it, and those
    bytes are left unread after it. -/
theorem next?_feed {r r' : FrameReader} {maxSize : Nat} {f : Frame}
    (h : r.next? maxSize = .ok (some (f, r'))) (bytes : ByteArray) :
    ∃ r'', (r.feed bytes).next? maxSize = .ok (some (f, r'')) ∧
      r''.unread = r'.unread ++ bytes := by
  obtain ⟨n, hp, hu⟩ := next?_parseAt? h
  have hn := Frame.le_size_of_parseAt? hp
  have h₁ := next?_eq (r.feed bytes) maxSize
  rw [unread_feed, Frame.parseAt?_append bytes (by simp [hp]), hp] at h₁
  cases h₂ : (r.feed bytes).next? maxSize with
  | error e => simp [h₂, Except.map] at h₁
  | ok o =>
    cases o with
    | none => simp [h₂, Except.map] at h₁
    | some p =>
      obtain ⟨f', r''⟩ := p
      simp only [h₂, Except.map, Option.map_some, Except.ok.injEq, Option.some.injEq,
        Prod.mk.injEq] at h₁
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

/-- An oversized frame is refused whatever arrives after it. -/
theorem next?_feed_error {r : FrameReader} {maxSize : Nat} {code : UInt32}
    (h : r.next? maxSize = .error code) (bytes : ByteArray) :
    (r.feed bytes).next? maxSize = .error code := by
  rw [next?_error_iff] at h ⊢
  rw [unread_feed, Frame.parseAt?_append bytes (by simp [h]), h]

/-- A returned frame leaves at least nine fewer bytes unread. -/
theorem size_unread_next? {r r' : FrameReader} {maxSize : Nat} {f : Frame}
    (h : r.next? maxSize = .ok (some (f, r'))) : r'.unread.size + 9 ≤ r.unread.size := by
  obtain ⟨n, hp, hu⟩ := next?_parseAt? h
  have := Frame.le_size_of_parseAt? hp
  rw [hu, ByteArray.size_extract]
  omega

/-- Every frame that has fully arrived, in order, and then the reader left,
    or the error refusing an oversized frame. -/
def drain (r : FrameReader) (maxSize : Nat) : List Frame × Except UInt32 FrameReader :=
  match h : r.next? maxSize with
  | .ok (some (f, r')) =>
    have := size_unread_next? h
    (f :: (drain r' maxSize).1, (drain r' maxSize).2)
  | .ok none => ([], .ok r)
  | .error code => ([], .error code)
termination_by r.unread.size

theorem drain_of_next?_some {r r' : FrameReader} {maxSize : Nat} {f : Frame}
    (h : r.next? maxSize = .ok (some (f, r'))) :
    r.drain maxSize = (f :: (r'.drain maxSize).1, (r'.drain maxSize).2) := by
  rw [drain]
  split <;> simp_all

theorem drain_of_next?_none {r : FrameReader} {maxSize : Nat} (h : r.next? maxSize = .ok none) :
    r.drain maxSize = ([], .ok r) := by
  rw [drain]
  split <;> simp_all

theorem drain_of_next?_error {r : FrameReader} {maxSize : Nat} {code : UInt32}
    (h : r.next? maxSize = .error code) : r.drain maxSize = ([], .error code) := by
  rw [drain]
  split <;> simp_all

/-- Draining depends only on the unread bytes. -/
theorem drain_congr {r s : FrameReader} {maxSize : Nat} (h : r.unread = s.unread) :
    (r.drain maxSize).1 = (s.drain maxSize).1 ∧
      (r.drain maxSize).2.map unread = (s.drain maxSize).2.map unread := by
  induction r using drain.induct (maxSize := maxSize) generalizing s with
  | case1 r f r' hr _ ih =>
    have h₁ := next?_eq s maxSize
    rw [← h, ← next?_eq r maxSize, hr] at h₁
    cases hs : s.next? maxSize with
    | error e => simp [hs, Except.map] at h₁
    | ok o =>
      cases o with
      | none => simp [hs, Except.map] at h₁
      | some p =>
        obtain ⟨f', s'⟩ := p
        simp only [hs, Except.map, Option.map_some, Except.ok.injEq, Option.some.injEq,
          Prod.mk.injEq] at h₁
        obtain ⟨rfl, hu⟩ := h₁
        rw [drain_of_next?_some hr, drain_of_next?_some hs]
        have := ih hu.symm
        simp [this.1, this.2]
  | case2 r hr =>
    have h₁ := next?_eq s maxSize
    rw [← h, ← next?_eq r maxSize, hr] at h₁
    cases hs : s.next? maxSize with
    | error e => simp [hs, Except.map] at h₁
    | ok o =>
      cases o with
      | none => simp [drain_of_next?_none hr, drain_of_next?_none hs, Except.map, h]
      | some p => simp [hs, Except.map] at h₁
  | case3 r code hr =>
    have h₁ := next?_eq s maxSize
    rw [← h, ← next?_eq r maxSize, hr] at h₁
    cases hs : s.next? maxSize with
    | error e =>
      simp only [hs, Except.map, Except.error.injEq] at h₁
      subst h₁
      simp [drain_of_next?_error hr, drain_of_next?_error hs]
    | ok o => simp [hs, Except.map] at h₁

/-- Draining, then feeding more bytes and draining again, returns the same
    frames, and leaves the same bytes unread or refuses the same frame, as
    feeding the bytes first and draining once. So by induction, feeding a stream
    in any number of pieces, draining after each, returns what feeding it whole
    would. -/
theorem drain_feed {r r' : FrameReader} {maxSize : Nat} (h : (r.drain maxSize).2 = .ok r')
    (bytes : ByteArray) :
    (r.drain maxSize).1 ++ ((r'.feed bytes).drain maxSize).1 = ((r.feed bytes).drain maxSize).1 ∧
      ((r'.feed bytes).drain maxSize).2.map unread =
        ((r.feed bytes).drain maxSize).2.map unread := by
  induction r using drain.induct (maxSize := maxSize) with
  | case1 r f r₁ hr _ ih =>
    rw [drain_of_next?_some hr] at h ⊢
    obtain ⟨t, ht, htu⟩ := next?_feed hr bytes
    have hc := drain_congr (maxSize := maxSize) (r := r₁.feed bytes) (s := t)
      (by rw [htu, unread_feed])
    rw [drain_of_next?_some ht]
    simp only [List.cons_append, List.cons.injEq, true_and]
    have := ih h
    exact ⟨this.1.trans hc.1, this.2.trans hc.2⟩
  | case2 r hr =>
    rw [drain_of_next?_none hr] at h ⊢
    simp only [Except.ok.injEq] at h
    subst h
    simp
  | case3 r code hr =>
    rw [drain_of_next?_error hr] at h
    simp at h

/-- A stream whose draining refuses a frame refuses it, after the same frames,
    whatever bytes arrive next. -/
theorem drain_feed_error {r : FrameReader} {maxSize : Nat} {code : UInt32}
    (h : (r.drain maxSize).2 = .error code) (bytes : ByteArray) :
    (r.feed bytes).drain maxSize = ((r.drain maxSize).1, .error code) := by
  induction r using drain.induct (maxSize := maxSize) with
  | case1 r f r₁ hr _ ih =>
    rw [drain_of_next?_some hr] at h ⊢
    obtain ⟨t, ht, htu⟩ := next?_feed hr bytes
    have hc := drain_congr (maxSize := maxSize) (r := r₁.feed bytes) (s := t)
      (by rw [htu, unread_feed])
    have := ih h
    rw [this] at hc
    rw [drain_of_next?_some ht]
    obtain ⟨h₁, h₂⟩ := hc
    cases ht' : (t.drain maxSize).2 with
    | error e =>
      rw [ht'] at h₂
      simp only [Except.map, Except.error.injEq] at h₂
      simp [← h₁, h₂]
    | ok t' => simp [ht', Except.map] at h₂
  | case2 r hr =>
    rw [drain_of_next?_none hr] at h
    simp at h
  | case3 r code' hr =>
    rw [drain_of_next?_error hr] at h
    simp only [Except.error.injEq] at h
    subst h
    rw [drain_of_next?_error (next?_feed_error hr bytes), drain_of_next?_error hr]

end FrameReader

/-! ## Payloads -/

/-- The data of a DATA frame, or the header block fragment of a HEADERS frame,
    without padding (and without the priority fields of HEADERS). -/
def framePayload (f : Frame) : Except UInt32 ByteArray := do
  let mut p := f.payload
  let mut padLen := 0
  if f.hasFlag Flag.padded then
    if p.isEmpty then throw ErrorCode.protocolError
    padLen := p[0]!.toNat
    p := p.extract 1 p.size
  if f.type == FrameType.headers && f.hasFlag Flag.priority then
    if p.size < 5 then throw ErrorCode.protocolError
    p := p.extract 5 p.size
  if padLen > p.size then throw ErrorCode.protocolError
  return p.extract 0 (p.size - padLen)

def dataFrame (streamId : Nat) (data : ByteArray) (endStream : Bool) : Frame :=
  { type := FrameType.data, flags := if endStream then Flag.endStream else 0, streamId,
    payload := data }

/-- A header block as HEADERS and CONTINUATION frames of at most `maxSize` bytes. -/
def headerFrames (streamId : Nat) (block : ByteArray) (endStream : Bool) (maxSize : Nat) :
    Array Frame := Id.run do
  let es := if endStream then Flag.endStream else 0
  if block.size ≤ maxSize then
    return #[{ type := FrameType.headers, flags := es ||| Flag.endHeaders, streamId, payload := block }]
  let first : Frame :=
    { type := FrameType.headers, flags := es, streamId, payload := block.extract 0 maxSize }
  let mut frames := #[first]
  let mut i := maxSize
  while i < block.size do
    let j := min block.size (i + maxSize)
    let last := j == block.size
    let flags := if last then Flag.endHeaders else 0
    frames := frames.push
      { type := FrameType.continuation, flags, streamId, payload := block.extract i j }
    i := j
  return frames

def settingsFrame (settings : Array (UInt16 × Nat)) : Frame :=
  let payload := settings.foldl (init := ByteArray.empty) fun out (id, v) =>
    let out := out.push (id >>> 8).toUInt8 |>.push id.toUInt8
    out.push (v / 2 ^ 24 % 256).toUInt8 |>.push (v / 2 ^ 16 % 256).toUInt8
      |>.push (v / 2 ^ 8 % 256).toUInt8 |>.push (v % 256).toUInt8
  { type := FrameType.settings, flags := 0, streamId := 0, payload }

def settingsAck : Frame := { type := FrameType.settings, flags := Flag.ack, streamId := 0, payload := .empty }

def parseSettings (p : ByteArray) : Except UInt32 (Array (UInt16 × Nat)) := do
  if p.size % 6 != 0 then throw ErrorCode.frameSizeError
  let mut out := #[]
  for i in [0:p.size / 6] do
    let o := 6 * i
    let id := (p[o]!.toUInt16 <<< 8) ||| p[o + 1]!.toUInt16
    out := out.push (id, getBE32 p (o + 2))
  return out

def pingFrame (data : ByteArray) (ack : Bool) : Frame :=
  { type := FrameType.ping, flags := if ack then Flag.ack else 0, streamId := 0, payload := data }

def windowUpdateFrame (streamId : Nat) (increment : Nat) : Frame :=
  let v := increment % 2 ^ 31
  { type := FrameType.windowUpdate, flags := 0, streamId,
    payload := ⟨#[(v / 2 ^ 24).toUInt8, (v / 2 ^ 16 % 256).toUInt8, (v / 2 ^ 8 % 256).toUInt8,
      (v % 256).toUInt8]⟩ }

def rstStreamFrame (streamId : Nat) (code : UInt32) : Frame :=
  let v := code.toNat
  { type := FrameType.rstStream, flags := 0, streamId,
    payload := ⟨#[(v / 2 ^ 24).toUInt8, (v / 2 ^ 16 % 256).toUInt8, (v / 2 ^ 8 % 256).toUInt8,
      (v % 256).toUInt8]⟩ }

def goawayFrame (lastStreamId : Nat) (code : UInt32) (debug : String := "") : Frame :=
  let l := lastStreamId % 2 ^ 31
  let c := code.toNat
  { type := FrameType.goaway, flags := 0, streamId := 0,
    payload := ⟨#[(l / 2 ^ 24).toUInt8, (l / 2 ^ 16 % 256).toUInt8, (l / 2 ^ 8 % 256).toUInt8,
      (l % 256).toUInt8, (c / 2 ^ 24).toUInt8, (c / 2 ^ 16 % 256).toUInt8,
      (c / 2 ^ 8 % 256).toUInt8, (c % 256).toUInt8]⟩ ++ debug.toUTF8 }

end Connect.Http2
