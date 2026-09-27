module

public section

/-!
# gzip in Lean

A self-contained implementation of gzip (RFC 1952) over DEFLATE (RFC 1951), so
the library needs no native zlib.

* **Decompression** accepts every DEFLATE stream: stored, fixed-Huffman and
  dynamic-Huffman blocks. It follows zlib's reference decoder, `puff.c`,
  including its checks for over-subscribed and incomplete codes.
* **Compression** finds repeats with a hash table (LZ77, 32 KiB window) and
  writes them with the fixed Huffman code. When that would be larger than the
  input, it writes stored blocks instead.

Decompression takes a limit on the output size and fails as soon as the output
would exceed it, so a small malicious payload cannot expand without bound.
-/

namespace Connect.Gzip

/-- Why decompression failed. -/
inductive Error where
  /-- The output would exceed the caller's limit. -/
  | limitExceeded
  /-- The input is not valid gzip or DEFLATE data. -/
  | invalid (reason : String)
  deriving Repr, BEq, Inhabited

instance : ToString Error where
  toString
    | .limitExceeded => "gzip: decompressed size exceeds the limit"
    | .invalid reason => s!"gzip: {reason}"

/-! ## CRC-32 -/

private def crcTable : Array UInt32 := Id.run do
  let mut table := Array.emptyWithCapacity 256
  for n in [0:256] do
    let mut c := n.toUInt32
    for _ in [0:8] do
      c := if c &&& 1 != 0 then (0xedb88320 : UInt32) ^^^ (c >>> 1) else c >>> 1
    table := table.push c
  return table

/-- CRC-32 (the gzip/zlib polynomial) of `data`, continuing from `crc`. -/
def crc32 (data : ByteArray) (crc : UInt32 := 0) : UInt32 := Id.run do
  let table := crcTable
  let mut c := crc ^^^ 0xffffffff
  for b in data do
    c := table[((c ^^^ b.toUInt32) &&& 0xff).toNat]! ^^^ (c >>> 8)
  return c ^^^ 0xffffffff

/-! ## Shared DEFLATE tables -/

/-- Base lengths for length symbols 257..285. -/
private def lengthBase : Array Nat :=
  #[3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
    131, 163, 195, 227, 258]

private def lengthExtra : Array Nat :=
  #[0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]

/-- Base distances for distance symbols 0..29. -/
private def distBase : Array Nat :=
  #[1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
    2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]

private def distExtra : Array Nat :=
  #[0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12,
    13, 13]

/-- Code lengths of the fixed literal/length code (RFC 1951 §3.2.6). -/
private def fixedLitLengths : Array Nat :=
  (Array.replicate 144 8) ++ (Array.replicate 112 9) ++ (Array.replicate 24 7) ++
    (Array.replicate 8 8)

private def maxBits : Nat := 15

/-! ## Decompression -/

/-- Reads bits least-significant first, as DEFLATE packs them. -/
private structure BitReader where
  input : ByteArray
  pos : Nat
  buf : UInt64
  cnt : Nat

private abbrev DecodeM := Except Error

@[inline] private def BitReader.fill (br : BitReader) : BitReader := Id.run do
  let mut br := br
  while br.cnt ≤ 56 && br.pos < br.input.size do
    br := { br with
      buf := br.buf ||| (br.input[br.pos]!.toUInt64 <<< br.cnt.toUInt64)
      pos := br.pos + 1
      cnt := br.cnt + 8 }
  return br

/-- Takes `n ≤ 32` bits. -/
@[inline] private def BitReader.bits (br : BitReader) (n : Nat) : DecodeM (Nat × BitReader) := do
  let br := if br.cnt < n then br.fill else br
  if br.cnt < n then throw (.invalid "unexpected end of compressed data")
  let v := (br.buf &&& ((1 <<< n.toUInt64) - 1)).toNat
  return (v, { br with buf := br.buf >>> n.toUInt64, cnt := br.cnt - n })

/-- Drops the bits left in the current byte and returns whole buffered bytes
    to the input, leaving the reader on a byte boundary. -/
