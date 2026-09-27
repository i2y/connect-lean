import Connect

/-! The theorems README.md lists rest on Lean's standard axioms at most: no
`sorry`, no `native_decide`. -/

/-! Round trips. -/

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

/-- info: 'Connect.Http2.Hpack.decodeInt_encodeInt' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Connect.Http2.Hpack.decodeInt_encodeInt

/--
info: 'Connect.Http2.Hpack.huffmanDecode_huffmanEncode' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.huffmanDecode_huffmanEncode

/--
info: 'Connect.Http2.Hpack.size_huffmanEncode' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.size_huffmanEncode

/--
info: 'Connect.Http2.Hpack.decodeString_encodeString' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.decodeString_encodeString

/--
info: 'Connect.Base64.decode?_encode' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Base64.decode?_encode

/--
info: 'Connect.Base64.decode?_encodeUrl' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Base64.decode?_encodeUrl

/--
info: 'Connect.Percent.decode_encodeGrpcMessage' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Percent.decode_encodeGrpcMessage

/--
info: 'Connect.Percent.decode_encodeQuery' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Percent.decode_encodeQuery

/-! Bounds on what untrusted input can make the parsers do. -/

/--
info: 'Connect.Http2.Hpack.decodeInt_spec' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.decodeInt_spec

/--
info: 'Connect.Http2.Hpack.decodeString_spec' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.decodeString_spec

/--
info: 'Connect.Http2.Hpack.Decoder.decode_valid' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.Decoder.decode_valid

/--
info: 'Connect.Http2.Hpack.Decoder.decode_listSize' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Http2.Hpack.Decoder.decode_listSize

/-- info: 'Connect.Http2.Hpack.Decoder.valid_mk' does not depend on any axioms -/
#guard_msgs in
#print axioms Connect.Http2.Hpack.Decoder.valid_mk

/-- info: 'Connect.Http2.Frame.parseAt?_size_le' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Connect.Http2.Frame.parseAt?_size_le

/-- info: 'Connect.Http2.FrameReader.next?_size_le' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Connect.Http2.FrameReader.next?_size_le

/-- info: 'Connect.EnvelopeReader.nextLength?_of_next?' depends on axioms: [propext, Quot.sound] -/
#guard_msgs in
#print axioms Connect.EnvelopeReader.nextLength?_of_next?

/--
info: 'Connect.Gzip.inflate_size_le' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Gzip.inflate_size_le

/--
info: 'Connect.Gzip.decompress_size_le' depends on axioms: [propext, Classical.choice, Quot.sound]
-/
#guard_msgs in
#print axioms Connect.Gzip.decompress_size_le
