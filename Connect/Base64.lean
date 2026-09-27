module

public section

/-!
# Base64

Connect uses base64 in three places: binary headers (keys ending in `-bin`),
the `value` of error details in JSON, and the `message` query parameter of GET
requests. Senders use a specific alphabet and padding for each, but receivers
must accept all of them, so decoding here accepts either alphabet, with or
without padding.

`decode?_encode` and `decode?_encodeUrl` prove that decoding gives back what
either encoder wrote, padded or not.
-/

namespace Connect.Base64

/-- The character for the six-bit value `n`: `A`–`Z`, `a`–`z`, `0`–`9`, then
    `+` and `/`, or `-` and `_` in the URL-safe alphabet (RFC 4648 §4, §5). -/
private def sym (url : Bool) (n : Nat) : Char :=
  if n < 26 then Char.ofNat (n + 65)
  else if n < 52 then Char.ofNat (n + 71)
  else if n < 62 then Char.ofNat (n - 4)
  else if n = 62 then if url then '-' else '+'
  else if url then '_' else '/'

/-- The standard alphabet: `sym`, tabulated. -/
private def stdAlphabet : Array Char := ((List.range 64).map (sym false)).toArray

/-- The URL-safe alphabet. -/
private def urlAlphabet : Array Char := ((List.range 64).map (sym true)).toArray

/-- Encodes the bytes of `data` from `i` on, each three as four characters;
    one or two left over become two or three, padded with `=` if `padding`. -/
private def encodeFrom (alphabet : Array Char) (data : ByteArray) (padding : Bool) (i : Nat)
    (out : String) : String :=
  if h : i + 3 ≤ data.size then
    let n := data[i].toNat * 65536 + data[i + 1].toNat * 256 + data[i + 2].toNat
    let out := out.push alphabet[n / 262144]! |>.push alphabet[n / 4096 % 64]!
      |>.push alphabet[n / 64 % 64]! |>.push alphabet[n % 64]!
    encodeFrom alphabet data padding (i + 3) out
  else if h : i + 2 = data.size then
    let n := data[i].toNat * 65536 + data[i + 1].toNat * 256
    let out := out.push alphabet[n / 262144]! |>.push alphabet[n / 4096 % 64]!
      |>.push alphabet[n / 64 % 64]!
    if padding then out.push '=' else out
  else if h : i + 1 = data.size then
    let n := data[i].toNat * 65536
    let out := out.push alphabet[n / 262144]! |>.push alphabet[n / 4096 % 64]!
    if padding then out.push '=' |>.push '=' else out
  else out
termination_by data.size - i

/-- Standard base64 (RFC 4648 §4), padded by default. -/
def encode (data : ByteArray) (padding : Bool := true) : String :=
  encodeFrom stdAlphabet data padding 0 ""

/-- URL-safe base64 (RFC 4648 §5), unpadded by default. -/
def encodeUrl (data : ByteArray) (padding : Bool := false) : String :=
  encodeFrom urlAlphabet data padding 0 ""

/-- The six-bit value of a character, in either alphabet. -/
private def value? (c : Char) : Option UInt32 :=
  if 'A' ≤ c ∧ c ≤ 'Z' then some (c.toNat - 'A'.toNat).toUInt32
  else if 'a' ≤ c ∧ c ≤ 'z' then some (c.toNat - 'a'.toNat + 26).toUInt32
  else if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat + 52).toUInt32
  else if c = '+' ∨ c = '-' then some 62
  else if c = '/' ∨ c = '_' then some 63
  else none

/-- Decodes `cs` after the `bits` pending bits `acc`: each character adds six
    bits, and every eight make a byte. Bits left over at the end are dropped. -/
private def decodeChars : List Char → (acc bits : UInt32) → ByteArray → Option ByteArray
  | [], _, _, out => some out
  | c :: cs, acc, bits, out =>
    match value? c with
    | none => none
    | some v =>
      let acc := (acc <<< 6) ||| v
      if bits ≥ 2 then
        decodeChars cs (acc &&& ((1 <<< (bits - 2)) - 1)) (bits - 2)
          (out.push (acc >>> (bits - 2)).toUInt8)
      else decodeChars cs acc (bits + 6) out

/-- Decodes base64 in either alphabet, with or without `=` padding.
    Returns `none` for any other character or an impossible length. -/
def decode? (s : String) : Option ByteArray :=
  let chars := (s.toList.reverse.dropWhile (· == '=')).reverse
  if chars.length % 4 == 1 then none
  else decodeChars chars 0 0 (ByteArray.emptyWithCapacity (chars.length * 3 / 4 + 3))

