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

/-! ### Encoding and decoding integers agree -/

theorem lt_size_encodeIntRest (out : ByteArray) (w : Nat) :
    out.size < (encodeIntRest out w).size := by
  fun_induction encodeIntRest out w with
  | case1 out w h => simp [ByteArray.size_push]
  | case2 out w h ih => simp only [ByteArray.size_push] at ih; omega

theorem getElem!_encodeIntRest (out : ByteArray) (w i : Nat) (hi : i < out.size) :
    (encodeIntRest out w)[i]! = out[i]! := by
  fun_induction encodeIntRest out w with
  | case1 out w h => exact ByteArray.getElem!_push_lt _ _ _ hi
  | case2 out w h ih =>
    rw [ih (by simp only [ByteArray.size_push]; omega), ByteArray.getElem!_push_lt _ _ _ hi]

/-- The byte at `i` of `a ++ b`, for `i` within `a`. -/
private theorem getElem!_append_left' (a b : ByteArray) (i : Nat) (hi : i < a.size) :
    (a ++ b)[i]! = a[i]! := by
  rw [getElem!_pos (a ++ b) i (by simp [ByteArray.size_append]; omega), getElem!_pos a i hi]
  exact ByteArray.getElem_append_left hi

private theorem decodeIntRest_encodeIntRest (rest : ByteArray) (w : Nat) (out : ByteArray) :
    ∀ (value shift left : Nat), 0 < left → w < 128 ^ left → value + w * 2 ^ shift ≤ 2 ^ 32 →
    decodeIntRest (encodeIntRest out w ++ rest) out.size value shift left =
      .ok (value + w * 2 ^ shift, (encodeIntRest out w).size) := by
  fun_induction encodeIntRest out w with
  | case1 out w hw =>
    intro value shift left hleft hlt hle
    obtain ⟨left, rfl⟩ : ∃ l, left = l + 1 := ⟨left - 1, by omega⟩
    have hsize : out.size < (out.push w.toUInt8 ++ rest).size := by
      simp [ByteArray.size_append, ByteArray.size_push]; omega
    have hbyte : (out.push w.toUInt8 ++ rest)[out.size]'hsize = w.toUInt8 := by
      rw [← getElem!_pos, getElem!_append_left' _ _ _ (by simp [ByteArray.size_push]),
        ByteArray.getElem!_push_eq]
    have hnat : w.toUInt8.toNat = w := by
      simp only [Nat.toUInt8_eq, UInt8.toNat_ofNat']; omega
    simp only [decodeIntRest, hsize, ↓reduceDIte, hbyte, hnat, ByteArray.size_push,
      Nat.mod_eq_of_lt hw, show ¬ value + w * 2 ^ shift > 2 ^ 32 by omega, ↓reduceIte, hw]
  | case2 out w hw ih =>
    intro value shift left hleft hlt hle
    obtain ⟨left, rfl⟩ : ∃ l, left = l + 1 := ⟨left - 1, by omega⟩
    have hleft' : 0 < left := by
      rcases Nat.eq_zero_or_pos left with h0 | h0
      · subst h0; simp at hlt; omega
      · exact h0
    generalize hc : (w % 128 + 128).toUInt8 = c at *
    have hcnat : c.toNat = w % 128 + 128 := by
      rw [← hc]; simp only [Nat.toUInt8_eq, UInt8.toNat_ofNat']; omega
    have hlen := lt_size_encodeIntRest (out.push c) (w / 128)
    simp only [ByteArray.size_push] at hlen
    have hsize : out.size < (encodeIntRest (out.push c) (w / 128) ++ rest).size := by
      simp only [ByteArray.size_append]; omega
    have hbyte : (encodeIntRest (out.push c) (w / 128) ++ rest)[out.size]'hsize = c := by
      rw [← getElem!_pos, getElem!_append_left' _ _ _ (by omega),
        getElem!_encodeIntRest _ _ _ (by simp [ByteArray.size_push]), ByteArray.getElem!_push_eq]
    have hdiv : w / 128 < 128 ^ left := by
      rw [Nat.pow_succ] at hlt; omega
    have hsplit : w * 2 ^ shift = w % 128 * 2 ^ shift + w / 128 * 2 ^ (shift + 7) := by
      have hw' := Nat.mod_add_div w 128
      rw [Nat.pow_add, show (2 : Nat) ^ 7 = 128 by rfl]
      conv => lhs; rw [← hw']
      rw [Nat.add_mul, Nat.mul_comm 128 (w / 128), Nat.mul_assoc, Nat.mul_comm 128 (2 ^ shift)]
    have hrec := ih (value + w % 128 * 2 ^ shift) (shift + 7) left hleft' hdiv (by omega)
    simp only [ByteArray.size_push] at hrec
    simp only [decodeIntRest, hsize, ↓reduceDIte, hbyte, hcnat,
      show (w % 128 + 128) % 128 = w % 128 by omega,
      show ¬ value + w % 128 * 2 ^ shift > 2 ^ 32 by omega, ↓reduceIte,
      show ¬ w % 128 + 128 < 128 by omega, hrec]
    rw [Nat.add_assoc, ← hsplit]

/-- Decoding what `encodeInt` wrote, followed by anything, gives back the value
    and the position just past it, for prefixes of one to eight bits, flags
    outside the prefix, and values up to 2^32. -/
theorem decodeInt_encodeInt (out rest : ByteArray) (n : Nat) (flags : UInt8) (v : Nat)
    (hn : 1 ≤ n ∧ n ≤ 8) (hflags : flags.toNat % 2 ^ n = 0) (hv : v ≤ 2 ^ 32) :
    decodeInt (encodeInt out n flags v ++ rest) out.size n =
      .ok (v, (encodeInt out n flags v).size) := by
  have hp1 : 2 ^ 1 ≤ 2 ^ n := Nat.pow_le_pow_right (by decide) hn.1
  have hp8 : 2 ^ n ≤ 2 ^ 8 := Nat.pow_le_pow_right (by decide) hn.2
  simp only [Nat.pow_one, show (2 : Nat) ^ 8 = 256 by rfl] at hp1 hp8
  -- The first byte keeps the value (or the prefix's maximum) in its low bits.
  have hfirst : ∀ x, x < 2 ^ n → (flags ||| x.toUInt8).toNat % 2 ^ n = x := by
    intro x hx
    have hx8 : x.toUInt8.toNat = x := by
      simp only [Nat.toUInt8_eq, UInt8.toNat_ofNat']; omega
    rw [UInt8.toNat_or, Nat.or_mod_two_pow, hflags, Nat.zero_or, hx8, Nat.mod_eq_of_lt hx]
  unfold encodeInt
  dsimp only
  split
  · rename_i hlt
    have hsize : out.size < (out.push (flags ||| v.toUInt8) ++ rest).size := by
      simp [ByteArray.size_append, ByteArray.size_push]; omega
    have hbyte :
        (out.push (flags ||| v.toUInt8) ++ rest)[out.size]'hsize = flags ||| v.toUInt8 := by
      rw [← getElem!_pos, getElem!_append_left' _ _ _ (by simp [ByteArray.size_push]),
        ByteArray.getElem!_push_eq]
    simp only [decodeInt, hsize, ↓reduceDIte, hbyte, hfirst v (by omega), hlt, ↓reduceIte,
      ByteArray.size_push]
  · rename_i hge
    generalize hc : flags ||| (2 ^ n - 1).toUInt8 = c
    have hlen := lt_size_encodeIntRest (out.push c) (v - (2 ^ n - 1))
    simp only [ByteArray.size_push] at hlen
    have hsize : out.size < (encodeIntRest (out.push c) (v - (2 ^ n - 1)) ++ rest).size := by
      simp only [ByteArray.size_append]; omega
    have hbyte : (encodeIntRest (out.push c) (v - (2 ^ n - 1)) ++ rest)[out.size]'hsize = c := by
      rw [← getElem!_pos, getElem!_append_left' _ _ _ (by omega),
        getElem!_encodeIntRest _ _ _ (by simp [ByteArray.size_push]), ByteArray.getElem!_push_eq]
    have hmax : c.toNat % 2 ^ n = 2 ^ n - 1 := by rw [← hc]; exact hfirst _ (by omega)
    have hrest := decodeIntRest_encodeIntRest rest (v - (2 ^ n - 1)) (out.push c) (2 ^ n - 1) 0 5
      (by decide) (by
        have : (2 : Nat) ^ 32 < 128 ^ 5 := by decide
        omega) (by simp; omega)
    simp only [ByteArray.size_push] at hrest
    simp only [decodeInt, hsize, ↓reduceDIte, hbyte, hmax, Nat.lt_irrefl, ↓reduceIte, hrest]
    congr 2
    simp; omega

/-! ## Huffman coding (§5.2, Appendix B)

The code is canonical, so decoding uses, for each length, the first code and
the number of codes (see `HpackTables`), rather than a lookup table. -/

/-- The symbol whose code is `code`, `len` bits long, if there is one. EOS is
    not a symbol: a string containing it is invalid (§5.2). -/
def huffmanSymbol? (len code : Nat) : Option UInt8 :=
  let first := huffmanFirst[len]!
  if first ≤ code ∧ code < first + huffmanCount[len]! then
    some huffmanSymbols[huffmanOffset[len]! + (code - first)]!
  else none

/-- Decodes bits `k - 1` down to `0` of `byte` (most significant first), after
    `code`, the `len` bits read since the last symbol. -/
def huffmanDecodeBits (byte : Nat) : (k : Nat) → (code len : Nat) → ByteArray →
    Except String (Nat × Nat × ByteArray)
  | 0, code, len, out => .ok (code, len, out)
  | k + 1, code, len, out =>
    let code := code * 2 + (byte >>> k) % 2
    let len := len + 1
    match huffmanSymbol? len code with
    | some sym => huffmanDecodeBits byte k 0 0 (out.push sym)
    | none =>
      if len ≥ 30 then .error "hpack: invalid Huffman code"
      else huffmanDecodeBits byte k code len out

/-- Decodes the bytes of `b` from `i` on. What is left at the end must be a
    prefix of EOS, which is all ones, shorter than a byte. -/
def huffmanDecodeFrom (b : ByteArray) (i code len : Nat) (out : ByteArray) :
    Except String ByteArray :=
  if h : i < b.size then
    match huffmanDecodeBits b[i].toNat 8 code len out with
    | .ok (code, len, out) => huffmanDecodeFrom b (i + 1) code len out
    | .error e => .error e
  else if len > 7 then .error "hpack: Huffman padding longer than seven bits"
  else if code != 2 ^ len - 1 then .error "hpack: Huffman padding is not EOS"
  else .ok out
termination_by b.size - i

/-- Decodes a Huffman-coded string. -/
def huffmanDecode (b : ByteArray) : Except String ByteArray :=
  huffmanDecodeFrom b 0 0 0 .empty

/-- `acc` plus the number of bits in the Huffman codes of `b` from `i` on. -/
def huffmanBitsFrom (b : ByteArray) (i acc : Nat) : Nat :=
  if h : i < b.size then huffmanBitsFrom b (i + 1) (acc + (huffmanCodes[b[i].toNat]!).2.toNat)
  else acc
termination_by b.size - i

/-- The Huffman-coded length of `b`, in bytes. -/
def huffmanLength (b : ByteArray) : Nat := (huffmanBitsFrom b 0 0 + 7) / 8

/-- Appends the codes of the bytes of `b` from `i` on to `out`, after the `n`
    pending bits `acc`: whole bytes are written out, most significant bit first,
    as soon as there are eight bits, and the last byte is padded with ones.
    There are never more than 7 + 30 pending bits, so they fit in 64. -/
def huffmanEncodeFrom (b : ByteArray) (i : Nat) (acc n : UInt64) (out : ByteArray) : ByteArray :=
  if n ≥ 8 then
    huffmanEncodeFrom b i (acc &&& ((1 <<< (n - 8)) - 1)) (n - 8)
      (out.push (acc >>> (n - 8)).toUInt8)
  else if h : i < b.size then
    let c := huffmanCodes[b[i].toNat]!
    huffmanEncodeFrom b (i + 1) ((acc <<< c.2.toUInt64) ||| c.1.toUInt64) (n + c.2.toUInt64) out
  else if n > 0 then out.push ((acc <<< (8 - n)) ||| ((1 <<< (8 - n)) - 1)).toUInt8
  else out
termination_by (b.size - i, n.toNat)
decreasing_by
  · rename_i h
    apply Prod.Lex.right
    have h8 : 8 ≤ n.toNat := UInt64.le_iff_toNat_le.1 h
    rw [UInt64.toNat_sub_of_le _ _ h]
    simp only [UInt64.reduceToNat]
    omega
  · apply Prod.Lex.left
    omega

/-- Huffman-codes `b`, padding with ones. -/
def huffmanEncode (b : ByteArray) : ByteArray :=
  huffmanEncodeFrom b 0 0 0 (ByteArray.emptyWithCapacity (huffmanLength b))

/-! ### Encoding and decoding Huffman codes agree

The proofs follow the bits: `bitsOf v n` lists the low `n` bits of `v`, most
significant first, and `decodeBits` is the decoder reading them one at a time. -/

/-- The code of the byte `x`, and its length in bits. -/
private def codeOf (x : Nat) : Nat × Nat :=
  ((huffmanCodes[x]!).1.toNat, (huffmanCodes[x]!).2.toNat)

/-- The decoding tables agree with `huffmanCodes`: each byte's code fits in its
    length, of one to 30 bits, and decodes to the byte, while no shorter prefix
    of it decodes to anything; nor does padding, up to seven ones. Checked by
    the kernel, symbol by symbol. -/
private theorem huffmanSymbol?_code :
    (∀ s < 256, 0 < (codeOf s).2 ∧ (codeOf s).2 ≤ 30 ∧ (codeOf s).1 < 2 ^ (codeOf s).2 ∧
      huffmanSymbol? (codeOf s).2 (codeOf s).1 = some s.toUInt8 ∧
      ∀ j < (codeOf s).2, huffmanSymbol? j ((codeOf s).1 >>> ((codeOf s).2 - j)) = none) ∧
    ∀ l ≤ 7, huffmanSymbol? l (2 ^ l - 1) = none := by
  decide +kernel

/-- The low `n` bits of `v`, most significant first. -/
private def bitsOf (v : Nat) : Nat → List Bool
  | 0 => []
  | n + 1 => v.testBit n :: bitsOf v n

/-- The bits of some bytes. -/
private def bytesBits (l : List UInt8) : List Bool := l.flatMap fun x => bitsOf x.toNat 8

/-- The bits of the codes of some bytes. -/
private def codeBits (l : List UInt8) : List Bool :=
  l.flatMap fun x => bitsOf (codeOf x.toNat).1 (codeOf x.toNat).2

/-- `huffmanDecodeBits`, on a list of bits. -/
private def decodeBits : List Bool → (code len : Nat) → ByteArray →
    Except String (Nat × Nat × ByteArray)
  | [], code, len, out => .ok (code, len, out)
  | bit :: bits, code, len, out =>
    let code := code * 2 + bit.toNat
    let len := len + 1
    match huffmanSymbol? len code with
    | some sym => decodeBits bits 0 0 (out.push sym)
    | none =>
      if len ≥ 30 then .error "hpack: invalid Huffman code"
      else decodeBits bits code len out

private theorem length_bitsOf (v n : Nat) : (bitsOf v n).length = n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [bitsOf, ih]

private theorem bitsOf_congr {v w : Nat} :
    ∀ {n : Nat}, (∀ j < n, v.testBit j = w.testBit j) → bitsOf v n = bitsOf w n
  | 0, _ => rfl
  | n + 1, h => by
    simp only [bitsOf, h n (by omega), bitsOf_congr (n := n) (fun j hj => h j (by omega))]

/-- The top `a` bits, then the low `b`. -/
private theorem bitsOf_add (v a b : Nat) :
    bitsOf v (a + b) = bitsOf (v >>> b) a ++ bitsOf v b := by
  induction a with
  | zero => simp [bitsOf]
  | succ a ih =>
    rw [show a + 1 + b = (a + b) + 1 by omega, bitsOf, ih, bitsOf, Nat.testBit_shiftRight,
      Nat.add_comm b a, List.cons_append]

/-- `a`'s low `n` bits followed by the `m` bits `c`. -/
private theorem bitsOf_shiftLeft_add {c m : Nat} (a n : Nat) (hc : c < 2 ^ m) :
    bitsOf ((a <<< m) + c) (n + m) = bitsOf a n ++ bitsOf c m := by
  have hshift : ((a <<< m) + c) >>> m = a := by
    rw [Nat.shiftLeft_eq, Nat.shiftRight_eq_div_pow, Nat.mul_comm,
      Nat.mul_add_div (Nat.two_pow_pos m), Nat.div_eq_of_lt hc, Nat.add_zero]
  rw [bitsOf_add, hshift]
  congr 1
  apply bitsOf_congr
  intro j hj
  rw [Nat.shiftLeft_eq, Nat.mul_comm, Nat.testBit_two_pow_mul_add a hc, ite_eq_left hj]

private theorem bitsOf_mod (v n m : Nat) (h : n ≤ m) : bitsOf (v % 2 ^ m) n = bitsOf v n :=
  bitsOf_congr fun j hj => by simp [Nat.testBit_mod_two_pow, show j < m by omega]

private theorem bitsOf_toUInt8 (v : Nat) : bitsOf v.toUInt8.toNat 8 = bitsOf v 8 := by
  simp only [Nat.toUInt8_eq, UInt8.toNat_ofNat']
  exact bitsOf_mod v 8 8 (Nat.le_refl _)

private theorem bitsOf_ones (p q : Nat) (h : p ≤ q) :
    bitsOf (2 ^ q - 1) p = List.replicate p true := by
  induction p with
  | zero => rfl
  | succ p ih =>
    rw [bitsOf, ih (by omega), List.replicate_succ, Nat.testBit_two_pow_sub_one,
      decide_eq_true (by omega : p < q)]

@[simp] private theorem bytesBits_nil : bytesBits [] = [] := rfl

private theorem bytesBits_cons (x : UInt8) (l : List UInt8) :
    bytesBits (x :: l) = bitsOf x.toNat 8 ++ bytesBits l := by
  simp [bytesBits]

private theorem bytesBits_append (l l' : List UInt8) :
    bytesBits (l ++ l') = bytesBits l ++ bytesBits l' := by
  simp [bytesBits]

private theorem codeBits_cons (x : UInt8) (l : List UInt8) :
    codeBits (x :: l) = bitsOf (codeOf x.toNat).1 (codeOf x.toNat).2 ++ codeBits l := by
  simp [codeBits]

private theorem length_bytesBits (l : List UInt8) : (bytesBits l).length = 8 * l.length := by
  induction l with
  | nil => rfl
  | cons x l ih => simp only [bytesBits_cons, List.length_append, length_bitsOf, ih,
      List.length_cons]; omega

/-- The byte at `i` of `b`, as a list. -/
private theorem drop_toList (b : ByteArray) (i : Nat) (h : i < b.size) :
    b.data.toList.drop i = b[i] :: b.data.toList.drop (i + 1) := by
  rw [List.drop_eq_getElem_cons (by simpa using h)]
  simp [ByteArray.getElem_eq_getElem_data]

/-! #### The encoder -/

/-- The low `n` bits of `a` followed by the `m` bits `c`, all within 64 bits. -/
private theorem bitsOf_shiftLeft_or {c m : Nat} (a n : Nat) (hc : c < 2 ^ m) (h : n + m ≤ 64) :
    bitsOf ((a <<< m) % 2 ^ 64 ||| c) (n + m) = bitsOf a n ++ bitsOf c m := by
  rw [bitsOf_add]
  congr 1
  · apply bitsOf_congr
    intro j hj
    have hc' : c.testBit (m + j) = false :=
      Nat.testBit_lt_two_pow (Nat.lt_of_lt_of_le hc (Nat.pow_le_pow_right (by decide) (by omega)))
    simp only [Nat.testBit_shiftRight, Nat.testBit_or, Nat.testBit_mod_two_pow,
      Nat.testBit_shiftLeft, hc', Bool.or_false]
    simp [show m + j < 64 by omega]
  · apply bitsOf_congr
    intro j hj
    simp only [Nat.testBit_or, Nat.testBit_mod_two_pow, Nat.testBit_shiftLeft]
    simp [show ¬ m ≤ j by omega]

private theorem toNat_shiftLeft_or (a c m : UInt64) (hm : m.toNat < 64) :
    ((a <<< m) ||| c).toNat = (a.toNat <<< m.toNat) % 2 ^ 64 ||| c.toNat := by
  rw [UInt64.toNat_or, UInt64.toNat_shiftLeft, Nat.mod_eq_of_lt hm]

/-- `2 ^ k - 1`, as a word. -/
private theorem toNat_mask (k : UInt64) (hk : k.toNat < 64) :
    ((1 <<< k) - 1 : UInt64).toNat = 2 ^ k.toNat - 1 := by
  have hpow : (1 <<< k : UInt64).toNat = 2 ^ k.toNat := by
    rw [UInt64.toNat_shiftLeft, Nat.mod_eq_of_lt hk, UInt64.toNat_one, Nat.one_shiftLeft,
      Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by decide) hk)]
  rw [UInt64.toNat_sub_of_le _ _
      (UInt64.le_iff_toNat_le.2 (by rw [hpow]; exact Nat.one_le_two_pow)),
    hpow, UInt64.toNat_one]

/-- Encoding from `i` on writes the pending bits, then the codes of the rest of
    `b`, then fewer than eight ones. -/
private theorem huffmanEncodeFrom_spec (b : ByteArray) (i : Nat) (acc n : UInt64)
    (out : ByteArray) :
    n.toNat < 64 → ∃ p < 8, bytesBits (huffmanEncodeFrom b i acc n out).data.toList =
      bytesBits out.data.toList ++ bitsOf acc.toNat n.toNat ++ codeBits (b.data.toList.drop i) ++
        List.replicate p true := by
  fun_induction huffmanEncodeFrom b i acc n out with
  | case1 i acc n out h ih =>
    intro hn
    have h8 : 8 ≤ n.toNat := UInt64.le_iff_toNat_le.1 h
    have hsub : (n - 8).toNat = n.toNat - 8 := by
      rw [UInt64.toNat_sub_of_le _ _ h]
      rfl
    obtain ⟨p, hp, h'⟩ := ih (by omega)
    refine ⟨p, hp, ?_⟩
    have hsplit : bitsOf acc.toNat n.toNat =
        bitsOf (acc.toNat >>> (n.toNat - 8)) 8 ++ bitsOf acc.toNat (n.toNat - 8) := by
      have := bitsOf_add acc.toNat 8 (n.toNat - 8)
      rwa [show 8 + (n.toNat - 8) = n.toNat by omega] at this
    rw [h', ByteArray.data_push, Array.toList_push, bytesBits_append, bytesBits_cons,
      bytesBits_nil, List.append_nil, UInt64.toNat_and, toNat_mask _ (by omega), hsub,
      Nat.and_two_pow_sub_one_eq_mod, bitsOf_mod _ _ _ (Nat.le_refl _), UInt64.toNat_toUInt8,
      UInt64.toNat_shiftRight, hsub, Nat.mod_eq_of_lt (by omega : n.toNat - 8 < 64),
      bitsOf_mod _ _ _ (Nat.le_refl _), hsplit]
    simp only [List.append_assoc]
  | case2 i acc n out h hi c ih =>
    intro hn
    have hn8 : n.toNat < 8 := by
      have h' : ¬ (8 : UInt64).toNat ≤ n.toNat := fun h' => h (UInt64.le_iff_toNat_le.2 h')
      simp only [UInt64.reduceToNat] at h'
      omega
    have hc : codeOf b[i].toNat = (c.1.toNat, c.2.toNat) := rfl
    obtain ⟨-, hle, hlt, -, -⟩ := huffmanSymbol?_code.1 b[i].toNat (UInt8.toNat_lt _)
    rw [hc] at hle hlt
    have hadd : (n + c.2.toUInt64).toNat = n.toNat + c.2.toNat := by
      rw [UInt64.toNat_add, UInt8.toNat_toUInt64, Nat.mod_eq_of_lt (by omega)]
    obtain ⟨p, hp, h'⟩ := ih (by rw [hadd]; omega)
    refine ⟨p, hp, ?_⟩
    rw [h', hadd, toNat_shiftLeft_or _ _ _ (by rw [UInt8.toNat_toUInt64]; omega),
      UInt8.toNat_toUInt64, UInt32.toNat_toUInt64, bitsOf_shiftLeft_or _ _ hlt (by omega),
      drop_toList b i hi, codeBits_cons, hc]
    simp only [List.append_assoc]
  | case3 i acc n out h hi hpos =>
    intro hn
    have hn8 : n.toNat < 8 := by
      have h' : ¬ (8 : UInt64).toNat ≤ n.toNat := fun h' => h (UInt64.le_iff_toNat_le.2 h')
      simp only [UInt64.reduceToNat] at h'
      omega
    have hn0 : 0 < n.toNat := UInt64.lt_iff_toNat_lt.1 hpos
    have hsub : (8 - n).toNat = 8 - n.toNat := by
      rw [UInt64.toNat_sub_of_le _ _ (UInt64.le_iff_toNat_le.2 (by simp; omega))]
      rfl
    refine ⟨8 - n.toNat, by omega, ?_⟩
    have hlast := bitsOf_shiftLeft_or (c := 2 ^ (8 - n.toNat) - 1) (m := 8 - n.toNat) acc.toNat
      n.toNat (Nat.sub_lt (Nat.two_pow_pos _) Nat.one_pos) (by omega)
    rw [show n.toNat + (8 - n.toNat) = 8 by omega, bitsOf_ones _ _ (Nat.le_refl _)] at hlast
    rw [ByteArray.data_push, Array.toList_push, bytesBits_append, bytesBits_cons, bytesBits_nil,
      List.append_nil, UInt64.toNat_toUInt8, bitsOf_mod _ _ _ (Nat.le_refl _),
      toNat_shiftLeft_or _ _ _ (by omega), toNat_mask _ (by omega), hsub, hlast,
      List.drop_eq_nil_of_le (by simp; omega)]
    simp [codeBits]
  | case4 i acc n out h hi hpos =>
    intro hn
    refine ⟨0, by omega, ?_⟩
    have : n.toNat = 0 := by
      have h' : ¬ (0 : UInt64).toNat < n.toNat := fun h' => hpos (UInt64.lt_iff_toNat_lt.2 h')
      simp only [UInt64.reduceToNat] at h'
      omega
    rw [this, List.drop_eq_nil_of_le (by simp; omega)]
    simp [bitsOf, codeBits]

/-! #### The decoder -/

private theorem huffmanDecodeBits_eq (byte : Nat) :
    ∀ (k code len : Nat) (out : ByteArray),
    huffmanDecodeBits byte k code len out = decodeBits (bitsOf byte k) code len out := by
  intro k
  induction k with
  | zero => intro code len out; rfl
  | succ k ih =>
    intro code len out
    simp only [huffmanDecodeBits, bitsOf, decodeBits, Nat.toNat_testBit,
      Nat.shiftRight_eq_div_pow, ih]

private theorem decodeBits_append (l₁ l₂ : List Bool) :
    ∀ (code len : Nat) (out : ByteArray), decodeBits (l₁ ++ l₂) code len out =
      match decodeBits l₁ code len out with
      | .ok (code, len, out) => decodeBits l₂ code len out
      | .error e => .error e := by
  induction l₁ with
  | nil => intro code len out; rfl
  | cons bit bits ih =>
    intro code len out
    simp only [List.cons_append, decodeBits]
    cases huffmanSymbol? (len + 1) (code * 2 + bit.toNat) with
    | some sym => exact ih ..
    | none =>
      dsimp only
      split
      · rfl
      · exact ih ..

/-- Reading the last `k` bits of a byte's code, after the others, decodes the
    byte. -/
private theorem decodeBits_code (x : UInt8) (rest : List Bool) (out : ByteArray) :
    ∀ k, 0 < k → k ≤ (codeOf x.toNat).2 →
    decodeBits (bitsOf (codeOf x.toNat).1 k ++ rest) ((codeOf x.toNat).1 >>> k)
      ((codeOf x.toNat).2 - k) out = decodeBits rest 0 0 (out.push x) := by
  obtain ⟨-, hle, -, hsym, hpre⟩ := huffmanSymbol?_code.1 x.toNat (UInt8.toNat_lt _)
  rw [Nat.toUInt8_eq, UInt8.ofNat_toNat] at hsym
  generalize (codeOf x.toNat).1 = c at *
  generalize (codeOf x.toNat).2 = n at *
  intro k
  induction k with
  | zero => intro h; omega
  | succ k ih =>
    intro _ hk
    have hstep : (c >>> (k + 1)) * 2 + (c.testBit k).toNat = c >>> k := by
      rw [Nat.toNat_testBit, Nat.shiftRight_eq_div_pow, Nat.shiftRight_eq_div_pow, Nat.pow_succ,
        ← Nat.div_div_eq_div_mul]
      omega
    simp only [bitsOf, List.cons_append, decodeBits, hstep, show n - (k + 1) + 1 = n - k by omega]
    rcases Nat.eq_zero_or_pos k with rfl | hk0
    · simp [hsym, bitsOf]
    · rw [show c >>> k = c >>> (n - (n - k)) by rw [Nat.sub_sub_self (by omega)],
        hpre (n - k) (by omega), Nat.sub_sub_self (by omega)]
      simp only [show ¬ n - k ≥ 30 by omega, ↓reduceIte]
      rw [show n - k = n - k by rfl]
      exact ih hk0 (by omega)

/-- Decoding the codes of some bytes pushes them. -/
private theorem decodeBits_codeBits (rest : List Bool) :
    ∀ (l : List UInt8) (out : ByteArray),
    decodeBits (codeBits l ++ rest) 0 0 out = decodeBits rest 0 0 (l.foldl ByteArray.push out) := by
  intro l
  induction l with
  | nil => intro out; rfl
  | cons x l ih =>
    intro out
    obtain ⟨hpos, -, hlt, -, -⟩ := huffmanSymbol?_code.1 x.toNat (UInt8.toNat_lt _)
    have h := decodeBits_code x (codeBits l ++ rest) out (codeOf x.toNat).2 hpos (Nat.le_refl _)
    rw [Nat.sub_self, Nat.shiftRight_eq_div_pow, Nat.div_eq_of_lt hlt] at h
    rw [codeBits_cons, List.append_assoc, h, ih]
    rfl

/-- Decoding padding of up to seven ones leaves it pending. -/
private theorem decodeBits_ones (out : ByteArray) :
    ∀ p l, l + p ≤ 7 →
    decodeBits (List.replicate p true) (2 ^ l - 1) l out = .ok (2 ^ (l + p) - 1, l + p, out) := by
  intro p
  induction p with
  | zero => intro l _; rfl
  | succ p ih =>
    intro l hl
    have hone : (2 ^ l - 1) * 2 + true.toNat = 2 ^ (l + 1) - 1 := by
      have := Nat.one_le_two_pow (n := l)
      rw [Nat.pow_succ]
      simp only [Bool.toNat_true]
      omega
    simp only [List.replicate_succ, decodeBits, hone, huffmanSymbol?_code.2 (l + 1) (by omega),
      show ¬ l + 1 ≥ 30 by omega, ↓reduceIte]
    rw [ih (l + 1) (by omega), show l + 1 + p = l + (p + 1) by omega]

/-- Decoding succeeds where decoding the bits leaves at most seven pending ones. -/
private theorem huffmanDecodeFrom_of_decodeBits (b : ByteArray) :
    ∀ (k i code len : Nat) (out : ByteArray) (l : Nat) (o : ByteArray), b.size - i = k →
    decodeBits (bytesBits (b.data.toList.drop i)) code len out = .ok (2 ^ l - 1, l, o) →
    l ≤ 7 → huffmanDecodeFrom b i code len out = .ok o := by
  intro k
  induction k with
  | zero =>
    intro i code len out l o hk h hl
    rw [List.drop_eq_nil_of_le (by simp; omega)] at h
    simp only [bytesBits_nil, decodeBits, Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    rw [huffmanDecodeFrom, dite_eq_right (by omega)]
    simpa using hl
  | succ k ih =>
    intro i code len out l o hk h hl
    have hi : i < b.size := by omega
    rw [drop_toList b i hi, bytesBits_cons, decodeBits_append] at h
    rw [huffmanDecodeFrom, dite_eq_left hi, huffmanDecodeBits_eq]
    split at h
    · rename_i code' len' out' h1
      exact ih (i + 1) code' len' out' l o (by omega) h hl
    · simp at h

private theorem data_foldl_push (l : List UInt8) :
    ∀ out : ByteArray, (l.foldl ByteArray.push out).data.toList = out.data.toList ++ l := by
  induction l with
  | nil => intro out; simp
  | cons x l ih => intro out; simp [ih, ByteArray.data_push]

private theorem bytesBits_huffmanEncode (b : ByteArray) :
    ∃ p < 8, bytesBits (huffmanEncode b).data.toList =
      codeBits b.data.toList ++ List.replicate p true := by
  obtain ⟨p, hp, h⟩ := huffmanEncodeFrom_spec b 0 0 0
    (ByteArray.emptyWithCapacity (huffmanLength b)) (by decide)
  have hempty : (ByteArray.emptyWithCapacity (huffmanLength b)).data.toList = [] := rfl
  exact ⟨p, hp, by simpa [huffmanEncode, bitsOf, hempty] using h⟩

/-- Huffman decoding undoes Huffman encoding. -/
theorem huffmanDecode_huffmanEncode (b : ByteArray) : huffmanDecode (huffmanEncode b) = .ok b := by
  obtain ⟨p, hp, hbits⟩ := bytesBits_huffmanEncode b
  have hb : b.data.toList.foldl ByteArray.push .empty = b := by
    apply ByteArray.ext
    apply Array.ext'
    rw [data_foldl_push]
    simp
  have hdec := decodeBits_codeBits (List.replicate p true) b.data.toList .empty
  have hpad := decodeBits_ones b p 0 (by omega)
  rw [hb] at hdec
  simp only [Nat.pow_zero, Nat.sub_self, Nat.zero_add] at hpad
  exact huffmanDecodeFrom_of_decodeBits _ _ 0 0 0 .empty p b rfl
    (by rw [List.drop_zero, hbits, hdec, hpad]) (by omega)

/-- `huffmanLength` is the length of the encoding. -/
private theorem huffmanBitsFrom_eq (b : ByteArray) (i acc : Nat) :
    huffmanBitsFrom b i acc = acc + (codeBits (b.data.toList.drop i)).length := by
  fun_induction huffmanBitsFrom b i acc with
  | case1 i acc h ih =>
    rw [ih, drop_toList b i h, codeBits_cons, List.length_append, length_bitsOf]
    simp only [codeOf]
    omega
  | case2 i acc h =>
    rw [List.drop_eq_nil_of_le (by simp; omega)]
    rfl

theorem size_huffmanEncode (b : ByteArray) : (huffmanEncode b).size = huffmanLength b := by
  obtain ⟨p, hp, hbits⟩ := bytesBits_huffmanEncode b
  have hlen := congrArg List.length hbits
  rw [length_bytesBits, List.length_append, List.length_replicate, Array.length_toList,
    ByteArray.size_data] at hlen
  have hT := huffmanBitsFrom_eq b 0 0
  rw [List.drop_zero, Nat.zero_add] at hT
  unfold huffmanLength
  omega

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

/-! ### Encoding and decoding strings agree -/

private theorem lt_size_encodeInt (out : ByteArray) (n : Nat) (flags : UInt8) (v : Nat) :
    out.size < (encodeInt out n flags v).size := by
  unfold encodeInt
  dsimp only
  split
  · simp [ByteArray.size_push]
  · have := lt_size_encodeIntRest (out.push (flags ||| (2 ^ n - 1).toUInt8)) (v - (2 ^ n - 1))
    simp only [ByteArray.size_push] at this
    omega

/-- The first byte `encodeInt` writes: the flags, and the value or the prefix's
    maximum. -/
private theorem getElem!_encodeInt (out : ByteArray) (n : Nat) (flags : UInt8) (v : Nat) :
    (encodeInt out n flags v)[out.size]! = flags ||| (min v (2 ^ n - 1)).toUInt8 := by
  unfold encodeInt
  dsimp only
  split
  · rw [ByteArray.getElem!_push_eq, Nat.min_eq_left (by omega)]
  · rw [getElem!_encodeIntRest _ _ _ (by simp [ByteArray.size_push]), ByteArray.getElem!_push_eq,
      Nat.min_eq_right (by omega)]

private theorem fromUTF8?_toUTF8 (s : String) : String.fromUTF8? s.toUTF8 = some s := by
  simp only [String.fromUTF8?, String.toUTF8_eq_toByteArray, dite_eq_left s.isValidUTF8]
  rfl

/-- Decoding a length with `flags`, then `P`, which decodes to `s`'s bytes,
    followed by anything, gives back `s` and the position just past `P`. -/
private theorem decodeString_encodeInt (out rest P : ByteArray) (s : String) (flags : UInt8)
    (hflags : flags.toNat % 2 ^ 7 = 0) (hsize : P.size ≤ 2 ^ 32)
    (hP : (if (flags ||| (min P.size 127).toUInt8) &&& 0x80 != 0 then huffmanDecode P else .ok P) =
      .ok s.toUTF8) :
    decodeString (encodeInt out 7 flags P.size ++ P ++ rest) out.size =
      .ok (s, (encodeInt out 7 flags P.size ++ P).size) := by
  have hlt := lt_size_encodeInt out 7 flags P.size
  have hbyte := getElem!_encodeInt out 7 flags P.size
  have hint :=
    decodeInt_encodeInt out (P ++ rest) 7 flags P.size ⟨by decide, by decide⟩ hflags hsize
  rw [← ByteArray.append_assoc] at hint
  generalize encodeInt out 7 flags P.size = E at hlt hbyte hint ⊢
  have hpos : out.size < (E ++ P ++ rest).size := by simp only [ByteArray.size_append]; omega
  have hfirst : (E ++ P ++ rest)[out.size]'hpos = flags ||| (min P.size 127).toUInt8 := by
    rw [← getElem!_pos, ByteArray.append_assoc, getElem!_append_left' _ _ _ hlt, hbyte]
  have hextract : (E ++ P ++ rest).extract E.size (E.size + P.size) = P := by
    rw [ByteArray.append_assoc, ByteArray.extract_append, Nat.sub_self, Nat.add_sub_cancel_left,
      ByteArray.extract_append_eq_left rfl, ByteArray.extract_eq_empty_iff.2 (by omega),
      ByteArray.empty_append]
  unfold decodeString
  simp only [hint, hfirst, hextract, hP, fromUTF8?_toUTF8, ByteArray.size_append]
  rw [dite_eq_left (by omega), ite_eq_right (by omega)]

/-- Decoding what `encodeString` wrote, followed by anything, gives back the
    string and the position just past it, for strings of up to 2^32 bytes. -/
theorem decodeString_encodeString (out rest : ByteArray) (s : String)
    (hs : s.utf8ByteSize ≤ 2 ^ 32) :
    decodeString (encodeString out s ++ rest) out.size = .ok (s, (encodeString out s).size) := by
  unfold encodeString
  dsimp only
  split
  · rename_i hlt
    rw [← size_huffmanEncode s.toUTF8]
    have htop : ∀ v < 128, ((0x80 ||| v.toUInt8) &&& 0x80 != 0 : Bool) = true := by decide
    apply decodeString_encodeInt _ _ _ _ _ (by decide)
      (by rw [size_huffmanEncode]; simp only [String.toUTF8_eq_toByteArray,
        String.size_toByteArray] at hlt ⊢; omega)
    rw [htop _ (by omega), ite_eq_left rfl, huffmanDecode_huffmanEncode]
  · have htop : ∀ v < 128, ((0 ||| v.toUInt8) &&& 0x80 != 0 : Bool) = false := by decide
    apply decodeString_encodeInt _ _ _ _ _ (by decide)
      (by simpa only [String.toUTF8_eq_toByteArray, String.size_toByteArray] using hs)
    rw [htop _ (by omega)]
    rfl

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
