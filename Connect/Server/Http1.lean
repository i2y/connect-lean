module

public import Std.Http
public import Connect.Server.Core

public section

/-!
# Serving over HTTP/1.1

The bridge between `Server.handle` and Lean's HTTP/1.1 server, `Std.Http`.
`Std.Http` is half-duplex: once a response starts, the unread request body is
discarded, and responses cannot carry trailers. `Server.handle` works around
the first and serves gRPC (which needs the second) only over HTTP/2.
-/

namespace Connect

open Std.Async (Async)

namespace Http1Server

/-- Converts `Std.Http` headers. Their names are already lower case. -/
def headersOfStd (h : Std.Http.Headers) : Headers :=
  { entries := h.toArray.map fun (k, v) => (k.value, v.value) }

/-- Converts to `Std.Http` headers, dropping entries that are not valid HTTP. -/
def headersToStd (h : Headers) : Std.Http.Headers :=
  h.entries.foldl (init := .empty) fun acc (k, v) =>
    match Std.Http.Header.Name.ofString? k, Std.Http.Header.Value.ofString? v with
    | some n, some val => acc.insert n val
    | _, _ => acc

/-- The `Std.Http` status for a code, including nginx's 499. -/
def statusOf (code : Nat) : Std.Http.Status :=
  match Std.Http.Status.ofCode none code.toUInt16 with
  | some s => s
  | none =>
    (Std.Http.Status.ofCode (some ⟨"Client Closed Request", by decide⟩) code.toUInt16).getD
      .internalServerError

/-- Serves one `Std.Http` request. -/
def handle (router : Router) (opts : ServerOptions) (req : Std.Http.Request Std.Http.Body.Stream)
    (cancellation : Std.CancellationContext) : Async (Std.Http.Response Std.Http.Body.Any) := do
  let target := toString req.line.uri
  let (path, query) := match target.splitOn "?" with
    | p :: rest => (p, "?".intercalate rest)
    | [] => ("", "")
  let peer := (req.extensions.get Std.Http.Server.RemoteAddr).map (toString ·.addr)
  let headPromise ← IO.Promise.new (α := Option (Std.Http.Response Std.Http.Body.Any))
  let answered ← IO.mkRef false
  let answer (r : Std.Http.Response Std.Http.Body.Any) : Async Unit := do
    unless ← answered.modifyGet (fun a => (a, true)) do headPromise.resolve (some r)
  let body ← Std.Http.Body.mkStream
  let writer : ResponseWriter := {
    respond := fun status h bytes => do
      let full ← Std.Http.Body.Full.ofByteArray bytes
      answer { line := { status := statusOf status, headers := headersToStd h },
               body := Std.Http.Body.Any.ofBody full }
    start := fun status h =>
      answer { line := { status := statusOf status, headers := headersToStd h },
               body := Std.Http.Body.Any.ofBody body }
    write := fun bytes => body.send (Std.Http.Chunk.ofByteArray bytes)
    finish := fun _ => body.close }
  let sreq : ServerRequest := {
    method := toString req.line.method, path, query, headers := headersOfStd req.line.headers
    peer, cancellation, http2 := false
    body := do return (← req.body.recv).map (·.data) }
  Std.Async.background (t := Std.Async.AsyncTask) do
    try Server.handle router opts sreq writer
    finally
      -- A response must always come, even if the handler machinery failed.
      let empty ← Std.Http.Body.Full.ofByteArray .empty
      answer { line := { status := .internalServerError }, body := Std.Http.Body.Any.ofBody empty }
  match ← Std.Async.await headPromise with
  | some r => return r
  | none =>
    let empty ← Std.Http.Body.Full.ofByteArray .empty
    return { line := { status := .internalServerError }, body := Std.Http.Body.Any.ofBody empty }

end Http1Server

/-- The `Std.Http` handler for a router, to serve it from your own `Std.Http`
    server. -/
def Router.httpHandler (router : Router) (opts : ServerOptions := {}) :
    Std.Http.Server.StatelessHandler :=
  Std.Http.Server.Handler.ofFn fun req => do
    let cancellation ← Std.Async.ContextAsync.getContext
    Http1Server.handle router opts req cancellation

end Connect
