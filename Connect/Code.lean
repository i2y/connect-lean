module

public section

/-!
# Error codes

The sixteen Connect error codes. They are the gRPC status codes without `OK`:
a successful RPC has no code at all. Each code has three spellings on the wire,
and this module keeps all of them in one place:

- the Connect name (`"invalid_argument"`), used in JSON error bodies;
- the gRPC number (`3`), used in the `grpc-status` trailer;
- an HTTP status (`400`), used for Connect unary error responses.

The theorems at the end show that the name and number spellings round-trip,
so a code survives every protocol unchanged.
-/

namespace Connect

/-- A Connect (and gRPC) error code. -/
inductive Code where
  /-- The RPC was canceled, usually by the caller. -/
  | canceled
  /-- An error of unclear origin, or one without a more appropriate code. -/
  | unknown
  /-- The request is invalid, regardless of system state. -/
  | invalidArgument
  /-- The deadline expired before the RPC could complete. -/
  | deadlineExceeded
  /-- A requested resource could not be found. -/
  | notFound
  /-- The caller tried to create a resource that already exists. -/
  | alreadyExists
  /-- The caller is not authorized to perform the operation. -/
  | permissionDenied
  /-- A resource, such as a quota or the message size limit, is exhausted. -/
  | resourceExhausted
  /-- The system is not in the state the operation requires. -/
  | failedPrecondition
  /-- The operation was aborted, often by a concurrency conflict. -/
  | aborted
  /-- The operation was attempted past the valid range. -/
  | outOfRange
  /-- The operation is not implemented, supported, or enabled. -/
  | unimplemented
  /-- An invariant of the underlying system is broken. -/
  | internal
  /-- The service is temporarily unavailable; callers may retry. -/
  | unavailable
  /-- Unrecoverable data loss or corruption. -/
  | dataLoss
  /-- The caller does not have valid credentials. -/
  | unauthenticated
  deriving Repr, DecidableEq, Hashable, Inhabited

namespace Code

/-- Every code, in gRPC numeric order. -/
@[expose] def all : List Code :=
  [canceled, unknown, invalidArgument, deadlineExceeded, notFound, alreadyExists,
   permissionDenied, resourceExhausted, failedPrecondition, aborted, outOfRange,
   unimplemented, internal, unavailable, dataLoss, unauthenticated]

/-- The Connect name of a code, as it appears in JSON error bodies. -/
@[expose] def name : Code → String
  | canceled => "canceled"
  | unknown => "unknown"
  | invalidArgument => "invalid_argument"
  | deadlineExceeded => "deadline_exceeded"
  | notFound => "not_found"
  | alreadyExists => "already_exists"
  | permissionDenied => "permission_denied"
  | resourceExhausted => "resource_exhausted"
  | failedPrecondition => "failed_precondition"
  | aborted => "aborted"
  | outOfRange => "out_of_range"
  | unimplemented => "unimplemented"
  | internal => "internal"
  | unavailable => "unavailable"
  | dataLoss => "data_loss"
  | unauthenticated => "unauthenticated"

/-- Parses a Connect code name. -/
@[expose] def ofName? : String → Option Code
  | "canceled" => some canceled
  | "unknown" => some unknown
  | "invalid_argument" => some invalidArgument
  | "deadline_exceeded" => some deadlineExceeded
  | "not_found" => some notFound
  | "already_exists" => some alreadyExists
  | "permission_denied" => some permissionDenied
  | "resource_exhausted" => some resourceExhausted
  | "failed_precondition" => some failedPrecondition
  | "aborted" => some aborted
  | "out_of_range" => some outOfRange
  | "unimplemented" => some unimplemented
  | "internal" => some internal
  | "unavailable" => some unavailable
  | "data_loss" => some dataLoss
  | "unauthenticated" => some unauthenticated
  | _ => none

/-- The gRPC status number of a code, between 1 and 16. -/
@[expose] def toGrpc : Code → Nat
  | canceled => 1
  | unknown => 2
  | invalidArgument => 3
  | deadlineExceeded => 4
  | notFound => 5
  | alreadyExists => 6
  | permissionDenied => 7
  | resourceExhausted => 8
  | failedPrecondition => 9
  | aborted => 10
  | outOfRange => 11
  | unimplemented => 12
  | internal => 13
  | unavailable => 14
  | dataLoss => 15
  | unauthenticated => 16

/-- The code for a gRPC status number. `0` (OK) and numbers above 16 have none. -/
@[expose] def ofGrpc? : Nat → Option Code
  | 1 => some canceled
  | 2 => some unknown
  | 3 => some invalidArgument
  | 4 => some deadlineExceeded
  | 5 => some notFound
  | 6 => some alreadyExists
  | 7 => some permissionDenied
  | 8 => some resourceExhausted
  | 9 => some failedPrecondition
  | 10 => some aborted
  | 11 => some outOfRange
  | 12 => some unimplemented
  | 13 => some internal
  | 14 => some unavailable
  | 15 => some dataLoss
  | 16 => some unauthenticated
  | _ => none

/-- The HTTP status of a Connect unary error response with this code. -/
@[expose] def httpStatus : Code → Nat
  | canceled => 499
  | unknown => 500
  | invalidArgument => 400
  | deadlineExceeded => 504
  | notFound => 404
  | alreadyExists => 409
  | permissionDenied => 403
  | resourceExhausted => 429
  | failedPrecondition => 400
  | aborted => 409
  | outOfRange => 400
  | unimplemented => 501
  | internal => 500
  | unavailable => 503
  | dataLoss => 500
  | unauthenticated => 401

/-- The code a client infers from an HTTP status when the response carries no
    Connect error of its own (for example, a proxy's error page). -/
@[expose] def ofHttpStatus : Nat → Code
  | 400 => internal
  | 401 => unauthenticated
  | 403 => permissionDenied
  | 404 => unimplemented
  | 429 => unavailable
  | 502 => unavailable
  | 503 => unavailable
  | 504 => unavailable
  | _ => unknown

instance : ToString Code := ⟨name⟩

/-! ## The spellings round-trip -/

theorem ofName?_name (c : Code) : ofName? c.name = some c := by
  cases c <;> rfl

theorem ofGrpc?_toGrpc (c : Code) : ofGrpc? c.toGrpc = some c := by
  cases c <;> rfl

theorem toGrpc_ofGrpc? {n : Nat} {c : Code} (h : ofGrpc? n = some c) : c.toGrpc = n := by
  unfold ofGrpc? at h
  split at h <;> first | (cases h; rfl) | cases h

theorem name_injective {a b : Code} (h : a.name = b.name) : a = b := by
  have := congrArg ofName? h
  simpa [ofName?_name] using this

theorem toGrpc_injective {a b : Code} (h : a.toGrpc = b.toGrpc) : a = b := by
  have := congrArg ofGrpc? h
  simpa [ofGrpc?_toGrpc] using this

/-- Every code is a gRPC status other than `OK`. -/
theorem toGrpc_mem_range (c : Code) : 1 ≤ c.toGrpc ∧ c.toGrpc ≤ 16 := by
  cases c <;> decide

theorem mem_all (c : Code) : c ∈ all := by
  cases c <;> decide

/-- Every error maps to an HTTP error status: nothing is reported as a success. -/
theorem httpStatus_is_error (c : Code) : 400 ≤ c.httpStatus ∧ c.httpStatus < 600 := by
  cases c <;> decide

end Code

end Connect
