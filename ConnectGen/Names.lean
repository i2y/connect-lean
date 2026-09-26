module

public section

/-!
# Lean names for protobuf symbols

Generated code must spell proto names as valid Lean identifiers, and the names
it invents must not collide with each other or with what Lean generates for a
structure. These helpers do both.
-/

namespace ConnectGen

/-- Lean keywords and commands that cannot be bare identifiers. -/
def keywords : List String := [
  "abbrev", "at", "attribute", "axiom", "by", "calc", "catch", "class", "def", "deriving", "do",
  "else", "end", "example", "export", "extends", "finally", "for", "from", "fun", "have",
  "if", "import", "in", "inductive", "instance", "let", "local", "macro", "match", "mut",
  "mutual", "namespace", "noncomputable", "notation", "opaque", "open", "partial", "private",
  "protected", "public", "return", "section", "set_option", "show", "structure", "suffices",
  "syntax", "then", "theorem", "try", "unless", "universe", "variable", "where", "with",
  "Type", "Prop", "Sort", "module", "meta", "prelude"]

private def isIdentStart (c : Char) : Bool := c.isAlpha || c == '_'
private def isIdentRest (c : Char) : Bool := c.isAlphanum || c == '_' || c == '\''

/-- Spells one name component, with `«»` when it is not a plain identifier. -/
def escapeComponent (s : String) : String :=
  match s.toList with
  | c :: cs =>
    if isIdentStart c && cs.all isIdentRest && !keywords.contains s then s
    else "«" ++ s ++ "»"
  | [] => "«»"

/-- Spells a dotted name, such as a proto package or full type name. -/
def escapeDotted (s : String) : String :=
  ".".intercalate ((s.splitOn ".").filter (!·.isEmpty) |>.map escapeComponent)

/-- `SayHello` → `sayHello`, `GetHTTPStatus` → `getHTTPStatus`. -/
def lowerFirst (s : String) : String :=
  match s.toList with
  | c :: cs => String.ofList (c.toLower :: cs)
  | [] => s

/-- Names Lean generates for every structure, which fields must avoid. -/
def structureReserved : List String :=
  ["mk", "rec", "recOn", "casesOn", "noConfusion", "noConfusionType", "ctorIdx", "below",
   "brecOn", "binductionOn", "ibelow", "sizeOf", "ext", "ext_iff", "inj", "injEq"]

/-- A field or function name for a method, avoiding `taken` names. -/
def memberName (method : String) (taken : List String) : String := Id.run do
  let mut n := lowerFirst method
  while taken.contains n || structureReserved.contains n do
    n := n ++ "_"
  return n

/-- Makes a string safe inside a `/-- … -/` doc comment. -/
def docSafe (s : String) : String :=
  (s.replace "-/" "- /").replace "/-" "/ -"

/-- A Lean string literal. -/
def stringLit (s : String) : String :=
  s.quote

end ConnectGen
