module

public import Std.Data.HashMap
public import Connect.Http2.HpackTables

public section

/-!
# HPACK

Header compression for HTTP/2 (RFC 7541).

The decoder is complete: indexed fields, literals with and without indexing,
Huffman-coded strings, and a dynamic table with size updates, bounded by the
table size we advertise.

The encoder never adds to the dynamic table. It indexes into the static table
where it can and writes everything else as literals, Huffman-coded when that is
shorter. Being stateless, header blocks from different streams can be sent in
any order.
-/

namespace Connect.Http2.Hpack

/-! ## Integers and strings (§5) -/

/-- Writes the continuation bytes of an integer: seven bits at a time, least
    significant first, the high bit set on all but the last. -/
def encodeIntRest (out : ByteArray) (v : Nat) : ByteArray :=
  if v < 128 then out.push v.toUInt8
  else encodeIntRest (out.push (v % 128 + 128).toUInt8) (v / 128)
termination_by v
decreasing_by omega

/-- Encodes `value` with an `n`-bit prefix, OR-ing `flags` into the first byte. -/
def encodeInt (out : ByteArray) (n : Nat) (flags : UInt8) (value : Nat) : ByteArray :=
  let max := 2 ^ n - 1
  if value < max then out.push (flags ||| value.toUInt8)
  else encodeIntRest (out.push (flags ||| max.toUInt8)) (value - max)

/-- Reads the continuation bytes of an integer from `i` on, adding them to
    `value`: at most `left` of them. -/
def decodeIntRest (b : ByteArray) (i value shift : Nat) : (left : Nat) → Except String (Nat × Nat)
  | 0 => .error (if i < b.size then "hpack: integer too long" else "hpack: truncated integer")
  | left + 1 =>
    if h : i < b.size then
      let byte := b[i].toNat
      let value := value + byte % 128 * 2 ^ shift
      if value > 2 ^ 32 then .error "hpack: integer too large"
      else if byte < 128 then .ok (value, i + 1)
      else decodeIntRest b (i + 1) value (shift + 7) left
    else .error "hpack: truncated integer"

/-- Decodes an `n`-bit-prefix integer at `pos`: its value and the position just
    past it. Values above 2^32 are refused, and so are encodings with more than
    five continuation bytes (padded with zeros, they would otherwise cost time
    without changing the value). -/
def decodeInt (b : ByteArray) (pos : Nat) (n : Nat) : Except String (Nat × Nat) :=
  if h : pos < b.size then
    let max := 2 ^ n - 1
    let first := b[pos].toNat % 2 ^ n
    if first < max then .ok (first, pos + 1)
    else decodeIntRest b (pos + 1) max 0 5
  else .error "hpack: truncated integer"

/-! ### What decoding an integer can do

An integer's value is bounded and so is its length: a peer cannot make the
decoder read far, or build large numbers, by padding. -/

