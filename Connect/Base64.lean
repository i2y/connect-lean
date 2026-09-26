module

public section

/-!
# Base64

Connect uses base64 in three places: binary headers (keys ending in `-bin`),
the `value` of error details in JSON, and the `message` query parameter of GET
requests. Senders use a specific alphabet and padding for each, but receivers
must accept all of them, so decoding here accepts either alphabet, with or
without padding.
-/

namespace Connect.Base64

private def stdAlphabet : String :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

private def urlAlphabet : String :=
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

private def encodeWith (alphabet : Array Char) (data : ByteArray) (padding : Bool) : String := Id.run do
  let sym (n : UInt32) : Char := alphabet[(n &&& 63).toNat]!
  let mut out := ""
  let mut i := 0
  while i + 3 ≤ data.size do
    let n := (data[i]!.toUInt32 <<< 16) ||| (data[i+1]!.toUInt32 <<< 8) ||| data[i+2]!.toUInt32
    out := out.push (sym (n >>> 18)) |>.push (sym (n >>> 12)) |>.push (sym (n >>> 6)) |>.push (sym n)
    i := i + 3
  let rest := data.size - i
  if rest == 1 then
    let n := data[i]!.toUInt32 <<< 16
    out := out.push (sym (n >>> 18)) |>.push (sym (n >>> 12))
    if padding then out := out ++ "=="
  else if rest == 2 then
    let n := (data[i]!.toUInt32 <<< 16) ||| (data[i+1]!.toUInt32 <<< 8)
    out := out.push (sym (n >>> 18)) |>.push (sym (n >>> 12)) |>.push (sym (n >>> 6))
    if padding then out := out.push '='
  return out

/-- Standard base64 (RFC 4648 §4), padded by default. -/
def encode (data : ByteArray) (padding : Bool := true) : String :=
  encodeWith stdAlphabet.toList.toArray data padding

/-- URL-safe base64 (RFC 4648 §5), unpadded by default. -/
def encodeUrl (data : ByteArray) (padding : Bool := false) : String :=
  encodeWith urlAlphabet.toList.toArray data padding

private def value? (c : Char) : Option UInt32 :=
  if 'A' ≤ c ∧ c ≤ 'Z' then some (c.toNat - 'A'.toNat).toUInt32
  else if 'a' ≤ c ∧ c ≤ 'z' then some (c.toNat - 'a'.toNat + 26).toUInt32
  else if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat + 52).toUInt32
  else if c = '+' ∨ c = '-' then some 62
  else if c = '/' ∨ c = '_' then some 63
  else none

/-- Decodes base64 in either alphabet, with or without `=` padding.
    Returns `none` for any other character or an impossible length. -/
def decode? (s : String) : Option ByteArray := Id.run do
  let chars := (s.toList.reverse.dropWhile (· == '=')).reverse.toArray
  if chars.size % 4 == 1 then return none
  let mut out := ByteArray.emptyWithCapacity (chars.size * 3 / 4 + 3)
  let mut acc : UInt32 := 0
  let mut bits : Nat := 0
  for c in chars do
    let some v := value? c | return none
    acc := (acc <<< 6) ||| v
    bits := bits + 6
    if bits ≥ 8 then
      bits := bits - 8
      out := out.push ((acc >>> bits.toUInt32) &&& 0xff).toUInt8
  return some out

end Connect.Base64
