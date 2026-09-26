module

public import Std.Async
public import Std.Net
public import Connect.Client.Transport

public section

/-!
# An HTTP/1.1 client transport

Just enough HTTP/1.1 for RPC, over `Std.Async.TCP`:

* request bodies with a `Content-Length` or chunked, written while the
  response is read, so a server can answer before the request ends;
* response bodies with a `Content-Length`, chunked (with trailers), or ending
  when the connection closes.

Each exchange uses its own connection and asks the server to close it after
the response (`Connection: close`). Plain `http://` only.
-/

namespace Connect.Http1

open Std.Async (Async)
open Std.Async.TCP
open Connect.Transport

/-- Parses hexadecimal digits, as in a chunk size. -/
def parseHex? (s : String) : Option Nat :=
  if s.isEmpty then none
  else s.foldl (init := some 0) fun acc c => acc.bind fun n =>
    if '0' ≤ c ∧ c ≤ '9' then some (n * 16 + (c.toNat - '0'.toNat))
    else if 'a' ≤ c ∧ c ≤ 'f' then some (n * 16 + (c.toNat - 'a'.toNat + 10))
    else if 'A' ≤ c ∧ c ≤ 'F' then some (n * 16 + (c.toNat - 'A'.toNat + 10))
    else none

/-- Buffered reads from a socket. -/
structure Reader where
  socket : Socket.Client
  buffer : IO.Ref ByteArray
  offset : IO.Ref Nat
  eof : IO.Ref Bool
  /-- Cancelled when the exchange is abandoned, which also stops a pending read. -/
  aborted : Std.CancellationContext

namespace Reader

def new (socket : Socket.Client) (aborted : Std.CancellationContext) : BaseIO Reader := do
  return { socket, aborted, buffer := ← IO.mkRef .empty, offset := ← IO.mkRef 0,
           eof := ← IO.mkRef false }

/-- Reads more bytes from the socket; `false` at end of stream. Fails once the
    exchange is aborted. -/
def fill (r : Reader) : Async Bool := do
  if ← r.eof.get then return false
  let aborted := do
    if ← r.aborted.isCancelled then throw (IO.userError "the exchange was aborted")
  aborted
  let received ← r.socket.recv? 65536
  -- Aborting cancels a pending read, which then looks like the end of the stream.
  aborted
  match received with
  | none => r.eof.set true; return false
  | some bytes =>
    if bytes.isEmpty then r.eof.set true; return false
    let off ← r.offset.get
    let buf ← r.buffer.get
    -- Drop what was consumed before appending.
    r.buffer.set (buf.extract off buf.size ++ bytes)
    r.offset.set 0
    return true

/-- Bytes available without reading from the socket. -/
def available (r : Reader) : BaseIO Nat := do
  return (← r.buffer.get).size - (← r.offset.get)

/-- Takes up to `n` buffered bytes. -/
def take (r : Reader) (n : Nat) : BaseIO ByteArray := do
  let off ← r.offset.get
  let buf ← r.buffer.get
  let k := min n (buf.size - off)
  r.offset.set (off + k)
  return buf.extract off (off + k)

/-- Reads one CRLF-terminated line, without the terminator. -/
partial def readLine (r : Reader) (limit : Nat := 65536) : Async String := do
  let buf ← r.buffer.get
  let off ← r.offset.get
  let mut i := off
  let mut found : Option Nat := none
  while i + 1 < buf.size do
    if buf[i]! == 13 && buf[i + 1]! == 10 then
      found := some i
      break
    i := i + 1
  match found with
  | some j =>
    r.offset.set (j + 2)
    -- Header bytes are not always UTF-8: fall back to Latin-1, which accepts
    -- any byte. (An undecodable line must not read as the blank line that
    -- ends the head.)
    let bytes := buf.extract off j
    return (String.fromUTF8? bytes).getD (String.ofList (bytes.toList.map fun b => Char.ofNat b.toNat))
  | none =>
    if buf.size - off > limit then throw (IO.userError "HTTP line too long")
    unless ← r.fill do throw (IO.userError "connection closed in the middle of an HTTP message")
    readLine r limit

/-- Reads exactly `n` bytes. -/
partial def readExact (r : Reader) (n : Nat) (acc : ByteArray := .empty) : Async ByteArray := do
  if acc.size ≥ n then return acc
  if (← r.available) == 0 then
    unless ← r.fill do throw (IO.userError "connection closed in the middle of an HTTP message")
  let more ← r.take (n - acc.size)
  readExact r n (acc ++ more)

end Reader

/-- How the response body is delimited. -/
inductive BodyFraming where
  | length (remaining : Nat)
  | chunked (remainingInChunk : Nat)
  | untilClose
  | finished

private def renderHead (method path host : String) (headers : Headers) (framing : String) :
    ByteArray := Id.run do
  let mut s := s!"{method} {path} HTTP/1.1\r\nhost: {host}\r\n"
  for (k, v) in headers do
    -- Never let a value break the message framing.
    let v := v.replace "\r" "" |>.replace "\n" ""
    s := s ++ s!"{k}: {v}\r\n"
  s := s ++ framing ++ "connection: close\r\n\r\n"
  return s.toUTF8

