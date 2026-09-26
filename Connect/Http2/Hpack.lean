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

/-- Encodes `value` with an `n`-bit prefix, OR-ing `flags` into the first byte. -/
def encodeInt (out : ByteArray) (n : Nat) (flags : UInt8) (value : Nat) : ByteArray := Id.run do
  let max := 2 ^ n - 1
  if value < max then return out.push (flags ||| value.toUInt8)
  let mut out := out.push (flags ||| max.toUInt8)
  let mut v := value - max
  while v ≥ 128 do
    out := out.push ((v % 128) + 128).toUInt8
    v := v / 128
  return out.push v.toUInt8

/-- Decodes an `n`-bit-prefix integer at `pos`. Values above 2^32 are refused,
    and so are encodings with more than five continuation bytes (padded with
    zeros, they would otherwise cost time without changing the value). -/
def decodeInt (b : ByteArray) (pos : Nat) (n : Nat) : Except String (Nat × Nat) := do
  if pos ≥ b.size then throw "hpack: truncated integer"
  let max := 2 ^ n - 1
  let first := b[pos]!.toNat % (2 ^ n)
  if first < max then return (first, pos + 1)
  let mut value := max
  let mut shift := 0
  let mut i := pos + 1
  repeat
    if i ≥ b.size then throw "hpack: truncated integer"
    if i - pos > 5 then throw "hpack: integer too long"
    let byte := b[i]!.toNat
    value := value + (byte % 128) * 2 ^ shift
    i := i + 1
    if value > 2 ^ 32 then throw "hpack: integer too large"
    if byte < 128 then break
    shift := shift + 7
  return (value, i)

/-! ## Huffman coding (§5.2, Appendix B) -/

private def huffmanLookup : Std.HashMap (UInt8 × UInt32) UInt8 := Id.run do
  let mut m := {}
  for h : i in [0:huffmanCodes.size] do
    let (code, len) := huffmanCodes[i]
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

/-- Reads a string literal at `pos`. -/
def decodeString (b : ByteArray) (pos : Nat) : Except String (String × Nat) := do
  if pos ≥ b.size then throw "hpack: truncated string"
  let huffman := b[pos]! &&& 0x80 != 0
  let (len, pos) ← decodeInt b pos 7
  if pos + len > b.size then throw "hpack: truncated string"
  let raw := b.extract pos (pos + len)
  let bytes ← if huffman then huffmanDecode raw else pure raw
  let some s := String.fromUTF8? bytes | throw "hpack: header is not UTF-8"
  return (s, pos + len)

/-! ## The dynamic table (§2.3, §4) -/

/-- A header's size in the table: its bytes plus 32. -/
def entrySize (name value : String) : Nat := name.utf8ByteSize + value.utf8ByteSize + 32

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

private def evict (d : Decoder) : Decoder := Id.run do
  let mut d := d
  while d.size > d.maxSize && !d.entries.isEmpty do
    let (n, v) := d.entries.back!
    d := { d with entries := d.entries.pop, size := d.size - entrySize n v }
  return d

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

/-- Decodes a complete header block. -/
def decode (d : Decoder) (b : ByteArray) : Except String (Array (String × String) × Decoder) := do
  let mut d := d
  let mut out := #[]
  let mut pos := 0
  let mut listSize := 0
  while pos < b.size do
    let byte := b[pos]!
    if byte &&& 0x80 != 0 then
      -- Indexed header field.
      let (index, p) ← decodeInt b pos 7
      out := out.push (← d.lookup index)
      pos := p
    else if byte &&& 0xc0 == 0x40 then
      -- Literal with incremental indexing.
      let (index, p) ← decodeInt b pos 6
      let (name, p) ← if index == 0 then decodeString b p else pure ((← d.lookup index).1, p)
      let (value, p) ← decodeString b p
      out := out.push (name, value)
      d := d.insert name value
      pos := p
    else if byte &&& 0xe0 == 0x20 then
      -- Dynamic table size update.
      let (size, p) ← decodeInt b pos 5
      if size > d.limit then throw "hpack: table size update above the limit"
      d := evict { d with maxSize := size }
      pos := p
    else
      -- Literal without indexing (0000) or never indexed (0001).
      let (index, p) ← decodeInt b pos 4
      let (name, p) ← if index == 0 then decodeString b p else pure ((← d.lookup index).1, p)
      let (value, p) ← decodeString b p
      out := out.push (name, value)
      pos := p
    if let some (n, v) := out.back? then
      listSize := listSize + entrySize n v
      if listSize > d.maxHeaderListSize then throw "hpack: header list too large"
  return (out, d)

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