/-! ## Decoding undoes encoding -/

private theorem value?_sym (url : Bool) : ∀ n < 64, value? (sym url n) = some n.toUInt32 := by
  cases url <;> decide +kernel

private theorem sym_ne (url : Bool) : ∀ n < 64, sym url n ≠ '=' := by
  cases url <;> decide +kernel

private theorem getElem!_stdAlphabet : ∀ n < 64, stdAlphabet[n]! = sym false n := by
  decide +kernel

private theorem getElem!_urlAlphabet : ∀ n < 64, urlAlphabet[n]! = sym true n := by
  decide +kernel

/-! ### Decoding, on numbers

The decoder keeps its bits in 32-bit words. The proofs reason about the same
decoder on natural numbers, which gives the same results. -/

/-- `decodeChars`, on natural numbers. -/
private def decodeCharsN : List Char → (acc bits : Nat) → ByteArray → Option ByteArray
  | [], _, _, out => some out
  | c :: cs, acc, bits, out =>
    match value? c with
    | none => none
    | some v =>
      let acc := acc * 64 + v.toNat
      if bits ≥ 2 then
        decodeCharsN cs (acc % 2 ^ (bits - 2)) (bits - 2) (out.push (acc / 2 ^ (bits - 2)).toUInt8)
      else decodeCharsN cs acc (bits + 6) out