private def hexString (n : Nat) : String :=
  String.ofList (Nat.toDigits 16 n)

/-- Parses a status line such as `HTTP/1.1 200 OK`. -/
private def parseStatus (line : String) : Except String Nat :=
  match line.splitOn " " with
  | v :: code :: _ =>
    if !v.startsWith "HTTP/1." then .error s!"not an HTTP/1 response: {line.quote}"
    else match code.toNat? with
      | some n => .ok n
      | none => .error s!"invalid status line {line.quote}"
  | _ => .error s!"invalid status line {line.quote}"

/-- Reads header lines up to the blank line. -/
private partial def readHeaderLines (r : Reader) (acc : Headers := {}) (count : Nat := 0) :
    Async Headers := do
  let line ← r.readLine
  if line.isEmpty then return acc
  if count > 256 then throw (IO.userError "too many HTTP headers")
  match line.splitOn ":" with
  | k :: rest =>
    readHeaderLines r (acc.add k.trimAscii.toString (":".intercalate rest).trimAscii.toString) (count + 1)
  | [] => readHeaderLines r acc (count + 1)

/-- Starts an exchange: connects and sends the request head (and a fixed body). -/
def start (ep : Endpoint) (method path : String) (headers : Headers) (body : RequestBody) :
    Async Exchange := do
  let socket ← connectTcp ep.host ep.port
  let host := if ep.host.contains ':' then s!"[{ep.host}]" else ep.host
  let hostHeader := if ep.port == 80 then host else s!"{host}:{ep.port}"
  let framing := match body with
    | .empty => if method == "GET" then "" else "content-length: 0\r\n"
    | .fixed b => s!"content-length: {b.size}\r\n"
    | .chunked => "transfer-encoding: chunked\r\n"
  let head := renderHead method (ep.pathPrefix ++ path) hostHeader headers framing
  match body with
  | .fixed b => socket.sendAll #[head, b]
  | _ => socket.send head
  let aborted ← Std.CancellationContext.new
  let reader ← Reader.new socket aborted
  let headRef ← IO.mkRef (none : Option (Nat × Headers))
  let framingRef ← IO.mkRef BodyFraming.finished
  let trailersRef ← IO.mkRef Headers.empty
  let readHead : Async (Nat × Headers) := do
    if let some h := ← headRef.get then return h
    -- Skip interim (1xx) responses.
    let mut result := (0, Headers.empty)
    repeat
      let status ← match parseStatus (← reader.readLine) with
        | .ok s => pure s
        | .error e => throw (IO.userError e)
      let hs ← readHeaderLines reader
      if status ≥ 200 then
        result := (status, hs)
        break
    let (status, hs) := result
    let framing :=
      if method == "HEAD" || status == 204 || status == 304 then BodyFraming.finished
      else if ((hs.get? "transfer-encoding").getD "").toLower.endsWith "chunked" then .chunked 0
      else match (hs.get? "content-length").bind (·.trimAscii.toString.toNat?) with
        | some n => .length n
        | none => .untilClose
    framingRef.set framing
    headRef.set (some (status, hs))
    return (status, hs)
  let rec readBody (fuel : Nat) : Async (Option ByteArray) := do
    let _ ← readHead
    match ← framingRef.get with
    | .finished => return none
    | .length 0 => framingRef.set .finished; return none
    | .length n =>
      if (← reader.available) == 0 then
        unless ← reader.fill do
          throw (IO.userError "connection closed before the response body ended")
      let bytes ← reader.take n
      framingRef.set (.length (n - bytes.size))
      return some bytes
    | .untilClose =>
      if (← reader.available) == 0 then
        unless ← reader.fill do
          framingRef.set .finished
          return none
      return some (← reader.take (← reader.available))
    | .chunked 0 =>
      let line ← reader.readLine
      let sizeText := ((line.splitOn ";").head!.trimAscii.toString)
      let some size := parseHex? sizeText
        | throw (IO.userError s!"invalid chunk size {sizeText.quote}")
      if size == 0 then
        trailersRef.set (← readHeaderLines reader)
        framingRef.set .finished
        return none
      framingRef.set (.chunked size)
      match fuel with
      | 0 => throw (IO.userError "chunked body made no progress")
      | fuel + 1 => readBody fuel
    | .chunked n =>
      if (← reader.available) == 0 then
        unless ← reader.fill do
          throw (IO.userError "connection closed before the response body ended")
      let bytes ← reader.take n
      let left := n - bytes.size
      if left == 0 then
        let _ ← reader.readExact 2 -- CRLF after the chunk data
      framingRef.set (.chunked left)
      return some bytes
  return {
    write := fun data => do
      if data.isEmpty then return
      socket.sendAll #[s!"{hexString data.size}\r\n".toUTF8, data, "\r\n".toUTF8]
    finish := do
      if let .chunked := body then socket.send "0\r\n\r\n".toUTF8
    head := readHead
    read := readBody 1024
    trailers := trailersRef.get
    close := do
      aborted.cancel .cancel
      try socket.native.cancelRecv catch _ => pure ()
      try socket.shutdown catch _ => pure () }

end Connect.Http1
