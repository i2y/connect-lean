module

public import Std.Async
public import Std.Sync

public section

/-!
# Racing an action against stop conditions

`Std.Async.EAsync.race` leaves the losing side running: a timer raced against a
call keeps the call's state alive until it fires, and a read raced against a
deadline never stops reading. `runUntil` waits with `Selectable.one` instead,
so whichever stop conditions lose are unregistered (a timer is stopped), and
it hands the result of an action that finishes too late to a clean-up function.
-/

namespace Connect

open Std.Async (Async Selectable)

private inductive RaceState (α : Type) where
  | running
  | finished (result : Except IO.Error α)
  | abandoned

/-- Runs `act`, unless one of `stops` fires first. Returns `.ok` with the
    action's result, or `.error` with the value of the stop that won. After a
    stop wins the action keeps running (Lean cannot interrupt it); if it later
    succeeds, `onLate` receives its result, to release what it acquired. -/
def runUntil (act : Async α) (stops : Array (Selectable β))
    (onLate : α → Async Unit := fun _ => pure ()) : Async (Except β α) := do
  let finished ← Std.CancellationContext.new
  let state ← IO.mkRef (RaceState.running : RaceState α)
  Std.Async.background (t := Std.Async.AsyncTask) do
    let r ← try (Except.ok <$> act) catch e => pure (.error e)
    let late ← state.modifyGet fun
      | .abandoned => (true, .abandoned)
      | _ => (false, .finished r)
    finished.cancel .cancel
    if late then
      if let .ok a := r then try onLate a catch _ => pure ()
  let outcome ← Selectable.one (#[.case finished.doneSelector (fun _ => pure none)] ++
    stops.map fun (s : Selectable β) => .case s.selector fun x => (some <$> s.cont x))
  match outcome with
  | none =>
    match ← state.get with
    | .finished (.ok a) => return .ok a
    | .finished (.error e) => throw e
    | _ => throw (IO.userError "runUntil: the action finished without a result")
  | some stop =>
    -- The action may have finished at the same moment; its result still wins.
    match ← state.modifyGet (fun s => match s with | .finished r => (some r, s) | _ => (none, .abandoned)) with
    | some (.ok a) => return .ok a
    | some (.error e) => throw e
    | none => return .error stop

/-- Runs `act` with a time limit in milliseconds: `none` if it ran out. -/
def runWithin (ms : Nat) (act : Async α) (onLate : α → Async Unit := fun _ => pure ()) :
    Async (Option α) := do
  let timer ← Std.Async.Selector.sleep (Std.Time.Millisecond.Offset.ofNat ms)
  match ← runUntil act #[.case timer pure] onLate with
  | .ok a => return some a
  | .error () => return none

end Connect
