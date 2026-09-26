module

public import Std.Async
public import Std.Net
public import Connect.Headers
public import Connect.Error

public section

/-!
# Client transports

What the client needs from an HTTP connection, whatever its version: start a
request, stream its body, read the response's status, headers, body and
trailers. `Http1` and `Http2` provide it.
-/

namespace Connect.Transport

open Std.Async (Async)

/-- Where requests go. -/
structure Endpoint where
  host : String
  port : UInt16
  /-- A path prefix before the procedure, without a trailing slash. -/
  pathPrefix : String := ""
  deriving Repr, Inhabited

/-- Parses an `http://host[:port][/prefix]` URL. -/
def Endpoint.parse (url : String) : Except String Endpoint := do
  let some rest := url.dropPrefix? "http://" |>.map (·.toString)
    | if url.startsWith "https://" then throw "https:// is not supported yet: use http://"
      else throw s!"expected an http:// URL, got {url.quote}"
  let (authority, pathPrefix) := match rest.splitOn "/" with
    | a :: ps => (a, if ps.isEmpty then "" else "/" ++ "/".intercalate ps)
    | [] => (rest, "")
  let pathPrefix := if pathPrefix.endsWith "/" then (pathPrefix.dropEnd 1).toString else pathPrefix
  -- `[::1]:8080` or `host:8080` or `host`
  let (host, portStr) :=
    if authority.startsWith "[" then
      match authority.splitOn "]" with
      | [h, p] => ((h.drop 1).toString, (p.dropPrefix? ":").map (·.toString))
      | _ => (authority, none)
    else match authority.splitOn ":" with
      | [h, p] => (h, some p)
      | _ => (authority, none)
  let port ← match portStr with
    | none => pure 80
    | some p => match p.toNat? with
      | some n => if n < 65536 then pure n.toUInt16 else throw s!"invalid port {p}"
      | none => throw s!"invalid port {p.quote}"
  if host.isEmpty then throw "missing host"
  return { host, port, pathPrefix }

/-- How the request body is sent. -/
inductive RequestBody where
  /-- No body. -/
  | empty
  /-- A body whose length is known up front. -/
  | fixed (bytes : ByteArray)
  /-- A body written piece by piece with `Exchange.write`, then `Exchange.finish`. -/
  | chunked

/-- One request and its response. Writing (`write`, `finish`) and reading
    (`head`, `read`, `trailers`) may happen concurrently, but each side must be
    used from one task at a time. -/
structure Exchange where
  /-- Sends part of a chunked request body. -/
  write : ByteArray → Async Unit
  /-- Ends a chunked request body. -/
  finish : Async Unit
  /-- Waits for the response status and headers. Later calls return the same. -/
  head : Async (Nat × Headers)
  /-- The next piece of the response body, `none` at its end. -/
  read : Async (Option ByteArray)
  /-- The response trailers, once the body has ended. -/
  trailers : BaseIO Headers
  /-- Closes the connection, abandoning the exchange. -/
  close : Async Unit
  /-- Why the exchange failed, when the transport can tell (an HTTP/2 stream
      the server reset). Other failures are reported as `unavailable`. -/
  failure : BaseIO (Option ConnectError) := pure none

/-- The address to connect to: IP literals directly, otherwise DNS. -/
def resolve (host : String) (port : UInt16) : Async (Array Std.Net.SocketAddress) := do
  if let some ip := Std.Net.IPv4Addr.ofString host then return #[.v4 { addr := ip, port }]
  if let some ip := Std.Net.IPv6Addr.ofString host then return #[.v6 { addr := ip, port }]
  let ips ← Std.Async.DNS.getAddrInfo host (toString port)
  -- Prefer IPv4: servers commonly listen on 127.0.0.1 only.
  let v4 := ips.filterMap fun | .v4 a => some (Std.Net.SocketAddress.v4 { addr := a, port }) | _ => none
  let v6 := ips.filterMap fun | .v6 a => some (Std.Net.SocketAddress.v6 { addr := a, port }) | _ => none
  return v4 ++ v6

/-- Opens a TCP connection to the first address that accepts. -/
def connectTcp (host : String) (port : UInt16) : Async Std.Async.TCP.Socket.Client := do
  let addrs ← resolve host port
  let mut lastError : Option IO.Error := none
  for addr in addrs do
    try
      let s ← Std.Async.TCP.Socket.Client.mk
      s.connect addr
      s.noDelay
      return s
    catch e => lastError := some e
  throw (lastError.getD (IO.userError s!"cannot resolve {host}"))

/-- The HTTP version a client uses. -/
inductive HttpVersion where
  /-- HTTP/1.1, one connection per call. -/
  | http1
  /-- HTTP/2 without TLS ("h2c", prior knowledge), calls sharing one connection. -/
  | http2
  deriving DecidableEq, Repr, Inhabited

end Connect.Transport
