module

public import Std.Http
public import Connect.Server.Context
public import Connect.Server.Service
public import Connect.Server.Core
public import Connect.Server.Http1
public import Connect.Server.Http2

public section

/-!
# Running a server

`Connect.serve` binds a router to an address and serves until `SIGINT` or
`SIGTERM`, then stops accepting and lets open calls finish:

```lean
def main : IO Unit :=
  Connect.serve (Connect.Router.empty.register myService) (cfg := { port := 8080 })
```

One port serves HTTP/1.1 (through `Std.Http`) and HTTP/2 without TLS ("h2c",
with prior knowledge, as gRPC clients use it): the first bytes of a connection
tell them apart.

`Connect.Server.start` returns a handle instead, for tests and for programs that
run other work alongside the server. To mount Connect next to other routes in
your own `Std.Http` server, use `Router.httpHandler`.
-/

namespace Connect

open Std.Async (Async)
open Std.Async.TCP

/-- Where and how to listen. -/
structure ServeConfig where
  /-- IPv4 or IPv6 address to bind. -/
  host : String := "127.0.0.1"
  /-- Port to bind; `0` picks a free one. -/
  port : UInt16 := 8080
  /-- Settings for HTTP/1.1 connections. -/
  http : Std.Http.Config := {}
  /-- Settings for HTTP/2 connections. -/
  http2 : Http2.Settings := {}
  /-- Serve HTTP/2 without TLS (h2c, prior knowledge) on the same port. -/
  enableHttp2 : Bool := true
  /-- How long a new connection may take to say which protocol it speaks. -/
  prefaceTimeoutMs : Nat := 10000

/-- A server running in the background. -/
structure RunningServer where
  /-- The bound port; differs from the requested one when that was `0`. -/
  port : UInt16
  shutdownContext : Std.CancellationContext
  finished : IO.Promise Unit

/-- A socket whose first bytes were already read, handed to `Std.Http`. -/
structure PeekedSocket where
  socket : Socket.Client
  pending : IO.Ref ByteArray

instance : Std.Http.Transport PeekedSocket where
  recv p n := do
    let b ← p.pending.get
    if b.isEmpty then p.socket.recv? n
    else
      p.pending.set .empty
      return some b
  sendAll p data := p.socket.sendAll data
  recvSelector p n :=
    let sel := p.socket.recvSelector n
    { tryFn := do
        let b ← p.pending.get
        if b.isEmpty then sel.tryFn
        else
          p.pending.set .empty
          return some (some b)
      registerFn := sel.registerFn
      unregisterFn := sel.unregisterFn }

namespace Server

private def socketAddress (host : String) (port : UInt16) : IO Std.Net.SocketAddress := do
  if let some ip := Std.Net.IPv4Addr.ofString host then
    return .v4 { addr := ip, port }
  if let some ip := Std.Net.IPv6Addr.ofString host then
    return .v6 { addr := ip, port }
  throw (IO.userError s!"invalid IP address {host}")

/-- Reads until the bytes either match the HTTP/2 preface or cannot: whether
    they do, and the bytes read. `none` if the client says nothing by
    `deadline`; the pending read is then cancelled, so the socket can go.
    (A plain read raced against a timer: waiting on `recvSelector` instead
    costs several milliseconds per connection.) -/
private partial def sniff (socket : Socket.Client) (deadline : Nat) (acc : ByteArray) :
    Async (Option (Bool × ByteArray)) := do
  let n := min acc.size Http2.preface.size
  if acc.extract 0 n != Http2.preface.extract 0 n then return some (false, acc)
  if acc.size ≥ Http2.preface.size then return some (true, acc)
  let now ← IO.monoMsNow
  if now ≥ deadline then return none
  match ← runWithin (deadline - now) (socket.recv? 65536) with
  | none =>
    -- A cancelled read returns `none`, ending the task that waits on it.
    try socket.native.cancelRecv catch _ => pure ()
    return none
  | some none => return some (false, acc)
  | some (some bytes) =>
    if bytes.isEmpty then return some (false, acc) else sniff socket deadline (acc ++ bytes)

