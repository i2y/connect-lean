module

public import Std.Async
public import Connect.Error

public section

/-!
# The RPC monad

Handlers and client calls run in `RpcM`: asynchronous IO (`Std.Async`) that can
fail with a `ConnectError`. `throw (.notFound "no such user")` ends an RPC with
that error; `IO` actions lift into `RpcM` directly, and an `IO.Error` that
escapes a handler reaches the client as `unknown`.
-/

namespace Connect

/-- Asynchronous IO that can fail with a `ConnectError`. -/
abbrev RpcM := ExceptT ConnectError Std.Async.Async

namespace RpcM

/-- Runs an RPC computation, turning an `IO.Error` into an `unknown` error. -/
def run (x : RpcM α) : Std.Async.Async (Except ConnectError α) := do
  try ExceptT.run x
  catch e => return .error (.unknown (toString e))

/-- Runs `x`, returning its outcome rather than failing; an `IO.Error` becomes
    `unknown`. (`try … catch` inside `RpcM` would not see an `IO.Error`.) -/
def attempt (x : RpcM α) : RpcM (Except ConnectError α) :=
  ExceptT.mk (Except.ok <$> run x)

/-- Lifts an `Except` into `RpcM`. -/
def ofExcept (x : Except ConnectError α) : RpcM α :=
  match x with
  | .ok a => pure a
  | .error e => throw e

/-- Runs an `IO` computation that reports failure as `Except ConnectError`. -/
def ofIOExcept (x : IO (Except ConnectError α)) : RpcM α := do
  ofExcept (← x)

/-- Runs an `Async` action for its effect, ignoring any `IO.Error` it throws.
    (Inside `RpcM`, `try … catch` only sees `ConnectError`s.) -/
def ignoreErrors (x : Std.Async.Async Unit) : RpcM Unit :=
  (show Std.Async.Async Unit from try x catch _ => pure ())

/-- Blocks the current thread until the computation finishes. For `main`
    functions and tests. -/
def block (x : RpcM α) : IO (Except ConnectError α) :=
  Std.Async.Async.block (run x)

/-- Blocks until the computation finishes, raising a failure as an `IO.Error`. -/
def toIO (x : RpcM α) : IO α := do
  match ← block x with
  | .ok a => pure a
  | .error e => throw (IO.userError (toString e))

end RpcM

end Connect