theorem decodeIntRest_spec {b : ByteArray} :
    ∀ {left i value shift v p : Nat}, decodeIntRest b i value shift left = .ok (v, p) →
      v ≤ 2 ^ 32 ∧ i < p ∧ p ≤ i + left ∧ p ≤ b.size := by
  intro left
  induction left with
  | zero => intro i value shift v p h; simp [decodeIntRest] at h
  | succ left ih =>
    intro i value shift v p h
    simp only [decodeIntRest] at h
    split at h
    · rename_i hi
      split at h
      · simp at h
      · rename_i hle
        split at h
        · simp only [Except.ok.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          omega
        · have := ih h
          omega
    · simp at h

/-- A decoded integer is at most 2^32, and takes one to six bytes of the block. -/
theorem decodeInt_spec {b : ByteArray} {pos n v p : Nat} (h : decodeInt b pos n = .ok (v, p)) :
    v ≤ 2 ^ 32 ∧ pos < p ∧ p ≤ pos + 6 ∧ p ≤ b.size := by
  simp only [decodeInt] at h
  split at h
  · rename_i hpos
    split at h
    · simp only [Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      have hb := (b[pos]'hpos).toNat_lt
      have := Nat.mod_le (b[pos]'hpos).toNat (2 ^ n)
      omega
    · have := decodeIntRest_spec h
      omega
  · simp at h

/-! ## Huffman coding (§5.2, Appendix B) -/

/-- The symbol of each code, by length and code. EOS, the 257th code, is left
    out: a string containing it is invalid (§5.2). -/
private def huffmanLookup : Std.HashMap (UInt8 × UInt32) UInt8 := Id.run do
  let mut m := {}
  for i in [0:256] do
    let (code, len) := huffmanCodes[i]!
    m := m.insert (len, code) i.toUInt8
  return m

/-- Decodes a Huffman-coded string. Padding must be at most seven one-bits. -/
def huffmanDecode (b : ByteArray) : Except String ByteArray := do
  let table := huffmanLookup
  let mut out := ByteArray.empty
  let mut code : UInt32 := 0
  let mut len : UInt8 := 0
  for byte in b do
    for k in [0:8] do
      let bit := ((byte >>> (7 - k).toUInt8) &&& 1).toUInt32
      code := (code <<< 1) ||| bit
      len := len + 1
      if len ≥ 5 then
        if let some sym := table[(len, code)]? then
          out := out.push sym
          code := 0
          len := 0
        else if len ≥ 30 then
          throw "hpack: invalid Huffman code"
  -- What is left must be a prefix of EOS, which is all ones, and shorter than a byte.
  if len > 7 then throw "hpack: Huffman padding longer than seven bits"
  if code != (1 <<< len.toUInt32) - 1 then throw "hpack: Huffman padding is not EOS"
  return out

/-- The Huffman-coded length of `b`, in bytes. -/
def huffmanLength (b : ByteArray) : Nat := Id.run do
  let mut bits := 0
  for byte in b do
    bits := bits + (huffmanCodes[byte.toNat]!).2.toNat
  return (bits + 7) / 8

/-- Huffman-codes `b`, padding with ones. -/
def huffmanEncode (b : ByteArray) : ByteArray := Id.run do
  let mut out := ByteArray.emptyWithCapacity (huffmanLength b)
  let mut acc : UInt64 := 0
  let mut n : UInt64 := 0
  for byte in b do
    let (code, len) := huffmanCodes[byte.toNat]!
    acc := (acc <<< len.toUInt64) ||| code.toUInt64
    n := n + len.toUInt64
    while n ≥ 8 do
      n := n - 8
      out := out.push (acc >>> n).toUInt8
    acc := acc &&& ((1 <<< n) - 1)
  if n > 0 then
    out := out.push ((acc <<< (8 - n)) ||| ((1 <<< (8 - n)) - 1)).toUInt8
  return out

/-- Writes a string literal, Huffman-coded if that is shorter. -/
def encodeString (out : ByteArray) (s : String) : ByteArray :=
  let raw := s.toUTF8
  let hlen := huffmanLength raw
  if hlen < raw.size then encodeInt out 7 0x80 hlen ++ huffmanEncode raw
  else encodeInt out 7 0 raw.size ++ raw

/-- Reads a string literal at `pos`: the string and the position just past it. -/
def decodeString (b : ByteArray) (pos : Nat) : Except String (String × Nat) :=
  if h : pos < b.size then
    let huffman := b[pos] &&& 0x80 != 0
    match decodeInt b pos 7 with
    | .error e => .error e
    | .ok (len, start) =>
      if start + len > b.size then .error "hpack: truncated string"
      else
        let raw := b.extract start (start + len)
        match (if huffman then huffmanDecode raw else .ok raw) with
        | .error e => .error e
        | .ok bytes =>
          match String.fromUTF8? bytes with
          | some s => .ok (s, start + len)
          | none => .error "hpack: header is not UTF-8"
  else .error "hpack: truncated string"

/-- A decoded string literal ends within the block, after where it starts. -/
theorem decodeString_spec {b : ByteArray} {pos : Nat} {s : String} {p : Nat}
    (h : decodeString b pos = .ok (s, p)) : pos < p ∧ p ≤ b.size := by
  simp only [decodeString] at h
  split at h
  · split at h
    · simp at h
    · rename_i len start hint
      have := decodeInt_spec hint
      split at h
      · simp at h
      · rename_i hfit
        split at h
        · simp at h
        · split at h
          · simp only [Except.ok.injEq, Prod.mk.injEq] at h
            omega
          · simp at h
  · simp at h

/-! ## The dynamic table (§2.3, §4) -/

/-- A header's size in the table: its bytes plus 32. -/
def entrySize (name value : String) : Nat := name.utf8ByteSize + value.utf8ByteSize + 32

/-- The size of a list of headers, as the table and HTTP/2 count it
    (RFC 9113 §6.5.2). -/
def listSize (hs : Array (String × String)) : Nat :=
  (hs.toList.map fun h => entrySize h.1 h.2).sum

/-- Decoding state: the dynamic table, newest entry first. -/
structure Decoder where
  entries : Array (String × String) := #[]
  size : Nat := 0
  /-- The size the peer's encoder may use, from its last size update. -/
  maxSize : Nat := 4096
  /-- The largest size we allow (our SETTINGS_HEADER_TABLE_SIZE). -/
  limit : Nat := 4096
  /-- The largest decoded header list we accept. -/
  maxHeaderListSize : Nat := 65536
  deriving Inhabited

namespace Decoder

/-- The table's recorded size is the size of its entries, which fit in the
    current maximum, which is within our limit. -/
def Valid (d : Decoder) : Prop :=
  d.size = listSize d.entries ∧ d.size ≤ d.maxSize ∧ d.maxSize ≤ d.limit

/-- Drops the oldest entries until the table fits in `maxSize`. -/
private def evict (d : Decoder) : Decoder :=
  if _h : d.maxSize < d.size ∧ 0 < d.entries.size then
    evict { d with entries := d.entries.pop
                   size := d.size - entrySize d.entries.back!.1 d.entries.back!.2 }
  else d
termination_by d.entries.size
decreasing_by simp only [Array.size_pop]; omega

private def insert (d : Decoder) (name value : String) : Decoder :=
  let s := entrySize name value
  if s > d.maxSize then { d with entries := #[], size := 0 }
  else evict { d with entries := #[(name, value)] ++ d.entries, size := d.size + s }

private def lookup (d : Decoder) (index : Nat) : Except String (String × String) :=
  if index == 0 then .error "hpack: index 0"
  else if index ≤ staticTable.size then .ok staticTable[index - 1]!
  else match d.entries[index - staticTable.size - 1]? with
    | some e => .ok e
    | none => .error s!"hpack: index {index} is out of range"

/-- A literal field at `pos` whose name index has an `n`-bit prefix: its name,
    its value and the position after it. -/
private def literal (d : Decoder) (b : ByteArray) (pos n : Nat) :
    Except String (String × String × Nat) := do
  let (index, p) ← decodeInt b pos n
  let (name, p) ← if index == 0 then decodeString b p else pure ((← d.lookup index).1, p)
  let (value, p) ← decodeString b p
  return (name, value, p)

/-- Decodes the representation at `pos`: the header field it yields, if any,
    and the table and the position after it. `first`: whether no field has
    been decoded yet; a dynamic table size update must come before the first
    one (§4.2), unless the table is empty. -/
private def decodeOne (d : Decoder) (b : ByteArray) (pos : Nat) (first : Bool) :
    Except String (Option (String × String) × Decoder × Nat) :=
  let byte := b[pos]!
  if byte &&& 0x80 != 0 then
    -- Indexed header field.
    match decodeInt b pos 7 with
    | .error e => .error e
    | .ok (index, p) =>
      match d.lookup index with
      | .error e => .error e
      | .ok field => .ok (some field, d, p)
  else if byte &&& 0xc0 == 0x40 then
    -- Literal with incremental indexing.
    match d.literal b pos 6 with
    | .error e => .error e
    | .ok (name, value, p) => .ok (some (name, value), d.insert name value, p)
  else if byte &&& 0xe0 == 0x20 then
    -- Dynamic table size update.
    if !(first || d.size == 0) then .error "hpack: table size update after a header field"
    else
      match decodeInt b pos 5 with
      | .error e => .error e
      | .ok (size, p) =>
        if size > d.limit then .error "hpack: table size update above the limit"
        else .ok (none, evict { d with maxSize := size }, p)
  else
    -- Literal without indexing (0000) or never indexed (0001).
    match d.literal b pos 4 with
    | .error e => .error e
    | .ok (name, value, p) => .ok (some (name, value), d, p)

/-- Decodes the representations from `pos` on. `size` is the list size of
    `out`. Every representation takes at least a byte, so `fuel` (one more
    than the block's length) is never exhausted. -/
private def decodeFrom (b : ByteArray) :
    (fuel : Nat) → Decoder → (pos : Nat) → Array (String × String) → (size : Nat) →
    Except String (Array (String × String) × Decoder)
  | 0, _, _, _, _ => .error "hpack: header block too long"
  | fuel + 1, d, pos, out, size =>
    if pos < b.size then
      match decodeOne d b pos out.isEmpty with
      | .error e => .error e
      | .ok (none, d', p) => decodeFrom b fuel d' p out size
      | .ok (some (n, v), d', p) =>
        let size := size + entrySize n v
        if size > d.maxHeaderListSize then .error "hpack: header list too large"
        else decodeFrom b fuel d' p (out.push (n, v)) size
    else .ok (out, d)

/-- Decodes a complete header block. -/
def decode (d : Decoder) (b : ByteArray) : Except String (Array (String × String) × Decoder) :=
  decodeFrom b (b.size + 1) d 0 #[] 0

end Decoder


/-! ### What decoding a block can do

Decoding never lets the dynamic table outgrow the size we advertised, nor
returns a header list larger than we accept: a peer cannot use either to make
us hold more memory than configured. -/

@[simp] theorem listSize_empty : listSize #[] = 0 := by simp [listSize]

theorem listSize_push (hs : Array (String × String)) (n v : String) :
    listSize (hs.push (n, v)) = listSize hs + entrySize n v := by
  simp [listSize]

theorem listSize_cons (h : String × String) (hs : Array (String × String)) :
    listSize (#[h] ++ hs) = entrySize h.1 h.2 + listSize hs := by
  simp [listSize]

theorem listSize_pop {hs : Array (String × String)} (h : hs.size ≠ 0) :
    listSize hs.pop + entrySize hs.back!.1 hs.back!.2 = listSize hs := by
  conv => rhs; rw [Array.eq_push_pop_back!_of_size_ne_zero h]
  rw [listSize_push]

namespace Decoder

/-- Eviction keeps the table's accounting, makes it fit in `maxSize`, and
    changes no setting. -/
private theorem evict_spec (d : Decoder) (hd : d.size = listSize d.entries) :
    (evict d).size = listSize (evict d).entries ∧ (evict d).size ≤ d.maxSize ∧
    (evict d).maxSize = d.maxSize ∧ (evict d).limit = d.limit ∧
    (evict d).maxHeaderListSize = d.maxHeaderListSize := by
  fun_induction evict d with
  | case1 d h ih =>
    have hpop := listSize_pop (hs := d.entries) (by omega)
    exact ih (by simp only; omega)
  | case2 d h =>
    refine ⟨hd, ?_, rfl, rfl, rfl⟩
    by_cases hs : d.maxSize < d.size
    · have h0 : d.entries.size = 0 := by omega
      have : d.entries = #[] := Array.eq_empty_of_size_eq_zero h0
      rw [hd, this]; simp
    · omega

private theorem insert_spec (d : Decoder) (n v : String) (hd : d.Valid) :
    (d.insert n v).Valid ∧ (d.insert n v).limit = d.limit ∧
    (d.insert n v).maxHeaderListSize = d.maxHeaderListSize := by
  obtain ⟨hs, hle, hmax⟩ := hd
  unfold insert
  dsimp only
  split
  · exact ⟨⟨rfl, Nat.zero_le _, hmax⟩, rfl, rfl⟩
  · have := evict_spec { d with entries := #[(n, v)] ++ d.entries, size := d.size + entrySize n v }
      (by simp only [listSize_cons]; omega)
    simp only at this
    exact ⟨⟨this.1, by omega, by omega⟩, this.2.2.2.1, this.2.2.2.2⟩

private theorem resize_spec (d : Decoder) (size : Nat) (hd : d.Valid) (hsize : size ≤ d.limit) :
    (evict { d with maxSize := size }).Valid ∧ (evict { d with maxSize := size }).limit = d.limit ∧
    (evict { d with maxSize := size }).maxHeaderListSize = d.maxHeaderListSize := by
  have := evict_spec { d with maxSize := size } hd.1
  simp only at this
  exact ⟨⟨this.1, by omega, by omega⟩, this.2.2.2.1, this.2.2.2.2⟩

/-- A representation leaves the table as it was, adds an entry to it, or
    resizes it within our limit. -/
private theorem decodeOne_table {d : Decoder} {b : ByteArray} {pos : Nat} {first : Bool}
    {f : Option (String × String)} {d' : Decoder} {p : Nat}
    (h : d.decodeOne b pos first = .ok (f, d', p)) :
    d' = d ∨ (∃ n v, d' = d.insert n v) ∨ (∃ size, size ≤ d.limit ∧ d' = evict { d with maxSize := size }) := by
  unfold decodeOne at h
  dsimp only at h
  repeat' split at h
  all_goals first
    | (simp only [reduceCtorEq] at h)
    | (simp only [Except.ok.injEq, Prod.mk.injEq] at h
       obtain ⟨-, rfl, -⟩ := h
       first
         | exact .inl rfl
         | exact .inr (.inl ⟨_, _, rfl⟩)
         | exact .inr (.inr ⟨_, by omega, rfl⟩))

private theorem decodeOne_spec {d : Decoder} {b : ByteArray} {pos : Nat} {first : Bool}
    {f : Option (String × String)} {d' : Decoder} {p : Nat} (hd : d.Valid)
    (h : d.decodeOne b pos first = .ok (f, d', p)) :
    d'.Valid ∧ d'.limit = d.limit ∧ d'.maxHeaderListSize = d.maxHeaderListSize := by
  rcases decodeOne_table h with rfl | ⟨n, v, rfl⟩ | ⟨size, hsize, rfl⟩
  · exact ⟨hd, rfl, rfl⟩
  · exact insert_spec d n v hd
  · exact resize_spec d size hd hsize

private theorem decodeFrom_spec {b : ByteArray} :
    ∀ {fuel : Nat} {d : Decoder} {pos : Nat} {out : Array (String × String)} {size : Nat}
      {hs : Array (String × String)} {d' : Decoder},
    decodeFrom b fuel d pos out size = .ok (hs, d') → d.Valid → size = listSize out →
    size ≤ d.maxHeaderListSize →
    d'.Valid ∧ d'.limit = d.limit ∧ d'.maxHeaderListSize = d.maxHeaderListSize ∧
      listSize hs ≤ d.maxHeaderListSize := by
  intro fuel
  induction fuel with
  | zero => intro d pos out size hs d' h; simp [decodeFrom] at h
  | succ fuel ih =>
    intro d pos out size hs d' h hd hsize hle
    simp only [decodeFrom] at h
    split at h
    · split at h
      · simp at h
      · rename_i d1 p hone
        obtain ⟨hv1, hl1, hm1⟩ := decodeOne_spec hd hone
        have := ih h hv1 hsize (by omega)
        exact ⟨this.1, by omega, by omega, by omega⟩
      · rename_i n v d1 p hone
        obtain ⟨hv1, hl1, hm1⟩ := decodeOne_spec hd hone
        split at h
        · simp at h
        · rename_i hmax
          have := ih h hv1 (by rw [listSize_push]; omega) (by omega)
          exact ⟨this.1, by omega, by omega, by omega⟩
    · simp only [Except.ok.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨hd, rfl, rfl, by omega⟩

/-- Decoding a block keeps the dynamic table within the size we advertised
    (`limit`), and changes neither setting. -/
theorem decode_valid {d : Decoder} {b : ByteArray} {hs : Array (String × String)} {d' : Decoder}
    (hd : d.Valid) (h : d.decode b = .ok (hs, d')) :
    d'.Valid ∧ d'.limit = d.limit ∧ d'.maxHeaderListSize = d.maxHeaderListSize :=
  let r := decodeFrom_spec h hd rfl (Nat.zero_le _)
  ⟨r.1, r.2.1, r.2.2.1⟩

/-- The headers a block decodes to fit in the header list size we accept. -/
theorem decode_listSize {d : Decoder} {b : ByteArray} {hs : Array (String × String)}
    {d' : Decoder} (hd : d.Valid) (h : d.decode b = .ok (hs, d')) :
    listSize hs ≤ d.maxHeaderListSize :=
  (decodeFrom_spec h hd rfl (Nat.zero_le _)).2.2.2

/-- A decoder starts out valid. -/
theorem valid_mk (limit maxHeaderListSize : Nat) :
    ({ limit, maxSize := limit, maxHeaderListSize } : Decoder).Valid :=
  ⟨rfl, Nat.zero_le _, Nat.le_refl _⟩

end Decoder

/-! ## Encoding -/

private def staticIndex : Std.HashMap (String × String) Nat × Std.HashMap String Nat := Id.run do
  let mut full := {}
  let mut names := {}
  for h : i in [0:staticTable.size] do
    let e := staticTable[i]
    unless full.contains e do full := full.insert e (i + 1)
    unless names.contains e.1 do names := names.insert e.1 (i + 1)
  return (full, names)

/-- Encodes a header block without touching the dynamic table. Names must be
    lower case. -/
def encode (headers : Array (String × String)) : ByteArray := Id.run do
  let (full, names) := staticIndex
  let mut out := ByteArray.empty
  for (name, value) in headers do
    if let some i := full[(name, value)]? then
      out := encodeInt out 7 0x80 i
    else
      -- Credentials are marked never-indexed, for intermediaries' sake.
      let flags : UInt8 := if name == "authorization" || name == "cookie" then 0x10 else 0
      match names[name]? with
      | some i => out := encodeInt out 4 flags i
      | none => out := encodeString (encodeInt out 4 flags 0) name
      out := encodeString out value
  return out

end Connect.Http2.Hpack
