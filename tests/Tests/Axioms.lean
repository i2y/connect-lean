import Connect

/-! The theorems README.md lists rest on Lean's standard axioms at most: no
`sorry`, no `native_decide`. -/

/--
info: 'Connect.Envelope.parseAt?_encode' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Envelope.parseAt?_encode

/-- info: 'Connect.Envelope.readLength_header' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Connect.Envelope.readLength_header

/--
info: 'Connect.Http2.Frame.parseAt?_encode' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Frame.parseAt?_encode

/-- info: 'Connect.Code.ofName?_name' does not depend on any axioms -/
#guard_msgs in
#print axioms Connect.Code.ofName?_name

/-- info: 'Connect.Code.ofGrpc?_toGrpc' does not depend on any axioms -/
#guard_msgs in
#print axioms Connect.Code.ofGrpc?_toGrpc

/-- info: 'Connect.Code.toGrpc_ofGrpc?' does not depend on any axioms -/
#guard_msgs in
#print axioms Connect.Code.toGrpc_ofGrpc?

/-- info: 'Connect.Code.httpStatus_is_error' does not depend on any axioms -/
#guard_msgs in
#print axioms Connect.Code.httpStatus_is_error

/-- info: 'Connect.Codec.ofName?_name' does not depend on any axioms -/
#guard_msgs in
#print axioms Connect.Codec.ofName?_name
