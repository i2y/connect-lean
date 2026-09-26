/-! A minimal test harness: named `IO` checks, run in order, failures counted. -/

namespace Tests

instance : Repr ByteArray where
  reprPrec b _ := s!"bytes{b.data.toList}"

abbrev Test := String × IO Unit

def expect (cond : Bool) (msg : String := "expectation failed") : IO Unit :=
  unless cond do throw (IO.userError msg)

def expectEq [BEq α] [Repr α] (actual expected : α) (what : String := "value") : IO Unit :=
  unless actual == expected do
    throw (IO.userError s!"{what}: expected {repr expected}, got {repr actual}")

def expectOk [ToString ε] (x : Except ε α) (what : String := "result") : IO α :=
  match x with
  | .ok a => pure a
  | .error e => throw (IO.userError s!"{what}: unexpected error {e}")

def expectError (x : Except ε α) (what : String := "result") : IO Unit :=
  match x with
  | .ok _ => throw (IO.userError s!"{what}: expected an error")
  | .error _ => pure ()

/-- How long a test took, when that is long enough to mention. -/
private def took (now start : Nat) : String :=
  if now - start ≥ 500 then s!" ({now - start} ms)" else ""

/-- Runs the tests whose names contain `filter` (all of them by default). -/
def runAll (groups : List (String × List Test)) (filter : String := "") : IO UInt32 := do
  let mut failed := 0
  let mut passed := 0
  for (group, tests) in groups do
    let tests := tests.filter fun (name, _) => filter.isEmpty || (name.splitOn filter).length > 1
    if tests.isEmpty then continue
    IO.println s!"{group}"
    for (name, t) in tests do
      let start ← IO.monoMsNow
      try
        t
        passed := passed + 1
        IO.println s!"  ✓ {name}{took (← IO.monoMsNow) start}"
      catch e =>
        failed := failed + 1
        IO.println s!"  ✗ {name}{took (← IO.monoMsNow) start}: {e}"
      (← IO.getStdout).flush
  IO.println s!"\n{passed} passed, {failed} failed"
  return if failed == 0 then 0 else 1

end Tests