private def BitReader.alignToByte (br : BitReader) : BitReader :=
  { br with pos := br.pos - br.cnt / 8, buf := 0, cnt := 0 }

/-- A canonical Huffman code in `puff.c`'s form: how many codes have each
    length, and the symbols ordered by code. -/
private structure Huffman where
  count : Array Nat
  symbol : Array Nat

/-- Builds the code for `lengths`. The second component is `puff.c`'s `left`:
    negative for an over-subscribed code, positive for an incomplete one. -/
private def Huffman.build (lengths : Array Nat) : Huffman × Int := Id.run do
  let mut count := Array.replicate (maxBits + 1) 0
  for len in lengths do
    count := count.modify len (· + 1)
  if count[0]! == lengths.size then
    return ({ count, symbol := #[] }, 0)
  let mut left : Int := 1
  for len in [1:maxBits + 1] do
    left := left * 2 - count[len]!
    if left < 0 then return ({ count, symbol := #[] }, left)
  let mut offs := Array.replicate (maxBits + 1) 0
  for len in [1:maxBits] do
    offs := offs.set! (len + 1) (offs[len]! + count[len]!)
  let mut symbol := Array.replicate lengths.size 0
  for sym in [0:lengths.size] do
    let len := lengths[sym]!
    if len != 0 then
      symbol := symbol.set! offs[len]! sym
      offs := offs.modify len (· + 1)
  return ({ count, symbol }, left)

/-- Decodes one symbol. -/
@[inline] private def Huffman.decode (h : Huffman) (br : BitReader) : DecodeM (Nat × BitReader) := do
  let br := if br.cnt < maxBits then br.fill else br
  let mut code := 0
  let mut first := 0
  let mut index := 0
  for len in [1:maxBits + 1] do
    if br.cnt < len then throw (.invalid "unexpected end of compressed data")
    code := code ||| ((br.buf >>> (len - 1).toUInt64) &&& 1).toNat
    let count := h.count[len]!
    if code < first + count then
      return (h.symbol[index + (code - first)]!,
        { br with buf := br.buf >>> len.toUInt64, cnt := br.cnt - len })
    index := index + count
    first := (first + count) * 2
    code := code * 2
  throw (.invalid "invalid Huffman code")

private def fixedLitCode : Huffman := (Huffman.build fixedLitLengths).1
private def fixedDistCode : Huffman := (Huffman.build (Array.replicate 30 5)).1

/-- Output that holds at most `limit` bytes. Everything that adds to it checks
    first, so the type records that no step of decompression ever holds more. -/
private abbrev Out (limit : Nat) := { out : ByteArray // out.size ≤ limit }

/-- Appends `n` bytes copied from `start` on (the copy may read bytes it has
    just appended). -/
private def copyBack (out : ByteArray) (start : Nat) : (n : Nat) → ByteArray
  | 0 => out
  | n + 1 => copyBack (out.push out[start]!) (start + 1) n

private theorem size_copyBack (out : ByteArray) (start n : Nat) :
    (copyBack out start n).size = out.size + n := by
  induction n generalizing out start with
  | zero => simp [copyBack]
  | succ n ih => simp only [copyBack, ih, ByteArray.size_push]; omega

/-- Decodes the literal/length and distance symbols of one block. Every symbol
    but the last adds at least a byte, so `fuel` of `limit - out.size + 1` is
    never exhausted before the limit is. -/
private def inflateCodes (lit dist : Huffman) (limit : Nat) :
    (fuel : Nat) → BitReader → Out limit → DecodeM (BitReader × Out limit)
  | 0, _, _ => throw .limitExceeded
  | fuel + 1, br, out => do
    let (sym, br) ← lit.decode br
    if sym < 256 then
      if h : out.val.size ≥ limit then throw .limitExceeded
      else inflateCodes lit dist limit fuel br ⟨out.val.push sym.toUInt8, by simp; omega⟩
    else if sym == 256 then
      return (br, out)
    else
      let sym := sym - 257
      if sym ≥ 29 then throw (.invalid "invalid length symbol")
      let (extra, br) ← br.bits lengthExtra[sym]!
      let len := lengthBase[sym]! + extra
      let (dsym, br) ← dist.decode br
      if dsym ≥ 30 then throw (.invalid "invalid distance symbol")
      let (dextra, br) ← br.bits distExtra[dsym]!
      let d := distBase[dsym]! + dextra
      if d > out.val.size then throw (.invalid "distance too far back")
      if h : out.val.size + len > limit then throw .limitExceeded
      else
        inflateCodes lit dist limit fuel br
          ⟨copyBack out.val (out.val.size - d) len, by rw [size_copyBack]; omega⟩

/-- The order in which code-length code lengths are sent. -/
private def codeLengthOrder : Array Nat :=
  #[16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

/-- Reads the code descriptions of a dynamic block. -/
private def readDynamicCodes (br : BitReader) : DecodeM (Huffman × Huffman × BitReader) := do
  let (nlen, br) ← br.bits 5
  let (ndist, br) ← br.bits 5
  let (ncode, br) ← br.bits 4
  let nlen := nlen + 257
  let ndist := ndist + 1
  let ncode := ncode + 4
  if nlen > 286 || ndist > 30 then throw (.invalid "bad dynamic block counts")
  let mut br := br
  let mut clens := Array.replicate 19 0
  for i in [0:ncode] do
    let (v, br') ← br.bits 3
    br := br'
    clens := clens.set! codeLengthOrder[i]! v
  let (clcode, left) := Huffman.build clens
  if left != 0 then throw (.invalid "incomplete code-length code")
  let mut lengths : Array Nat := Array.emptyWithCapacity (nlen + ndist)
  while lengths.size < nlen + ndist do
    let (sym, br') ← clcode.decode br
    br := br'
    if sym < 16 then
      lengths := lengths.push sym
    else
      let (prev, reps, br') ← match sym with
        | 16 => do
          if lengths.isEmpty then throw (.invalid "repeat with no previous length")
          let (r, br') ← br.bits 2
          pure (lengths.back!, 3 + r, br')
        | 17 => do
          let (r, br') ← br.bits 3
          pure (0, 3 + r, br')
        | _ => do
          let (r, br') ← br.bits 7
          pure (0, 11 + r, br')
      br := br'
      if lengths.size + reps > nlen + ndist then throw (.invalid "too many code lengths")
      for _ in [0:reps] do
        lengths := lengths.push prev
  let litLengths := lengths.extract 0 nlen
  let distLengths := lengths.extract nlen (nlen + ndist)
  if litLengths[256]! == 0 then throw (.invalid "missing end-of-block code")
  let (lit, left) := Huffman.build litLengths
  if left < 0 || (left > 0 && nlen != lit.count[0]! + lit.count[1]!) then
    throw (.invalid "bad literal/length code")
  let (dist, left) := Huffman.build distLengths
  if left < 0 || (left > 0 && ndist != dist.count[0]! + dist.count[1]!) then
    throw (.invalid "bad distance code")
  return (lit, dist, br)

private theorem size_copySlice (src dest : ByteArray) (srcOff len : Nat)
    (h : srcOff + len ≤ src.size) :
    (src.copySlice srcOff dest dest.size len).size = dest.size + len := by
  simp only [ByteArray.copySlice, ByteArray.size, Array.size_append, Array.size_extract]
  simp only [ByteArray.size] at h
  omega

/-- Copies a stored block. -/
private def inflateStored (limit : Nat) (br : BitReader) (out : Out limit) :
    DecodeM (BitReader × Out limit) := do
  let br := br.alignToByte
  let input := br.input
  let p := br.pos
  if p + 4 > input.size then throw (.invalid "unexpected end of compressed data")
  let len := input[p]!.toNat ||| (input[p + 1]!.toNat <<< 8)
  let nlen := input[p + 2]!.toNat ||| (input[p + 3]!.toNat <<< 8)
  if len != (nlen ^^^ 0xffff) then throw (.invalid "stored block length mismatch")
  if hin : p + 4 + len > input.size then throw (.invalid "unexpected end of compressed data")
  else if h : out.val.size + len > limit then throw .limitExceeded
  else
    let copied := input.copySlice (p + 4) out.val out.val.size len
    return ({ br with pos := p + 4 + len },
      ⟨copied, by rw [size_copySlice _ _ _ _ (by omega)]; omega⟩)

/-- Inflates blocks up to the final one. Every block takes at least three bits
    of input, so `fuel` of eight per input byte is never exhausted. -/
private def inflateBlocks (limit : Nat) :
    (fuel : Nat) → BitReader → Out limit → DecodeM (BitReader × Out limit)
  | 0, _, _ => throw (.invalid "too many blocks")
  | fuel + 1, br, out => do
    let (final, br) ← br.bits 1
    let (type, br) ← br.bits 2
    let (br, out) ← match type with
      | 0 => inflateStored limit br out
      | 1 => inflateCodes fixedLitCode fixedDistCode limit (limit - out.val.size + 1) br out
      | 2 => do
        let (lit, dist, br) ← readDynamicCodes br
        inflateCodes lit dist limit (limit - out.val.size + 1) br out
      | _ => throw (.invalid "invalid block type")
    if final == 1 then return (br, out) else inflateBlocks limit fuel br out

/-- Inflates the DEFLATE stream starting at byte `start` after `out`, into at
    most `limit` bytes in all: the output and the byte offset past the stream. -/
private def inflateBounded (input : ByteArray) (start limit : Nat) (out : Out limit) :
    DecodeM (Out limit × Nat) := do
  let (br, out) ← inflateBlocks limit (input.size * 8 + 1)
    { input, pos := start, buf := 0, cnt := 0 } out
  return (out, br.alignToByte.pos)

/-- Inflates the DEFLATE stream starting at byte `start`. Returns the output and
    the byte offset just past the stream. -/
def inflate (input : ByteArray) (start : Nat := 0) (limit : Nat := 2 ^ 62)
    (out : ByteArray := .empty) : Except Error (ByteArray × Nat) :=
  if h : out.size ≤ limit then
    (fun (out, e) => (out.val, e)) <$> inflateBounded input start limit ⟨out, h⟩
  else .error .limitExceeded

/-- Inflating never produces more than `limit` bytes. -/
theorem inflate_size_le {input : ByteArray} {start limit : Nat} {out res : ByteArray} {e : Nat}
    (h : inflate input start limit out = .ok (res, e)) : res.size ≤ limit := by
  simp only [inflate] at h
  split at h
  · simp only [Functor.map, Except.map] at h
    split at h
    · simp at h
    · rename_i v _
      simp only [Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, -⟩ := h
      exact v.1.2
  · simp at h

/-! ## Compression -/

/-- Writes bits least-significant first. -/
private structure BitWriter where
  out : ByteArray
  buf : UInt64 := 0
  cnt : UInt64 := 0

@[inline] private def BitWriter.put (w : BitWriter) (value : Nat) (n : Nat) : BitWriter := Id.run do
  let mut out := w.out
  let mut buf := w.buf ||| (value.toUInt64 <<< w.cnt)
  let mut cnt := w.cnt + n.toUInt64
  while cnt ≥ 8 do
    out := out.push buf.toUInt8
    buf := buf >>> 8
    cnt := cnt - 8
  return { out, buf, cnt }

private def BitWriter.flush (w : BitWriter) : ByteArray :=
  if w.cnt > 0 then w.out.push w.buf.toUInt8 else w.out

/-- Reverses the low `len` bits of `code`: Huffman codes are sent most
    significant bit first, inside a least-significant-first bit stream. -/
private def reverseBits (code len : Nat) : Nat := Id.run do
  let mut r := 0
  let mut c := code
  for _ in [0:len] do
    r := (r <<< 1) ||| (c &&& 1)
    c := c >>> 1
  return r

/-- The fixed code for each literal/length symbol, pre-reversed, with its length. -/
private def fixedLitTable : Array (Nat × Nat) := Id.run do
  let mut t := Array.emptyWithCapacity 288
  for sym in [0:288] do
    let (code, len) :=
      if sym < 144 then (0x30 + sym, 8)
      else if sym < 256 then (0x190 + (sym - 144), 9)
      else if sym < 280 then (sym - 256, 7)
      else (0xc0 + (sym - 280), 8)
    t := t.push (reverseBits code len, len)
  return t

private def fixedDistTable : Array Nat :=
  (Array.range 30).map (reverseBits · 5)

@[inline] private def putLiteral (w : BitWriter) (sym : Nat) : BitWriter :=
  let (code, len) := fixedLitTable[sym]!
  w.put code len

/-- The largest `i` with `table[i] ≤ v`. -/
private def symbolFor (table : Array Nat) (v : Nat) : Nat := Id.run do
  let mut i := 0
  for j in [0:table.size] do
    if table[j]! ≤ v then i := j
  return i

private def putMatch (w : BitWriter) (len dist : Nat) : BitWriter :=
  let lsym := symbolFor lengthBase len
  let w := putLiteral w (257 + lsym)
  let w := w.put (len - lengthBase[lsym]!) lengthExtra[lsym]!
  let dsym := symbolFor distBase dist
  let w := w.put fixedDistTable[dsym]! 5
  w.put (dist - distBase[dsym]!) distExtra[dsym]!

private def hashBits : Nat := 15
private def windowSize : Nat := 32768
private def maxMatch : Nat := 258

@[inline] private def hash3 (data : ByteArray) (i : Nat) : Nat :=
  let v := (data[i]!.toNat <<< 16) ||| (data[i + 1]!.toNat <<< 8) ||| data[i + 2]!.toNat
  ((v * 2654435761) >>> 17) &&& ((1 <<< hashBits) - 1)

@[inline] private def matchLength (data : ByteArray) (a b limit : Nat) : Nat := Id.run do
  let mut n := 0
  while n < limit && data[a + n]! == data[b + n]! do
    n := n + 1
  return n

/-- One final fixed-Huffman block holding all of `data`. -/
private def deflateFixed (data : ByteArray) (w : BitWriter) : BitWriter := Id.run do
  let mut w := w.put 1 1 |>.put 1 2
  let mut table : Array Nat := Array.replicate (1 <<< hashBits) 0
  let mut i := 0
  let n := data.size
  while i < n do
    if i + 3 ≤ n then
      let h := hash3 data i
      let cand := table[h]!
      table := table.set! h (i + 1)
      if cand > 0 && i - (cand - 1) ≤ windowSize then
        let c := cand - 1
        let len := matchLength data c i (min maxMatch (n - i))
        if len ≥ 3 then
          w := putMatch w len (i - c)
          -- Index the positions inside the match so later repeats can find them.
          let stop := min (i + len) (n - 2)
          let mut j := i + 1
          while j < stop do
            table := table.set! (hash3 data j) (j + 1)
            j := j + 1
          i := i + len
          continue
    w := putLiteral w data[i]!.toNat
    i := i + 1
  return putLiteral w 256

/-- Stored blocks: the input verbatim, in pieces of at most 65535 bytes. -/
private def deflateStored (data : ByteArray) (out : ByteArray) : ByteArray := Id.run do
  let mut out := out
  let mut i := 0
  let mut first := true
  while first || i < data.size do
    first := false
    let len := min 65535 (data.size - i)
    let final := if i + len ≥ data.size then 1 else 0
    out := out.push final.toUInt8
    out := out.push len.toUInt8 |>.push (len >>> 8).toUInt8
    out := out.push (len ^^^ 0xffff).toUInt8 |>.push ((len ^^^ 0xffff) >>> 8).toUInt8
    out := data.copySlice i out out.size len
    i := i + len
  return out

/-- DEFLATE-compresses `data`, appending to `out`. -/
def deflate (data : ByteArray) (out : ByteArray := .empty) : ByteArray :=
  let compressed := (deflateFixed data { out }).flush
  let storedSize := out.size + data.size + 5 * (data.size / 65535 + 1)
  if compressed.size ≤ storedSize then compressed else deflateStored data out

/-! ## The gzip container -/

private def putLE32 (out : ByteArray) (v : UInt32) : ByteArray :=
  out.push v.toUInt8 |>.push (v >>> 8).toUInt8 |>.push (v >>> 16).toUInt8 |>.push (v >>> 24).toUInt8

private def getLE32 (b : ByteArray) (i : Nat) : UInt32 :=
  b[i]!.toUInt32 ||| (b[i + 1]!.toUInt32 <<< 8) ||| (b[i + 2]!.toUInt32 <<< 16) |||
    (b[i + 3]!.toUInt32 <<< 24)

/-- gzip-compresses `data`. -/
def compress (data : ByteArray) : ByteArray :=
  -- Magic, deflate, no flags, no mtime, no extra flags, unknown OS.
  let header : ByteArray := ⟨#[0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 255]⟩
  let body := deflate data header
  putLE32 (putLE32 body (crc32 data)) data.size.toUInt32

/-- Skips a zero-terminated field starting at `i`. -/
private def skipZeroTerminated (b : ByteArray) (i : Nat) : Except Error Nat := do
  let mut j := i
  while j < b.size && b[j]! != 0 do
    j := j + 1
  if j ≥ b.size then throw (.invalid "truncated header")
  return j + 1

/-- Decompresses the gzip members from `start` on, after `out`. Every member
    takes at least eighteen bytes, so `fuel` of one per byte is never
    exhausted. -/
private def members (data : ByteArray) (limit : Nat) :
    (fuel : Nat) → (start : Nat) → Out limit → Except Error (Out limit)
  | 0, _, _ => throw (.invalid "too many members")
  | fuel + 1, start, out => do
    let b := data
    if start + 10 > b.size then throw (.invalid "truncated header")
    if b[start]! != 0x1f || b[start + 1]! != 0x8b then throw (.invalid "not gzip data")
    if b[start + 2]! != 8 then throw (.invalid "unknown compression method")
    let flags := b[start + 3]!
    let mut i := start + 10
    if flags &&& 0x04 != 0 then
      if i + 2 > b.size then throw (.invalid "truncated header")
      let xlen := b[i]!.toNat ||| (b[i + 1]!.toNat <<< 8)
      i := i + 2 + xlen
    if flags &&& 0x08 != 0 then i ← skipZeroTerminated b i
    if flags &&& 0x10 != 0 then i ← skipZeroTerminated b i
    if flags &&& 0x02 != 0 then i := i + 2
    if i > b.size then throw (.invalid "truncated header")
    -- Each member is inflated on its own: back-references cannot reach into
    -- the previous member's output.
    let (produced, «end») ← inflateBounded b i (limit - out.val.size) ⟨.empty, Nat.zero_le _⟩
    if «end» + 8 > b.size then throw (.invalid "truncated trailer")
    if getLE32 b «end» != crc32 produced.val then throw (.invalid "CRC mismatch")
    if getLE32 b («end» + 4) != produced.val.size.toUInt32 then throw (.invalid "size mismatch")
    let out : Out limit := ⟨out.val ++ produced.val, by
      have := out.2; have := produced.2; simp only [ByteArray.size_append]; omega⟩
    let next := «end» + 8
    if next + 2 ≤ b.size && b[next]! == 0x1f && b[next + 1]! == 0x8b then
      members data limit fuel next out
    else
      return out

/-- Decompresses gzip data, including concatenated members. Fails if the output
    would be larger than `limit` bytes. -/
def decompress (data : ByteArray) (limit : Nat := 2 ^ 62) : Except Error ByteArray :=
  (·.val) <$> members data limit (data.size + 1) 0 ⟨.empty, Nat.zero_le _⟩

/-- Decompression never produces more than `limit` bytes, however the input
    was made. (The output type of each step says the same of every buffer on
    the way.) -/
theorem decompress_size_le {data : ByteArray} {limit : Nat} {out : ByteArray}
    (h : decompress data limit = .ok out) : out.size ≤ limit := by
  simp only [decompress, Functor.map, Except.map] at h
  split at h
  · simp at h
  · rename_i v _
    simp only [Except.ok.injEq] at h
    exact h ▸ v.2

end Connect.Gzip
