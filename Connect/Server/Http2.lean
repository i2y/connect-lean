module

public import Connect.Http2.Connection
public import Connect.Server.Core

public section

/-!
# Serving over HTTP/2

Each stream the client opens becomes a `ServerRequest`; the response goes back
as a HEADERS frame, DATA frames, and trailers in a final HEADERS frame.
-/

namespace Connect

open Std.Async (Async)

namespace Http2Server

/-- Serves one HTTP/2 stream. -/
def handleStream (router : Router) (opts : ServerOptions) (peer : Option String)
    (stream : Http2.Stream) : Async Unit := do
  let hs ← stream.headers
  let pseudo (name : String) := (hs.find? (·.1 == name)).map (·.2)
  let target := (pseudo ":path").getD ""
  let (path, query) := match target.splitOn "?" with
    | p :: rest => (p, "?".intercalate rest)
    | [] => ("", "")
  let headers : Headers := { entries := hs.filter (!·.1.startsWith ":") }
  let withStatus (status : Nat) (h : Headers) : Http2.HeaderList :=
    #[(":status", toString status)] ++ h.entries
  let writer : ResponseWriter := {
    respond := fun status h body => stream.respond (withStatus status h) body #[]
    respondWithTrailers := fun status h body trailers =>
      stream.respond (withStatus status h) body trailers.entries
    start := fun status h => stream.sendHeaders (withStatus status h) false
    write := fun bytes => stream.sendData bytes false
    finish := fun trailers =>
      if trailers.isEmpty then stream.sendData .empty true
      else stream.sendHeaders trailers.entries true }
  Server.handle router opts {
    method := (pseudo ":method").getD "", path, query, headers, peer
    body := stream.read, cancellation := stream.cancellation, http2 := true } writer
  stream.endResponse

end Http2Server

end Connect
