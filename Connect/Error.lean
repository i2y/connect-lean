module

public import Lean.Data.Json
public import Connect.Code
public import Connect.Headers
public import Connect.Base64

public section

/-!
# Errors

A failed RPC ends with a `ConnectError`: a code, a message for developers, and
optional details. A detail is a protobuf message, such as `google.rpc.RetryInfo`,
carried as its type name and binary encoding, so clients can act on it without
parsing the message text.

Every protocol carries the same error. Connect writes it as JSON, gRPC and
gRPC-Web as trailers, so `toJson`/`ofJson?` live here and the gRPC forms live
with the gRPC protocol.
-/

namespace Connect

/-- A protobuf message attached to an error. -/
structure ErrorDetail where
  /-- Fully-qualified message name, such as `google.rpc.RetryInfo`. -/
  typeName : String
  /-- The message in binary protobuf form. -/
  value : ByteArray
  /-- The JSON form a server may add for humans. Informational only. -/
  debug : Option Lean.Json := none
  deriving Inhabited

namespace ErrorDetail

/-- The `google.protobuf.Any` type URL for this detail. -/
def typeUrl (d : ErrorDetail) : String :=
  "type.googleapis.com/" ++ d.typeName

/-- Builds a detail from a `google.protobuf.Any` type URL and value. -/
def ofTypeUrl (url : String) (value : ByteArray) : ErrorDetail :=
  { typeName := (url.splitOn "/").getLast!, value }

instance : BEq ErrorDetail where
  beq a b := a.typeName == b.typeName && a.value == b.value

instance : Repr ErrorDetail where
  reprPrec d _ := s!"ErrorDetail({d.typeName}, {d.value.size} bytes)"

end ErrorDetail

/-- The error an RPC fails with. -/
structure ConnectError where
  code : Code
  message : String := ""
  details : Array ErrorDetail := #[]
  /-- Response headers. A server sends them with the error when the response
      has not started yet (otherwise they join the trailers); a client finds the
      failed response's headers here. -/
  headers : Headers := {}
  /-- Response trailers, sent after the error or received with it. -/
  trailers : Headers := {}
  deriving Inhabited, BEq, Repr

namespace ConnectError

def new (code : Code) (message : String := "") : ConnectError := { code, message }

def canceled (message : String := "") : ConnectError := new .canceled message
def unknown (message : String := "") : ConnectError := new .unknown message
def invalidArgument (message : String := "") : ConnectError := new .invalidArgument message
def deadlineExceeded (message : String := "") : ConnectError := new .deadlineExceeded message
def notFound (message : String := "") : ConnectError := new .notFound message
def alreadyExists (message : String := "") : ConnectError := new .alreadyExists message
def permissionDenied (message : String := "") : ConnectError := new .permissionDenied message
def resourceExhausted (message : String := "") : ConnectError := new .resourceExhausted message
def failedPrecondition (message : String := "") : ConnectError := new .failedPrecondition message
def aborted (message : String := "") : ConnectError := new .aborted message
def outOfRange (message : String := "") : ConnectError := new .outOfRange message
def unimplemented (message : String := "") : ConnectError := new .unimplemented message
def internal (message : String := "") : ConnectError := new .internal message
def unavailable (message : String := "") : ConnectError := new .unavailable message
def dataLoss (message : String := "") : ConnectError := new .dataLoss message
def unauthenticated (message : String := "") : ConnectError := new .unauthenticated message

def withDetail (e : ConnectError) (d : ErrorDetail) : ConnectError :=
  { e with details := e.details.push d }

/-- Adds a response header to send with the error. -/
def withHeader (e : ConnectError) (name value : String) : ConnectError :=
  { e with headers := e.headers.add name value }

/-- Adds a response trailer to send with the error. -/
def withTrailer (e : ConnectError) (name value : String) : ConnectError :=
  { e with trailers := e.trailers.add name value }

instance : ToString ConnectError where
  toString e := if e.message.isEmpty then e.code.name else s!"{e.code.name}: {e.message}"

/-- The JSON object Connect uses for errors:
    `{"code": "not_found", "message": "...", "details": [{"type": ..., "value": ...}]}`. -/
def toJson (e : ConnectError) : Lean.Json :=
  let fields : List (String × Lean.Json) := [("code", .str e.code.name)]
  let fields := if e.message.isEmpty then fields else fields ++ [("message", .str e.message)]
  let fields :=
    if e.details.isEmpty then fields
    else
      let details := e.details.map fun d =>
        let base : List (String × Lean.Json) :=
          [("type", .str d.typeName), ("value", .str (Base64.encode d.value (padding := false)))]
        Lean.Json.mkObj (match d.debug with
          | some dbg => base ++ [("debug", dbg)]
          | none => base)
      fields ++ [("details", .arr details)]
  Lean.Json.mkObj fields

/-- Reads a JSON error. `fallback` is the code for an error without a
    recognizable one. Malformed details are skipped, as the protocol asks. -/
def ofJson (j : Lean.Json) (fallback : Code) : ConnectError := Id.run do
  let code := match j.getObjValAs? String "code" with
    | .ok name => (Code.ofName? name).getD fallback
    | .error _ => fallback
  let message := (j.getObjValAs? String "message").toOption.getD ""
  let mut details := #[]
  if let .ok (.arr ds) := j.getObjVal? "details" then
    for d in ds do
      let (.ok type, .ok value) := (d.getObjValAs? String "type", d.getObjValAs? String "value")
        | continue
      let some bytes := Base64.decode? value | continue
      let typeName := (type.splitOn "/").getLast!
      details := details.push { typeName, value := bytes, debug := (d.getObjVal? "debug").toOption }
  return { code, message, details }

end ConnectError

end Connect
