module

public import Connect.Base64

public section

/-!
# Headers

Request headers, response headers and trailers. Names are case-insensitive, so
they are stored lower-cased; a name may carry several values, kept in order.

Keys ending in `-bin` carry binary values, base64-encoded on the wire.
`addBin` and `getBin?` do the encoding.
-/

namespace Connect

/-- An ordered, case-insensitive multimap of header names to values. -/
structure Headers where
  /-- The entries in insertion order, with lower-cased names. -/
  entries : Array (String × String) := #[]
  deriving Inhabited, Repr, BEq

namespace Headers

/-- Lower-cases ASCII letters: header names are case-insensitive. -/
def normalize (name : String) : String :=
  name.map Char.toLower

def empty : Headers := {}

def size (h : Headers) : Nat := h.entries.size

def isEmpty (h : Headers) : Bool := h.entries.isEmpty

/-- The first value for `name`. -/
def get? (h : Headers) (name : String) : Option String :=
  let name := normalize name
  h.entries.find? (·.1 == name) |>.map (·.2)

/-- Every value for `name`, in order. -/
def getAll (h : Headers) (name : String) : Array String :=
  let name := normalize name
  h.entries.filterMap fun (k, v) => if k == name then some v else none

def contains (h : Headers) (name : String) : Bool :=
  let name := normalize name
  h.entries.any (·.1 == name)

/-- Appends a value, keeping any existing values for the name. -/
def add (h : Headers) (name value : String) : Headers :=
  { entries := h.entries.push (normalize name, value) }

/-- Removes every value for `name`. -/
def erase (h : Headers) (name : String) : Headers :=
  let name := normalize name
  { entries := h.entries.filter (·.1 != name) }

/-- Replaces every value for `name` with `value`. -/
def set (h : Headers) (name value : String) : Headers :=
  (h.erase name).add name value

/-- Appends all entries of `other`. -/
def append (h other : Headers) : Headers :=
  { entries := h.entries ++ other.entries }

instance : Append Headers := ⟨append⟩

def ofList (pairs : List (String × String)) : Headers :=
  pairs.foldl (fun h (k, v) => h.add k v) empty

def toList (h : Headers) : List (String × String) := h.entries.toList

/-- The distinct names, in order of first appearance. -/
def names (h : Headers) : Array String := Id.run do
  let mut out := #[]
  for (k, _) in h.entries do
    unless out.contains k do out := out.push k
  return out

def filter (h : Headers) (p : String → String → Bool) : Headers :=
  { entries := h.entries.filter fun (k, v) => p k v }

instance [Monad m] : ForIn m Headers (String × String) where
  forIn h init f := forIn h.entries init f

/-- Appends a binary value, base64-encoded as gRPC and Connect expect.
    The name should end in `-bin`. -/
def addBin (h : Headers) (name : String) (value : ByteArray) : Headers :=
  h.add name (Base64.encode value (padding := false))

/-- Decodes the first value for a binary (`-bin`) header. -/
def getBin? (h : Headers) (name : String) : Option ByteArray :=
  h.get? name >>= Base64.decode?

/-- Whether `name` is a binary header name. -/
def isBinary (name : String) : Bool :=
  (normalize name).endsWith "-bin"

end Headers

end Connect