private theorem value?_lt {c : Char} {v : UInt32} (h : value? c = some v) : v.toNat < 64 := by
  have hc : c.toNat = c.val.toNat := rfl
  have hA : 'A'.toNat = 65 := rfl
  have ha : 'a'.toNat = 97 := rfl
  have h0 : '0'.toNat = 48 := rfl
  unfold value? at h
  split at h
  · rename_i hr
    simp only [Option.some.injEq] at h
    subst h
    have : c.val.toNat ≤ 90 := hr.2
    simp only [Nat.toUInt32_eq, UInt32.toNat_ofNat']
    omega
  · split at h
    · rename_i hr
      simp only [Option.some.injEq] at h
      subst h
      have : c.val.toNat ≤ 122 := hr.2
      simp only [Nat.toUInt32_eq, UInt32.toNat_ofNat']
      omega
    · split at h
      · rename_i hr
        simp only [Option.some.injEq] at h
        subst h
        have : c.val.toNat ≤ 57 := hr.2
        simp only [Nat.toUInt32_eq, UInt32.toNat_ofNat']
        omega
      · split at h
        · simp only [Option.some.injEq] at h
          subst h
          decide
        · split at h
          · simp only [Option.some.injEq] at h
            subst h
            decide
          · simp at h

/-- The words hold what the numbers do: bits fewer than eight, and no more of
    them than that. -/
private theorem decodeChars_eq : ∀ (cs : List Char) (acc bits : UInt32) (out : ByteArray),
    acc.toNat < 2 ^ bits.toNat → bits.toNat ≤ 7 →
    decodeChars cs acc bits out = decodeCharsN cs acc.toNat bits.toNat out := by
  intro cs
  induction cs with
  | nil => intro acc bits out _ _; rfl
  | cons c cs ih =>
    intro acc bits out hacc hbits
    simp only [decodeChars, decodeCharsN]
    cases hv : value? c with
    | none => rfl
    | some v =>
      have hv64 := value?_lt hv
      have hpow : 2 ^ bits.toNat ≤ 2 ^ 7 := Nat.pow_le_pow_right (by decide) hbits
      -- The new bits join the pending ones, as a number too.
      have hjoin : ((acc <<< 6) ||| v).toNat = acc.toNat * 64 + v.toNat := by
        rw [UInt32.toNat_or, UInt32.toNat_shiftLeft, show (6 : UInt32).toNat % 32 = 6 from rfl,
          Nat.mod_eq_of_lt (by rw [Nat.shiftLeft_eq]; omega),
          ← Nat.shiftLeft_add_eq_or_of_lt (by omega), Nat.shiftLeft_eq]
      dsimp only
      split
      · rename_i h2
        have h2' : 2 ≤ bits.toNat := UInt32.le_iff_toNat_le.1 h2
        have hsub : (bits - 2).toNat = bits.toNat - 2 := by
          rw [UInt32.toNat_sub_of_le _ _ h2]
          rfl
        have hk : (bits - 2).toNat % 32 = bits.toNat - 2 := by rw [hsub]; omega
        have hmask : ((1 <<< (bits - 2)) - 1 : UInt32).toNat = 2 ^ (bits.toNat - 2) - 1 := by
          have hp : (1 <<< (bits - 2) : UInt32).toNat = 2 ^ (bits.toNat - 2) := by
            rw [UInt32.toNat_shiftLeft, hk, UInt32.toNat_one, Nat.one_shiftLeft]
            exact Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by decide) (by omega))
          rw [UInt32.toNat_sub_of_le _ _
              (UInt32.le_iff_toNat_le.2 (by rw [hp]; exact Nat.one_le_two_pow)),
            hp, UInt32.toNat_one]
        rw [ite_eq_left (show bits.toNat ≥ 2 from h2')]
        have hbyte : (((acc <<< 6) ||| v) >>> (bits - 2)).toUInt8 =
            ((acc.toNat * 64 + v.toNat) / 2 ^ (bits.toNat - 2)).toUInt8 := by
          apply UInt8.toNat_inj.1
          rw [UInt32.toNat_toUInt8, UInt32.toNat_shiftRight, hjoin, hk, Nat.shiftRight_eq_div_pow,
            Nat.toUInt8_eq, UInt8.toNat_ofNat']
        rw [hbyte, ih _ _ _ (by
            rw [UInt32.toNat_and, hmask, hsub, Nat.and_two_pow_sub_one_eq_mod]
            exact Nat.mod_lt _ (Nat.two_pow_pos _)) (by rw [hsub]; omega)]
        rw [UInt32.toNat_and, hmask, hsub, Nat.and_two_pow_sub_one_eq_mod, hjoin]
      · rename_i h2
        have h2' : bits.toNat < 2 := by
          have : ¬ (2 : UInt32).toNat ≤ bits.toNat := fun h' => h2 (UInt32.le_iff_toNat_le.2 h')
          simp only [UInt32.reduceToNat] at this
          omega
        have hadd : (bits + 6).toNat = bits.toNat + 6 := by
          rw [UInt32.toNat_add, Nat.mod_eq_of_lt (by simp; omega)]
          rfl
        rw [ite_eq_right (show ¬ bits.toNat ≥ 2 by omega), ih _ _ _ (by
            rw [hjoin, hadd, Nat.pow_add]
            have : acc.toNat * 64 + v.toNat < (acc.toNat + 1) * 64 := by omega
            have : (acc.toNat + 1) * 64 ≤ 2 ^ bits.toNat * 2 ^ 6 :=
              Nat.mul_le_mul (by omega) (by decide)
            omega) (by rw [hadd]; omega), hjoin, hadd]

private theorem decodeCharsN_sym (url : Bool) {v : Nat} (hv : v < 64) (cs : List Char)
    (acc bits : Nat) (out : ByteArray) :
    decodeCharsN (sym url v :: cs) acc bits out =
      if bits ≥ 2 then
        decodeCharsN cs ((acc * 64 + v) % 2 ^ (bits - 2)) (bits - 2)
          (out.push ((acc * 64 + v) / 2 ^ (bits - 2)).toUInt8)
      else decodeCharsN cs (acc * 64 + v) (bits + 6) out := by
  have hv' : v.toUInt32.toNat = v := by
    simp only [Nat.toUInt32_eq, UInt32.toNat_ofNat']
    omega
  simp only [decodeCharsN, value?_sym url v hv, hv']

private theorem toUInt8_eq {x : Nat} {b : UInt8} (h : x = b.toNat) : x.toUInt8 = b := by
  subst h; simp

/-- The four characters of three bytes decode to them. -/
private theorem decodeCharsN_three (url : Bool) (b₀ b₁ b₂ : UInt8) (rest : List Char)
    (out : ByteArray) :
    let n := b₀.toNat * 65536 + b₁.toNat * 256 + b₂.toNat
    decodeCharsN (sym url (n / 262144) :: sym url (n / 4096 % 64) :: sym url (n / 64 % 64) ::
      sym url (n % 64) :: rest) 0 0 out =
      decodeCharsN rest 0 0 (((out.push b₀).push b₁).push b₂) := by
  intro n
  have h₀ := b₀.toNat_lt
  have h₁ := b₁.toNat_lt
  have h₂ := b₂.toNat_lt
  simp (config := { decide := true }) only [decodeCharsN_sym url (v := n / 262144) (by omega),
    decodeCharsN_sym url (v := n / 4096 % 64) (by omega),
    decodeCharsN_sym url (v := n / 64 % 64) (by omega),
    decodeCharsN_sym url (v := n % 64) (by omega),
    ↓reduceIte, Nat.reduceSub, Nat.reducePow, Nat.zero_mul, Nat.zero_add, Nat.mod_one, Nat.div_one]
  rw [toUInt8_eq (b := b₀) (by omega), toUInt8_eq (b := b₁) (by omega),
    toUInt8_eq (b := b₂) (by omega)]

/-- The three characters of two last bytes decode to them. -/
private theorem decodeCharsN_two (url : Bool) (b₀ b₁ : UInt8) (out : ByteArray) :
    let n := b₀.toNat * 65536 + b₁.toNat * 256
    decodeCharsN [sym url (n / 262144), sym url (n / 4096 % 64), sym url (n / 64 % 64)] 0 0 out =
      some ((out.push b₀).push b₁) := by
  intro n
  have h₀ := b₀.toNat_lt
  have h₁ := b₁.toNat_lt
  simp (config := { decide := true }) only [decodeCharsN_sym url (v := n / 262144) (by omega),
    decodeCharsN_sym url (v := n / 4096 % 64) (by omega),
    decodeCharsN_sym url (v := n / 64 % 64) (by omega),
    ↓reduceIte, Nat.reduceSub, Nat.reducePow, Nat.zero_mul, Nat.zero_add, decodeCharsN.eq_1]
  rw [toUInt8_eq (b := b₀) (by omega), toUInt8_eq (b := b₁) (by omega)]

/-- The two characters of one last byte decode to it. -/
private theorem decodeCharsN_one (url : Bool) (b₀ : UInt8) (out : ByteArray) :
    let n := b₀.toNat * 65536
    decodeCharsN [sym url (n / 262144), sym url (n / 4096 % 64)] 0 0 out = some (out.push b₀) := by
  intro n
  have h₀ := b₀.toNat_lt
  simp (config := { decide := true }) only [decodeCharsN_sym url (v := n / 262144) (by omega),
    decodeCharsN_sym url (v := n / 4096 % 64) (by omega),
    ↓reduceIte, Nat.reduceSub, Nat.reducePow, Nat.zero_mul, Nat.zero_add, decodeCharsN.eq_1]
  rw [toUInt8_eq (b := b₀) (by omega)]

/-- The byte at `i` of `data`, as a list. -/
private theorem drop_toList (data : ByteArray) (i : Nat) (h : i < data.size) :
    data.data.toList.drop i = data[i] :: data.data.toList.drop (i + 1) := by
  rw [List.drop_eq_getElem_cons (by simpa using h)]
  simp [ByteArray.getElem_eq_getElem_data]

/-- What encoding from `i` on appends: characters that decode to the bytes from
    `i` on, whose number is not one more than a multiple of four, then padding. -/
private theorem encodeFrom_spec (alphabet : Array Char) (url : Bool)
    (halpha : ∀ n < 64, alphabet[n]! = sym url n) (data : ByteArray) (padding : Bool) (i : Nat)
    (out : String) :
    ∃ body pad : List Char,
      (encodeFrom alphabet data padding i out).toList = out.toList ++ body ++ pad ∧
      (∀ c ∈ body, c ≠ '=') ∧ (∀ c ∈ pad, c = '=') ∧ body.length % 4 ≠ 1 ∧
      ∀ o : ByteArray, i ≤ data.size →
        (decodeCharsN body 0 0 o).map (·.data.toList) =
          some (o.data.toList ++ data.data.toList.drop i) := by
  fun_induction encodeFrom alphabet data padding i out with
  | case1 i out h n out' ih =>
    obtain ⟨body, pad, hs, hb, hp, hlen, hdec⟩ := ih
    have h₀ := data[i].toNat_lt
    have h₁ := data[i + 1].toNat_lt
    have h₂ := data[i + 2].toNat_lt
    refine ⟨sym url (n / 262144) :: sym url (n / 4096 % 64) :: sym url (n / 64 % 64) ::
      sym url (n % 64) :: body, pad, ?_, ?_, hp, ?_, ?_⟩
    · rw [hs]
      simp [out', halpha _ (show n / 262144 < 64 by omega),
        halpha _ (show n / 4096 % 64 < 64 by omega),
        halpha _ (show n / 64 % 64 < 64 by omega), halpha _ (show n % 64 < 64 by omega)]
    · intro c hc
      simp only [List.mem_cons] at hc
      rcases hc with rfl | rfl | rfl | rfl | hc
      all_goals first | exact hb c hc | exact sym_ne url _ (by omega)
    · simp only [List.length_cons]; omega
    · intro o _
      rw [decodeCharsN_three, hdec _ (by omega), drop_toList data i (by omega),
        drop_toList data (i + 1) (by omega), drop_toList data (i + 2) (by omega)]
      simp
  | case2 i out h h' n out' hpad | case3 i out h h' n out' hpad =>
    have h₀ := data[i].toNat_lt
    have h₁ := data[i + 1].toNat_lt
    refine ⟨[sym url (n / 262144), sym url (n / 4096 % 64), sym url (n / 64 % 64)],
      if padding then ['='] else [], ?_, ?_, ?_, by simp, ?_⟩
    · simp [out', hpad, halpha _ (show n / 262144 < 64 by omega),
        halpha _ (show n / 4096 % 64 < 64 by omega), halpha _ (show n / 64 % 64 < 64 by omega)]
    · intro c hc
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl | rfl
      all_goals exact sym_ne url _ (by omega)
    · split <;> simp
    · intro o _
      rw [decodeCharsN_two, drop_toList data i (by omega), drop_toList data (i + 1) (by omega),
        List.drop_eq_nil_of_le (by simp; omega)]
      simp
  | case4 i out h h' h'' n out' hpad | case5 i out h h' h'' n out' hpad =>
    have h₀ := data[i].toNat_lt
    refine ⟨[sym url (n / 262144), sym url (n / 4096 % 64)],
      if padding then ['=', '='] else [], ?_, ?_, ?_, by simp, ?_⟩
    · simp [out', hpad, halpha _ (show n / 262144 < 64 by omega),
        halpha _ (show n / 4096 % 64 < 64 by omega)]
    · intro c hc
      simp only [List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl
      all_goals exact sym_ne url _ (by omega)
    · split <;> simp
    · intro o _
      rw [decodeCharsN_one, drop_toList data i (by omega), List.drop_eq_nil_of_le (by simp; omega)]
      simp
  | case6 i out h h' h'' =>
    refine ⟨[], [], by simp, by simp, by simp, by simp, ?_⟩
    intro o hi
    rw [List.drop_eq_nil_of_le (by simp; omega)]
    simp [decodeCharsN]

/-- Dropping the `=` padding leaves the characters before it. -/
private theorem strip_padding (body pad : List Char) (hb : ∀ c ∈ body, c ≠ '=')
    (hp : ∀ c ∈ pad, c = '=') : ((body ++ pad).reverse.dropWhile (· == '=')).reverse = body := by
  have hdrop : ∀ l : List Char, (∀ c ∈ l, c = '=') →
      (l ++ body.reverse).dropWhile (· == '=') = body.reverse.dropWhile (· == '=') := by
    intro l hl
    induction l with
    | nil => rfl
    | cons c cs ih =>
      rw [List.cons_append, List.dropWhile_cons_of_pos (by simp [hl c (by simp)])]
      exact ih (fun c hc => hl c (by simp [hc]))
  have hbody : body.reverse.dropWhile (· == '=') = body.reverse := by
    cases h : body.reverse with
    | nil => rfl
    | cons c cs =>
      have : c ≠ '=' := hb c (by rw [← List.mem_reverse, h]; simp)
      rw [List.dropWhile_cons_of_neg (by simpa using this)]
  rw [List.reverse_append, hdrop pad.reverse (by simpa using hp), hbody, List.reverse_reverse]

private theorem decode?_encodeFrom (alphabet : Array Char) (url : Bool)
    (halpha : ∀ n < 64, alphabet[n]! = sym url n) (data : ByteArray) (padding : Bool) :
    decode? (encodeFrom alphabet data padding 0 "") = some data := by
  obtain ⟨body, pad, hs, hb, hp, hlen, hdec⟩ :=
    encodeFrom_spec alphabet url halpha data padding 0 ""
  unfold decode?
  simp only [hs, String.toList_empty, List.nil_append, strip_padding body pad hb hp]
  simp only [beq_iff_eq, hlen, ↓reduceIte]
  rw [decodeChars_eq _ _ _ _ (by decide) (by decide)]
  simp only [UInt32.reduceToNat]
  have := hdec (ByteArray.emptyWithCapacity (body.length * 3 / 4 + 3)) (Nat.zero_le _)
  obtain ⟨x, hx, hdata⟩ := Option.map_eq_some_iff.1 this
  rw [hx]
  congr 1
  apply ByteArray.ext
  apply Array.ext'
  rw [hdata]
  rfl

/-- Decoding gives back what `encode` wrote, padded or not. -/
theorem decode?_encode (data : ByteArray) (padding : Bool) :
    decode? (encode data padding) = some data :=
  decode?_encodeFrom stdAlphabet false getElem!_stdAlphabet data padding

/-- Decoding gives back what `encodeUrl` wrote, padded or not. -/
theorem decode?_encodeUrl (data : ByteArray) (padding : Bool) :
    decode? (encodeUrl data padding) = some data :=
  decode?_encodeFrom urlAlphabet true getElem!_urlAlphabet data padding

end Connect.Base64