/-- Serves one connection, HTTP/1.1 or HTTP/2. -/
private def serveClient (router : Router) (opts : ServerOptions) (cfg : ServeConfig)
    (shutdown : Std.CancellationContext) (client : Socket.Client) : Async Unit := do
  let peerAddr ← (client.getPeerName : IO _).toBaseIO
  let peer := peerAddr.toOption.map toString
  let some (isHttp2, initial) ← sniff client ((← IO.monoMsNow) + cfg.prefaceTimeoutMs) .empty
    | try client.shutdown catch _ => pure ()
  if isHttp2 && cfg.enableHttp2 then
    let transport : Http2.Transport := {
      send := client.sendAll, recv := client.recv? 65536
      close := try client.shutdown catch _ => pure () }
    let conn ← Http2.Connection.serve transport (Http2Server.handleStream router opts peer)
      cfg.http2 (initial.extract Http2.preface.size initial.size)
    let stop ← Std.Async.Selectable.one #[
      .case conn.closed.doneSelector (fun _ => pure false),
      .case shutdown.doneSelector (fun _ => pure true)]
    if stop then
      -- Let open streams finish, briefly, then close. Frames still queued go
      -- out first.
      conn.goaway
      let grace ← Std.Async.Selector.sleep 5000
      Std.Async.Selectable.one #[
        .case conn.closed.doneSelector pure,
        .case conn.quiesced.doneSelector pure,
        .case grace pure]
      conn.close
  else
    let pending ← IO.mkRef initial
    let ext := match peerAddr.toOption with
      | some a => Std.Http.Extensions.empty.insert (Std.Http.Server.RemoteAddr.mk a)
      | none => .empty
    let conn : Std.Async.ContextAsync Unit :=
      Std.Http.Server.serveConnection ({ socket := client, pending } : PeekedSocket)
        (router.httpHandler opts) cfg.http ext
    -- A forked context lives in its parent's table until cancelled.
    let connContext ← shutdown.fork
    try Std.Async.ContextAsync.runIn connContext conn
    finally connContext.cancel .cancel

/-- Starts serving `router` in the background. -/
def start (router : Router) (opts : ServerOptions := {}) (cfg : ServeConfig := {}) :
    IO RunningServer := do
  let addr ← socketAddress cfg.host cfg.port
  let listener ← Socket.Server.mk
  listener.bind addr
  listener.listen 1024
  listener.noDelay
  let port := (← listener.getSockName).port
  let shutdown ← Std.CancellationContext.new
  let finished ← IO.Promise.new
  let active ← IO.mkRef (0 : Nat)
  let stopped ← IO.mkRef false
  let settle : BaseIO Unit := do
    if (← stopped.get) && (← active.get) == 0 then finished.resolve ()
  let acceptLoop : Async Unit := do
    repeat
      let next ← Std.Async.Selectable.one #[
        .case listener.acceptSelector (fun c => pure (some c)),
        .case shutdown.doneSelector (fun _ => pure none)]
      let some client := next | break
      active.modify (· + 1)
      Std.Async.background (t := Std.Async.AsyncTask) do
        try
          try client.noDelay catch _ => pure ()
          serveClient router opts cfg shutdown client
        catch _ => pure ()
        finally
          active.modify (· - 1)
          settle
    stopped.set true
    settle
  let _ ← (Std.Async.background (t := Std.Async.AsyncTask) acceptLoop : Async Unit).toIO
  return { port, shutdownContext := shutdown, finished }

end Server

namespace RunningServer

/-- Stops accepting connections and waits for open ones to finish. -/
def shutdown (s : RunningServer) : IO Unit := do
  s.shutdownContext.cancel .shutdown
  let _ ← IO.wait s.finished.result!

/-- Waits until the server shuts down. -/
def wait (s : RunningServer) : IO Unit := do
  let _ ← IO.wait s.finished.result!

end RunningServer

/-- Serves `router` until `SIGINT` or `SIGTERM`, then shuts down gracefully. -/
def serve (router : Router) (opts : ServerOptions := {}) (cfg : ServeConfig := {})
    (onReady : UInt16 → IO Unit := fun p => IO.eprintln s!"listening on http://{cfg.host}:{p}") :
    IO Unit := do
  let running ← Server.start router opts cfg
  onReady running.port
  let term ← Std.Async.Signal.Waiter.mk .sigterm false
  let int ← Std.Async.Signal.Waiter.mk .sigint false
  let _ ← IO.waitAny [(← term.wait).map (fun _ => ()), (← int.wait).map (fun _ => ())]
  running.shutdown

end Connect
