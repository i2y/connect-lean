module

public import Std.Async
public import Std.Sync
public import Std.Data.HashMap
public import Connect.Http2.Frame
public import Connect.Http2.Hpack

public section

/-!
# HTTP/2 connections

The part of HTTP/2 (RFC 9113) that clients and servers share: a reader task that
takes frames off the transport and routes them to streams, flow control in both
directions, settings, pings, resets and goaways.

A `Stream` is what an application sees: its headers, its body as a sequence of
chunks, its trailers, and functions to send headers and data. Reading a chunk
returns its bytes to the peer's flow-control window; sending waits for window.

Every frame goes out through one queue and one writer task, so the reader never
waits on the socket. Otherwise two peers that both answer frames from their
reading side (as Go's HTTP/2 does) can deadlock once both socket buffers fill.

Deliberately left out: server push (disabled), priorities (ignored), and the
dynamic table on the sending side (see `Hpack.encode`).
-/

namespace Connect.Http2

open Std.Async (Async)

/-- The byte stream a connection runs over. -/
structure Transport where
  send : Array ByteArray → Async Unit
  /-- The next bytes, `none` at end of stream. -/
  recv : Async (Option ByteArray)
  close : Async Unit

/-- What we advertise. -/
structure Settings where
  maxConcurrentStreams : Nat := 256
  /-- Receive window of each stream. -/
  initialWindowSize : Nat := 1024 * 1024
  /-- Receive window of the connection as a whole (at least 65535, the
      protocol's starting window). -/
  connectionWindowSize : Nat := 4 * 1024 * 1024
  /-- Frames that may wait for the writer before a peer that sends but does not
      read is cut off (the PING and SETTINGS flood attacks). -/
  maxQueuedFrames : Nat := 10000
  /-- Bytes of DATA that may wait for the writer before senders pause. -/
  maxQueuedBytes : Nat := 1024 * 1024
  maxFrameSize : Nat := 16384
  headerTableSize : Nat := 4096
  maxHeaderListSize : Nat := 65536

/-- A header list, pseudo-headers first. -/
abbrev HeaderList := Array (String × String)

/-- An HTTP/2 connection or stream failure. -/
structure Http2Error where
  code : UInt32
  message : String
  deriving Inhabited

instance : ToString Http2Error := ⟨fun e => s!"HTTP/2 error {e.code}: {e.message}"⟩

private def toIOError (e : Http2Error) : IO.Error := IO.userError (toString e)

/-- The connection's view of one stream. -/
private structure StreamRec where
  inbound : Std.CloseableChannel ByteArray
  headers : IO.Promise (Except String HeaderList)
  headersReceived : Bool := false
  trailers : IO.Ref HeaderList
  resetCode : IO.Ref (Option UInt32)
  /-- The code of the peer's RST_STREAM, or REFUSED_STREAM for a stream its
      GOAWAY left out. -/
  peerResetCode : IO.Ref (Option UInt32)
  cancellation : Std.CancellationContext
  sendWindow : Int
  /-- Received DATA bytes the application has not read yet. They are returned
      to the connection window when read, or when the stream goes away. -/
  buffered : Nat := 0
  remoteEnded : Bool := false
  localEnded : Bool := false
  /-- We are resetting the stream: its RST_STREAM is being queued. -/
  resetting : Bool := false

/-- A header block being assembled from HEADERS and CONTINUATION frames. -/
private structure PendingBlock where
  streamId : Nat
  block : ByteArray
  endStream : Bool

private structure State where
  streams : Std.HashMap Nat StreamRec := {}
  connSendWindow : Int := 65535
  peerInitialWindow : Nat := 65535
  peerMaxFrameSize : Nat := 16384
  nextStreamId : Nat
  lastPeerStreamId : Nat := 0
  goingAway : Bool := false
  /-- We sent a GOAWAY (`Connection.goaway`). -/
  sentGoaway : Bool := false
  closed : Bool := false
  decoder : Hpack.Decoder
  pending : Option PendingBlock := none
  /-- Bytes returned to the connection window but not yet announced; they go
      out in batches. -/
  connUnacked : Nat := 0
  /-- DATA bytes received and not yet returned with a WINDOW_UPDATE: the peer
      may never have more than our connection window outstanding. -/
  connOutstanding : Nat := 0
  /-- Server: handlers still running. The concurrency limit counts these, not
      open streams, so a client cannot evade it by resetting streams whose
      handlers are still at work ("rapid reset"). -/
  activeHandlers : Nat := 0
  /-- The peer's SETTINGS_MAX_CONCURRENT_STREAMS, which a client obeys. -/
  peerMaxConcurrent : Nat := 2 ^ 31
  /-- Batches queued for the writer and not yet written, and their bytes. -/
  queuedFrames : Nat := 0
  queuedBytes : Nat := 0

/-- A stream, as the application sees it. -/
structure Stream where
  id : Nat
  /-- The headers that opened the stream (server) or answered it (client). -/
  headers : Async HeaderList
  /-- The next piece of the body; `none` once the peer ended the stream.
      Throws if the stream was reset. -/
  read : Async (Option ByteArray)
  /-- The trailers, once `read` returned `none`. -/
  trailers : BaseIO HeaderList
  /-- Sends a header block: the response headers, or trailers. -/
  sendHeaders : HeaderList → (endStream : Bool) → Async Unit
  /-- Sends data, waiting for flow-control window as needed. Does nothing once
      the peer reset the stream with NO_ERROR after a complete response. -/
  sendData : ByteArray → (endStream : Bool) → Async Unit
  /-- Sends headers, a whole body and trailers (if any), ending the stream. A
      body that fits in one frame and the current windows goes out in the same
      write as the headers and trailers, so the peer never sees one without
      the others. -/
  respond : HeaderList → ByteArray → (trailers : HeaderList) → Async Unit
  /-- Abandons the stream. -/
  reset : UInt32 → Async Unit
  /-- The error code the peer reset the stream with, if it did. -/
  peerResetCode : BaseIO (Option UInt32)
  /-- After a complete response: if the peer is still sending, tells it to
      stop (RST_STREAM with NO_ERROR, RFC 9113 §8.1). -/
  endResponse : Async Unit
  /-- Cancelled when the peer resets the stream or the connection ends. -/
  cancellation : Std.CancellationContext

/-- One HTTP/2 connection. -/
structure Connection where
  transport : Transport
  isServer : Bool
  settings : Settings
  private state : Std.Mutex State
  private windowChanged : Std.Notify
  /-- Streams must open in the order of their identifiers, so choosing an
      identifier and sending the stream's HEADERS happen one caller at a time. -/
  private openLock : Std.Semaphore
  /-- Encoded frames waiting for the writer task, in order. -/
  private outbound : Std.CloseableChannel (Array ByteArray)
  /-- A file to log frames to, from `CONNECT_HTTP2_TRACE`; for debugging. -/
  private traceTo : Option String
  /-- Signalled by the writer each time it has written a batch. -/
  private drained : Std.Notify
  /-- Cancelled when the connection has ended. -/
  closed : Std.CancellationContext
  /-- Servers: cancelled once `goaway` was called and no handler is running
      any more, so the connection can close without cutting a call short. -/
  quiesced : Std.CancellationContext
  /-- For servers: called with each stream the client opens. -/
  onStream : Stream → Async Unit

namespace Connection

private def trace (c : Connection) (dir : String) (f : Frame) : IO Unit := do
  let some path := c.traceTo | return
  let st ← c.state.atomically get
  let line := s!"{← IO.monoMsNow} {if c.isServer then "S" else "C"} {dir} type={f.type} " ++
    s!"flags={f.flags} stream={f.streamId} len={f.payload.size} streams={st.streams.size} " ++
    s!"connSend={st.connSendWindow} unacked={st.connUnacked}\n"
  let h ← IO.FS.Handle.mk path .append
  h.putStr line

/-- Queues frames for the writer; they go out in the order they are queued, a
    batch never split. Fails once the connection is closed. -/
private def sendFrames (c : Connection) (frames : Array Frame) : Async Unit := do
  for f in frames do c.trace "out" f
  let bufs := frames.map (·.encode)
  let bytes := bufs.foldl (· + ·.size) 0
  c.state.atomically (modify fun st =>
    { st with queuedFrames := st.queuedFrames + 1, queuedBytes := st.queuedBytes + bytes })
  match ← Std.Async.await (← c.outbound.send bufs) with
  | .ok () => pure ()
  | .error _ => throw (IO.userError "the connection is closed")

/-- `sendFrames`, ignoring a closed connection. (Defined in `Async` so that the
    `try` catches `IO.Error`s; inside `ExceptT` it would not.) -/
private def sendQuietly (c : Connection) (frames : Array Frame) : Async Unit :=
  try c.sendFrames frames catch _ => pure ()

/-- Ends a stream's incoming data; closing twice is harmless. -/
private def closeInbound (ch : Std.CloseableChannel ByteArray) : BaseIO Unit := do
  let _ ← ch.close.toBaseIO

/-- Stops accepting frames; the writer sends what is queued, then closes the
    transport. -/
private def closeOutbound (c : Connection) : BaseIO Unit := do
  let _ ← c.outbound.close.toBaseIO

/-- Writes queued frames until the queue is closed or the transport fails. -/
private partial def writeLoop (c : Connection) (onFailure : Async Unit) : Async Unit := do
  match ← Std.Async.await (← c.outbound.recv) with
  | none =>
    try c.transport.close catch _ => pure ()
  | some first =>
    -- Send whatever else is already queued in the same write.
    let mut bufs := first
    let mut batches := 1
    repeat
      match ← c.outbound.tryRecv with
      | some more => bufs := bufs ++ more; batches := batches + 1
      | none => break
    let ok ← try c.transport.send bufs; pure true catch _ => pure false
    let bytes := bufs.foldl (· + ·.size) 0
    c.state.atomically (modify fun st =>
      { st with queuedFrames := st.queuedFrames - batches, queuedBytes := st.queuedBytes - bytes })
    c.drained.notify
    if ok then writeLoop c onFailure
    else
      onFailure
      closeOutbound c
      try c.transport.close catch _ => pure ()

private def settingsFrameFor (s : Settings) (isServer : Bool) : Frame :=
  settingsFrame (#[(SettingId.maxConcurrentStreams, s.maxConcurrentStreams),
    (SettingId.initialWindowSize, s.initialWindowSize),
    (SettingId.maxFrameSize, s.maxFrameSize),
    (SettingId.headerTableSize, s.headerTableSize),
    (SettingId.maxHeaderListSize, s.maxHeaderListSize)] ++
    (if isServer then #[] else #[(SettingId.enablePush, 0)]))

/-- Ends every stream with an error, and marks the connection closed. -/
private def failAll (c : Connection) (reason : String) : Async Unit := do
  let streams ← c.state.atomically do
    let st ← get
    set { st with closed := true, streams := {} }
    return st.streams
  for (_, entry) in streams.toList do
    entry.headers.resolve (.error reason)
    if (← entry.resetCode.get).isNone then entry.resetCode.set (some ErrorCode.cancel)
    closeInbound entry.inbound
    entry.cancellation.cancel .cancel
  c.windowChanged.notify
  c.drained.notify
  c.closed.cancel .cancel

/-- Sends a GOAWAY and closes the connection. -/
private def connectionError (c : Connection) (code : UInt32) (msg : String) : Async Unit := do
  let last ← c.state.atomically (return (← get).lastPeerStreamId)
  c.sendQuietly #[goawayFrame last code msg]
  failAll c msg
  closeOutbound c

/-- Counts `n` bytes as returned to the connection window; the update itself
    goes out in batches of a quarter of the window. Call with the lock held. -/
private def connectionWindow (s : Settings) : Nat := max 65535 s.connectionWindowSize

private def creditLocked (c : Connection) (st : State) (n : Nat) : State × Nat :=
  let unacked := st.connUnacked + n
  if unacked ≥ connectionWindow c.settings / 4 then
    ({ st with connUnacked := 0, connOutstanding := st.connOutstanding - unacked }, unacked)
  else ({ st with connUnacked := unacked }, 0)

private def sendConnectionUpdate (c : Connection) (n : Nat) : Async Unit := do
  if n > 0 then
    c.sendQuietly #[windowUpdateFrame 0 n]

/-- Credits bytes that arrived for a stream that is gone. -/
private def creditConnection (c : Connection) (n : Nat) : Async Unit := do
  if n == 0 then return
  let update ← c.state.atomically do
    let (st, update) := c.creditLocked (← get) n
    set st
    return update
  c.sendConnectionUpdate update

/-- Forgets a stream, returning its unread bytes to the connection window.
    Whoever still waits for its headers or data is released. -/
private def removeStream (c : Connection) (id : Nat) : Async (Option StreamRec) := do
  let (entry?, update) ← c.state.atomically do
    let st ← get
    match st.streams[id]? with
    | none => return (none, 0)
    | some entry =>
      let (st, update) := c.creditLocked { st with streams := st.streams.erase id } entry.buffered
      set st
      return (some entry, update)
  c.sendConnectionUpdate update
  if let some entry := entry? then
    entry.headers.resolve (.error "the stream closed before its headers arrived")
    closeInbound entry.inbound
    -- A place for another stream under the peer's concurrency limit.
    c.windowChanged.notify
  return entry?

/-- Forgets a stream once both sides have ended it. -/
private def maybeRemove (c : Connection) (id : Nat) : Async Unit := do
  let done ← c.state.atomically do
    match (← get).streams[id]? with
    | some entry => return entry.remoteEnded && entry.localEnded
    | none => return false
  if done then discard (c.removeStream id)

/-- The application read `n` bytes of stream `id`: returns them to the peer's
    windows. Bytes of a stream already removed were credited then. -/
private def acknowledge (c : Connection) (id : Nat) (n : Nat) : Async Unit := do
  if n == 0 then return
  let (update, stream) ← c.state.atomically do
    let st ← get
    match st.streams[id]? with
    | none => return (0, false)
    | some entry =>
      let st := { st with streams := st.streams.insert id { entry with buffered := entry.buffered - n } }
      let (st, update) := c.creditLocked st n
      set st
      return (update, !entry.remoteEnded)
  let mut frames := #[]
  if update > 0 then frames := frames.push (windowUpdateFrame 0 update)
  if stream then frames := frames.push (windowUpdateFrame id n)
  unless frames.isEmpty do
    c.sendQuietly frames

/-- Waits until `id` may send up to `want` bytes, and takes that window. -/
private partial def reserve (c : Connection) (id : Nat) (want : Nat) : Async Nat := do
  let wakeUp ← c.windowChanged.wait
  let got ← c.state.atomically do
    let st ← get
    if st.closed then return Except.error "the connection is closed"
    match st.streams[id]? with
    | none => return .error "the stream is closed"
    | some entry =>
      if (← entry.resetCode.get).isSome then return .error "the stream was reset"
      let avail := min (min entry.sendWindow st.connSendWindow) (Int.ofNat st.peerMaxFrameSize)
      if avail ≤ 0 then return .ok 0
      let k := min want avail.toNat
      set { st with
        connSendWindow := st.connSendWindow - k
        streams := st.streams.insert id { entry with sendWindow := entry.sendWindow - k } }
      return .ok k
  match got with
  | .error e => throw (IO.userError e)
  | .ok 0 =>
    Std.Async.await wakeUp
    reserve c id want
  | .ok k => return k

/-- Waits while the writer has more DATA queued than the settings allow. -/
private partial def waitForWriter (c : Connection) : Async Unit := do
  let wakeUp ← c.drained.wait
  let (bytes, closed) ← c.state.atomically do
    let st ← get
    return (st.queuedBytes, st.closed)
  if closed then throw (IO.userError "the connection is closed")
  if bytes ≤ c.settings.maxQueuedBytes then return
  Std.Async.await wakeUp
  waitForWriter c

/-- Whether the connection still tracks stream `id`. Once a stream was reset,
    or both sides ended it, it takes no more frames (RFC 9113 §5.1): headers and
    empty DATA for it are dropped, and DATA that needs window fails. -/
private def isOpen (c : Connection) (id : Nat) : Async Bool :=
  c.state.atomically (return (← get).streams.contains id)

private def sendDataOn (c : Connection) (id : Nat) (data : ByteArray) (endStream : Bool) :
    Async Unit := do
  if data.isEmpty then
    if endStream && (← c.isOpen id) then c.sendFrames #[dataFrame id .empty true]
  else
    let mut off := 0
    while off < data.size do
      c.waitForWriter
      let k ← c.reserve id (data.size - off)
      let last := off + k ≥ data.size
      c.sendFrames #[dataFrame id (data.extract off (off + k)) (endStream && last)]
      off := off + k
  if endStream then
    c.state.atomically do
      let st ← get
      if let some entry := st.streams[id]? then
        set { st with streams := st.streams.insert id { entry with localEnded := true } }
    maybeRemove c id

private def sendHeadersOn (c : Connection) (id : Nat) (headers : HeaderList) (endStream : Bool) :
    Async Unit := do
  unless ← c.isOpen id do return
  let maxSize ← c.state.atomically (return (← get).peerMaxFrameSize)
  c.sendFrames (headerFrames id (Hpack.encode headers) endStream maxSize)
  if endStream then
    c.state.atomically do
      let st ← get
      if let some entry := st.streams[id]? then
        set { st with streams := st.streams.insert id { entry with localEnded := true } }
    maybeRemove c id

/-- Takes window for `n` bytes of stream `id` if all of it is available now,
    in a single frame. -/
private def tryReserveAll (c : Connection) (id : Nat) (n : Nat) : Async Bool :=
  c.state.atomically do
    let st ← get
    match st.streams[id]? with
    | none => return false
    | some entry =>
      if n > st.peerMaxFrameSize || Int.ofNat n > min entry.sendWindow st.connSendWindow then
        return false
      set { st with
        connSendWindow := st.connSendWindow - n
        streams := st.streams.insert id { entry with sendWindow := entry.sendWindow - n } }
      return true

private def respondOn (c : Connection) (id : Nat) (headers : HeaderList) (body : ByteArray)
    (trailers : HeaderList) : Async Unit := do
  if body.isEmpty && trailers.isEmpty then return ← sendHeadersOn c id headers true
  unless ← c.isOpen id do return
  if body.isEmpty || (← c.tryReserveAll id body.size) then
    let maxSize ← c.state.atomically (return (← get).peerMaxFrameSize)
    let mut frames := headerFrames id (Hpack.encode headers) false maxSize
    unless body.isEmpty do frames := frames.push (dataFrame id body trailers.isEmpty)
    unless trailers.isEmpty do
      frames := frames ++ headerFrames id (Hpack.encode trailers) true maxSize
    c.sendFrames frames
    c.state.atomically do
      let st ← get
      if let some entry := st.streams[id]? then
        set { st with streams := st.streams.insert id { entry with localEnded := true } }
    maybeRemove c id
  else
    sendHeadersOn c id headers false
    sendDataOn c id body trailers.isEmpty
    unless trailers.isEmpty do sendHeadersOn c id trailers true

/-- Resets a stream the connection still tracks, once. A stream already closed
    on both sides gets no RST_STREAM (RFC 9113 §5.1). -/
private def resetOn (c : Connection) (id : Nat) (code : UInt32) : Async Unit := do
  let claimed ← c.state.atomically do
    let st ← get
    match st.streams[id]? with
    | some entry =>
      if entry.resetting then return none
      set { st with streams := st.streams.insert id { entry with resetting := true } }
      return some entry
    | none => return none
  let some entry := claimed | return
  -- Record the code before the data channel closes, so that a reader woken by
  -- the close sees a reset rather than a clean end.
  if (← entry.resetCode.get).isNone then entry.resetCode.set (some code)
  -- Queue the RST_STREAM before forgetting the stream. DATA arriving meanwhile
  -- is dropped; were the stream already gone, it would be answered with a
  -- RST_STREAM (STREAM_CLOSED) that could reach the peer before this one.
  c.sendQuietly #[rstStreamFrame id code]
  discard (c.removeStream id)
  entry.cancellation.cancel .cancel

/-- The application's handle on a stream the connection tracks. -/
private def mkStream (c : Connection) (id : Nat) (entry : StreamRec) : Stream where
  id
  headers := do
    match ← Std.Async.await entry.headers.result! with
    | .ok h => pure h
    | .error e => throw (IO.userError e)
  read := do
    match ← Std.Async.await (← entry.inbound.recv) with
    | some bytes =>
      c.acknowledge id bytes.size
      return some bytes
    | none =>
      match ← entry.resetCode.get with
      | some code =>
        if code == ErrorCode.noError then return none
        throw (toIOError { code, message := "the stream was reset" })
      | none => return none
  trailers := entry.trailers.get
  sendHeaders := sendHeadersOn c id
  sendData := fun data endStream => do
    -- After a complete response, a server may reset the stream with NO_ERROR:
    -- it needs no more of the request (RFC 9113 §8.1), so the rest is dropped.
    let stopped : BaseIO Bool := return (← entry.resetCode.get) == some ErrorCode.noError
    if ← stopped then return
    try sendDataOn c id data endStream
    catch e => unless ← stopped do throw e
  respond := respondOn c id
  reset := resetOn c id
  peerResetCode := entry.peerResetCode.get
  endResponse := do
    let unfinished ← c.state.atomically do
      let st ← get
      match st.streams[id]? with
      | some r => return r.localEnded && !r.remoteEnded
      | none => return false
    if unfinished then resetOn c id ErrorCode.noError
  cancellation := entry.cancellation

private def newRec (initialWindow : Nat) : BaseIO StreamRec := do
  return {
    inbound := ← Std.CloseableChannel.new
    headers := ← IO.Promise.new
    trailers := ← IO.mkRef #[]
    resetCode := ← IO.mkRef none
    peerResetCode := ← IO.mkRef none
    cancellation := ← Std.CancellationContext.new
    sendWindow := Int.ofNat initialWindow }

/-! ## Receiving -/

private def isPseudo (name : String) : Bool := name.startsWith ":"

/-- Handles a complete header block. -/
private def headerBlock (c : Connection) (id : Nat) (block : ByteArray) (endStream : Bool) :
    ExceptT Http2Error Async Unit := do
  -- Decode first, whatever happens next, to keep the table in step with the peer.
  let decoded ← c.state.atomically do
    let st ← get
    match Hpack.Decoder.decode st.decoder block with
    | .ok (hs, d) => set { st with decoder := d }; return Except.ok hs
    | .error e => return .error e
  let headers ← match decoded with
    | .ok hs => pure hs
    | .error e => throw { code := ErrorCode.compressionError, message := e }
  let existing ← c.state.atomically (return (← get).streams[id]?)
  match existing with
  | some entry =>
    if !entry.headersReceived then
      -- A response's headers (client side); informational ones are skipped.
      let status := (headers.find? (·.1 == ":status")).map (·.2)
      if status.any (·.startsWith "1") && !endStream then return
      -- Update the stream as it is now, not the copy read above: its windows
      -- and flags may have changed in between.
      c.state.atomically do
        let st ← get
        if let some r := st.streams[id]? then
          set { st with streams := st.streams.insert id { r with headersReceived := true } }
      entry.headers.resolve (.ok headers)
    else
      -- Trailers must end the stream.
      unless endStream do
        c.resetOn id ErrorCode.protocolError
        return
      entry.trailers.set headers
    if endStream then
      c.state.atomically do
        let st ← get
        if let some r := st.streams[id]? then
          set { st with streams := st.streams.insert id { r with remoteEnded := true } }
      closeInbound entry.inbound
      c.maybeRemove id
  | none =>
    if !c.isServer then
      -- A response for a stream we already forgot; ignore it.
      return
    let entry ← newRec 0
    let entry := { entry with headersReceived := true, remoteEnded := endStream }
    let admitted ← c.state.atomically do
      let st ← get
      if id % 2 == 0 || id ≤ st.lastPeerStreamId then return none
      let accepted := !st.goingAway && st.activeHandlers < c.settings.maxConcurrentStreams
      let entry := { entry with sendWindow := Int.ofNat st.peerInitialWindow }
      set (if accepted then
          { st with lastPeerStreamId := id, activeHandlers := st.activeHandlers + 1
                    streams := st.streams.insert id entry }
        else { st with lastPeerStreamId := id })
      return some (accepted, entry)
    let some (accepted, entry) := admitted
      | throw { code := ErrorCode.protocolError, message := s!"stream {id} was already used" }
    unless accepted do
      c.sendQuietly #[rstStreamFrame id ErrorCode.refusedStream]
      return
    entry.headers.resolve (.ok headers)
    if endStream then closeInbound entry.inbound
    let stream := c.mkStream id entry
    let run : Async Unit := Std.Async.background (t := Std.Async.AsyncTask) do
      try c.onStream stream
      catch _ => c.resetOn id ErrorCode.internalError
      finally
        let idle ← c.state.atomically do
          let st ← get
          set { st with activeHandlers := st.activeHandlers - 1 }
          return st.sentGoaway && st.activeHandlers == 1
        if idle then c.quiesced.cancel .cancel
    run

private def applySettings (c : Connection) (params : Array (UInt16 × Nat)) :
    ExceptT Http2Error Async Unit := do
  for (id, v) in params do
    if id == SettingId.initialWindowSize then
      if v > maxWindow then throw { code := ErrorCode.flowControlError, message := "window too large" }
      c.state.atomically do
        let st ← get
        let delta := Int.ofNat v - Int.ofNat st.peerInitialWindow
        let streams := st.streams.fold (init := st.streams) fun acc k r =>
          acc.insert k { r with sendWindow := r.sendWindow + delta }
        set { st with peerInitialWindow := v, streams }
    else if id == SettingId.maxFrameSize then
      if v < 16384 || v > 16777215 then
        throw { code := ErrorCode.protocolError, message := "invalid max frame size" }
      c.state.atomically (modify fun st => { st with peerMaxFrameSize := v })
    else if id == SettingId.enablePush then
      if v > 1 then throw { code := ErrorCode.protocolError, message := "invalid enable push" }
    else if id == SettingId.maxConcurrentStreams then
      c.state.atomically (modify fun st => { st with peerMaxConcurrent := v })
  c.windowChanged.notify

/-- What to do with a DATA frame. -/
private inductive DataOutcome where
  | deliver (entry : StreamRec)
  /-- Reset the stream with this code. -/
  | reset (code : UInt32)
  /-- The stream is being reset; the data is not wanted. -/
  | drop
  /-- The stream is gone. -/
  | unknown

/-- Handles one frame. Connection errors are thrown. -/
private def handleFrame (c : Connection) (f : Frame) : ExceptT Http2Error Async Unit := do
  c.trace "in " f
  -- A peer that keeps sending while it does not read our replies (PINGs and
  -- SETTINGS each queue one) would otherwise make the queue grow without bound.
  let queued ← c.state.atomically (return (← get).queuedFrames)
  if queued > c.settings.maxQueuedFrames then
    throw { code := ErrorCode.enhanceYourCalm, message := "the peer does not read its replies" }
  let pending ← c.state.atomically (return (← get).pending)
  if let some p := pending then
    unless f.type == FrameType.continuation && f.streamId == p.streamId do
      throw { code := ErrorCode.protocolError, message := "expected CONTINUATION" }
  let protocolError (msg : String) : ExceptT Http2Error Async Unit :=
    throw { code := ErrorCode.protocolError, message := msg }
  match f.type with
  | 0x0 => -- DATA
    if f.streamId == 0 then protocolError "DATA on stream 0"
    let data ← match framePayload f with
      | .ok d => pure d
      | .error code => throw { code, message := "malformed DATA" }
    let endStream := f.hasFlag Flag.endStream
    -- The peer may not send more than our windows allow; buffering beyond them
    -- would let it use unbounded memory.
    let overrun ← c.state.atomically do
      let st ← get
      let outstanding := st.connOutstanding + f.payload.size
      set { st with connOutstanding := outstanding }
      return decide (outstanding > connectionWindow c.settings)
    if overrun then
      throw { code := ErrorCode.flowControlError, message := "connection window exceeded" }
    -- Look the stream up and count the data in one step: a stream that goes
    -- away in between would otherwise leave these bytes uncounted, and the
    -- connection window would shrink for good.
    let outcome ← c.state.atomically do
      let st ← get
      match st.streams[f.streamId]? with
      | none => return DataOutcome.unknown
      | some entry =>
        if entry.resetting then return .drop
        if entry.remoteEnded then return .reset ErrorCode.streamClosed
        -- A response's DATA cannot come before its headers.
        if !entry.headersReceived then return .reset ErrorCode.protocolError
        if entry.buffered + data.size > c.settings.initialWindowSize then
          return .reset ErrorCode.flowControlError
        let updated := { entry with buffered := entry.buffered + data.size, remoteEnded := endStream }
        set { st with streams := st.streams.insert f.streamId updated }
        return .deliver entry
    match outcome with
    | .deliver entry =>
      -- Padding is never delivered, so return its window now.
      let padding := f.payload.size - data.size
      if padding > 0 then
        c.creditConnection padding
        c.sendQuietly #[windowUpdateFrame f.streamId padding]
      unless data.isEmpty do
        let _ ← entry.inbound.send data
      if endStream then
        closeInbound entry.inbound
        c.maybeRemove f.streamId
    | .reset code =>
      c.creditConnection f.payload.size
      c.resetOn f.streamId code
    | .drop => c.creditConnection f.payload.size
    | .unknown =>
      -- The stream is gone; the data still counts against the connection window.
      c.creditConnection f.payload.size
      let (last, next) ← c.state.atomically do
        let st ← get
        return (st.lastPeerStreamId, st.nextStreamId)
      if c.isServer then
        if f.streamId > last then protocolError "DATA on an idle stream"
        c.sendQuietly #[rstStreamFrame f.streamId ErrorCode.streamClosed]
      else
        -- Frames the server sent before it saw our RST_STREAM are ignored
        -- (RFC 9113 §5.1).
        if f.streamId % 2 == 0 || f.streamId ≥ next then protocolError "DATA on a stream we never opened"
  | 0x1 => -- HEADERS
    if f.streamId == 0 then protocolError "HEADERS on stream 0"
    let fragment ← match framePayload f with
      | .ok d => pure d
      | .error code => throw { code, message := "malformed HEADERS" }
    if f.hasFlag Flag.endHeaders then
      c.headerBlock f.streamId fragment (f.hasFlag Flag.endStream)
    else
      c.state.atomically (modify fun st => { st with pending := some {
        streamId := f.streamId, block := fragment, endStream := f.hasFlag Flag.endStream } })
  | 0x9 => -- CONTINUATION
    let some p := pending | protocolError "unexpected CONTINUATION"
    let block := p.block ++ f.payload
    if block.size > 4 * c.settings.maxHeaderListSize then protocolError "header block too large"
    if f.hasFlag Flag.endHeaders then
      c.state.atomically (modify fun st => { st with pending := none })
      c.headerBlock p.streamId block p.endStream
    else
      c.state.atomically (modify fun st => { st with pending := some { p with block } })
  | 0x2 => -- PRIORITY
    if f.streamId == 0 then protocolError "PRIORITY on stream 0"
  | 0x3 => -- RST_STREAM
    if f.streamId == 0 then protocolError "RST_STREAM on stream 0"
    if f.payload.size != 4 then throw { code := ErrorCode.frameSizeError, message := "bad RST_STREAM" }
    let code := (getBE32 f.payload 0).toUInt32
    if let some entry := ← c.state.atomically (return (← get).streams[f.streamId]?) then
      entry.peerResetCode.set (some code)
      entry.resetCode.set (some code)
    if let some entry := ← c.removeStream f.streamId then
      entry.cancellation.cancel .cancel
  | 0x4 => -- SETTINGS
    if f.streamId != 0 then protocolError "SETTINGS on a stream"
    if f.hasFlag Flag.ack then
      unless f.payload.isEmpty do throw { code := ErrorCode.frameSizeError, message := "bad SETTINGS ack" }
    else
      let params ← match parseSettings f.payload with
        | .ok p => pure p
        | .error code => throw { code, message := "malformed SETTINGS" }
      c.applySettings params
      c.sendFrames #[settingsAck]
  | 0x5 => protocolError "PUSH_PROMISE is not allowed"
  | 0x6 => -- PING
    if f.streamId != 0 then protocolError "PING on a stream"
    if f.payload.size != 8 then throw { code := ErrorCode.frameSizeError, message := "bad PING" }
    unless f.hasFlag Flag.ack do c.sendFrames #[pingFrame f.payload true]
  | 0x7 => -- GOAWAY
    if f.streamId != 0 then protocolError "GOAWAY on a stream"
    if f.payload.size < 8 then throw { code := ErrorCode.frameSizeError, message := "bad GOAWAY" }
    let last := getBE32 f.payload 0 % 2 ^ 31
    let refused ← c.state.atomically do
      let st ← get
      set { st with goingAway := true }
      return st.streams.toList.filter fun (id, _) => !c.isServer && id > last
    for (id, entry) in refused do
      entry.peerResetCode.set (some ErrorCode.refusedStream)
      entry.resetCode.set (some ErrorCode.refusedStream)
      entry.headers.resolve (.error "the server is going away")
      entry.cancellation.cancel .cancel
      discard (c.removeStream id)
  | 0x8 => -- WINDOW_UPDATE
    if f.payload.size != 4 then throw { code := ErrorCode.frameSizeError, message := "bad WINDOW_UPDATE" }
    let inc : Nat := getBE32 f.payload 0 % 2 ^ 31
    if inc == 0 then
      if f.streamId == 0 then protocolError "zero WINDOW_UPDATE"
      else c.resetOn f.streamId ErrorCode.protocolError
    else if f.streamId == 0 then
      let overflow ← c.state.atomically do
        let st ← get
        let w := st.connSendWindow + inc
        set { st with connSendWindow := w }
        return decide (w > Int.ofNat maxWindow)
      if overflow then throw { code := ErrorCode.flowControlError, message := "window overflow" }
    else
      let overflow ← c.state.atomically do
        let st ← get
        match st.streams[f.streamId]? with
        | none => return false
        | some r =>
          let w := r.sendWindow + inc
          set { st with streams := st.streams.insert f.streamId { r with sendWindow := w } }
          return decide (w > Int.ofNat maxWindow)
      if overflow then c.resetOn f.streamId ErrorCode.flowControlError
    c.windowChanged.notify
  | _ => pure () -- unknown frame types are ignored

/-- Reads frames until the transport ends or the peer breaks the protocol. -/
private def traceNote (c : Connection) (note : String) : IO Unit := do
  let some path := c.traceTo | return
  let h ← IO.FS.Handle.mk path .append
  h.putStr s!"{← IO.monoMsNow} {if c.isServer then "S" else "C"} note {note}\n"

private partial def readLoop (c : Connection) (reader : FrameReader) : Async Unit := do
  match reader.next? c.settings.maxFrameSize with
  | .error code => c.connectionError code "frame too large"
  | .ok (some (frame, reader')) =>
    let outcome ← try (c.handleFrame frame).run
      catch e =>
        c.traceNote s!"handleFrame threw {e}"
        pure (.error { code := ErrorCode.internalError, message := toString e })
    match outcome with
    | .ok () => readLoop c reader'
    | .error e => c.connectionError e.code e.message
  | .ok none =>
    c.traceNote "waiting for bytes"
    match ← (try (Except.ok <$> c.transport.recv) catch e => pure (.error e)) with
    | .ok (some bytes) =>
      c.traceNote s!"got {bytes.size} bytes"
      readLoop c (reader.feed bytes)
    | other =>
      c.traceNote s!"transport ended {match other with | .error e => toString e | _ => "eof"}"
      c.failAll "the connection closed"
      closeOutbound c

/-! ## Starting -/

private def create (transport : Transport) (isServer : Bool) (settings : Settings)
    (onStream : Stream → Async Unit) : IO Connection := do
  let state ← Std.Mutex.new ({
    nextStreamId := if isServer then 2 else 1
    decoder := { limit := settings.headerTableSize, maxSize := settings.headerTableSize
                 maxHeaderListSize := settings.maxHeaderListSize } } : State)
  return { transport, isServer, settings, state, windowChanged := ← Std.Notify.new,
           openLock := ← Std.Semaphore.new 1, outbound := ← Std.CloseableChannel.new,
           traceTo := ← IO.getEnv "CONNECT_HTTP2_TRACE", drained := ← Std.Notify.new,
           closed := ← Std.CancellationContext.new, quiesced := ← Std.CancellationContext.new,
           onStream }

/-- The frames that follow the preface: our settings and a larger window. -/
private def openingFrames (settings : Settings) (isServer : Bool) : Array Frame :=
  let extra := connectionWindow settings - 65535
  #[settingsFrameFor settings isServer] ++
    (if extra > 0 then #[windowUpdateFrame 0 extra] else #[])

/-- Serves a connection whose client preface has already been read. -/
def serve (transport : Transport) (onStream : Stream → Async Unit) (settings : Settings := {})
    (initial : ByteArray := .empty) : Async Connection := do
  let c ← create transport true settings onStream
  c.sendFrames (openingFrames settings true)
  Std.Async.background (t := Std.Async.AsyncTask) (c.writeLoop (c.failAll "write failed"))
  Std.Async.background (t := Std.Async.AsyncTask) (c.readLoop (FrameReader.empty.feed initial))
  return c

/-- Starts a client connection: sends the preface and settings. -/
def connect (transport : Transport) (settings : Settings := {}) : Async Connection := do
  let c ← create transport false settings (fun s => s.reset ErrorCode.refusedStream)
  let _ ← c.outbound.send #[preface]
  c.sendFrames (openingFrames settings false)
  Std.Async.background (t := Std.Async.AsyncTask) (c.writeLoop (c.failAll "write failed"))
  Std.Async.background (t := Std.Async.AsyncTask) (c.readLoop .empty)
  return c

/-- Whether new streams can be opened. -/
def isUsable (c : Connection) : BaseIO Bool := do
  let st ← c.state.atomically get
  return !st.closed && !st.goingAway && st.nextStreamId < 2 ^ 31 - 2

/-- Takes the next stream identifier for `entry`, once the peer's concurrency
    limit allows another stream. -/
private partial def allocateStream (c : Connection) (entry : StreamRec) :
    Async (Nat × StreamRec) := do
  let wakeUp ← c.windowChanged.wait
  let got ← c.state.atomically do
    let st ← get
    if st.closed || st.goingAway then return Except.error "the connection is closed"
    if st.streams.size ≥ st.peerMaxConcurrent then return .ok none
    let id := st.nextStreamId
    let entry := { entry with sendWindow := Int.ofNat st.peerInitialWindow }
    set { st with nextStreamId := id + 2, streams := st.streams.insert id entry }
    return .ok (some (id, entry))
  match got with
  | .error e => throw (IO.userError e)
  | .ok (some r) => return r
  | .ok none =>
    Std.Async.await wakeUp
    allocateStream c entry

/-- Opens a stream (clients): sends `headers`, ending the stream if there is no
    body. Waits while the peer's concurrency limit is reached. -/
def openStream (c : Connection) (headers : HeaderList) (endStream : Bool) : Async Stream := do
  let entry ← newRec 0
  Std.Async.await (← c.openLock.acquire)
  try
    let (id, entry) ← c.allocateStream entry
    c.sendHeadersOn id headers endStream
    return c.mkStream id entry
  finally
    c.openLock.release

/-- Stops accepting streams and tells the peer; open streams may finish.
    `quiesced` is cancelled once they have. -/
def goaway (c : Connection) : Async Unit := do
  let (last, idle) ← c.state.atomically do
    let st ← get
    set { st with goingAway := true, sentGoaway := true }
    return (st.lastPeerStreamId, st.activeHandlers == 0)
  c.sendQuietly #[goawayFrame last ErrorCode.noError]
  if idle then c.quiesced.cancel .cancel

/-- Closes the connection now. -/
def close (c : Connection) : Async Unit := do
  c.failAll "the connection was closed"
  closeOutbound c

end Connection

end Connect.Http2
