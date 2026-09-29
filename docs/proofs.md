# Proofs

The protocol's pure pieces are proved correct in Lean, using only Lean's
standard axioms (no `sorry`, no `native_decide`). The proofs are checked when
the library is built and cost nothing at run time;
[`tests/Tests/Axioms.lean`](../tests/Tests/Axioms.lean) checks the axioms of
each theorem listed here.

**Decoding gives back what was encoded:**

- `Connect.Envelope.parseAt?_encode`: parsing the bytes of an encoded message
  frame, with anything before and after it, gives back the same frame and the
  offset just past it.
- `Connect.Envelope.readLength_header`: the four length bytes decode to the
  length, for every length a frame can carry.
- `Connect.Http2.Frame.parseAt?_encode`: the same for HTTP/2 frames: an encoded
  frame parses back to itself, for every length and stream identifier its
  fields can hold.
- `Connect.Http2.Hpack.decodeInt_encodeInt`: HPACK integers, for prefixes of
  one to eight bits and values up to 2^32.
- `Connect.Http2.Hpack.huffmanDecode_huffmanEncode`: Huffman coding, for every
  byte string, and `size_huffmanEncode`: `huffmanLength` is the length of the
  encoding. The kernel checks the decoding tables against the code, symbol by
  symbol.
- `Connect.Http2.Hpack.decodeString_encodeString`: HPACK string literals,
  Huffman-coded or not, followed by anything, for strings up to 2^32 bytes.
- `Connect.Base64.decode?_encode`, `decode?_encodeUrl`: base64 in either
  alphabet, padded or not.
- `Connect.Percent.decode_encodeGrpcMessage`, `decode_encodeQuery`:
  percent-encoded `grpc-message` values and query parameters.
- `Connect.Code.ofName?_name`, `ofGrpc?_toGrpc`, `toGrpc_ofGrpc?`: error codes
  survive the Connect and gRPC spellings, and `httpStatus_is_error`: no error
  is reported with a success status.
- `Connect.Codec.ofName?_name`: codec names round-trip.

**Untrusted input cannot make the parsers use more than configured:**

- `Connect.Http2.Hpack.decodeInt_spec`: a decoded HPACK integer is at most
  2^32 and takes at most six bytes; `decodeString_spec`: a string ends within
  the block.
- `Connect.Http2.Hpack.Decoder.decode_valid`: decoding a header block keeps the
  dynamic table within the size we advertised, and `decode_listSize`: the
  decoded headers fit in the header list size we accept.
- `Connect.Http2.Frame.parseAt?_size_le`, `FrameReader.next?_size_le`: no frame
  longer than the maximum frame size is returned; a longer one is refused
  before its payload is buffered.
- `Connect.EnvelopeReader.nextLength?_of_next?`: the length a server checks
  against its limit is the size of the message it then reads.
- `Connect.Gzip.inflate_size_le`, `decompress_size_le`: decompression never
  produces more than the limit, however the input was made.

**How the network splits the bytes does not matter:**

- `Connect.EnvelopeReader.unread_feed`, `next?_eq`, `next?_feed`: feeding
  appends to the bytes the reader holds, `next?` parses those bytes and nothing
  else, and a message that has arrived is not changed by the bytes after it.
- `Connect.EnvelopeReader.drain_feed`: so draining after each chunk returns the
  same messages, and leaves the same bytes, as draining after all of them.
- `Connect.Http2.FrameReader.drain_feed`, `drain_feed_error`: the same for
  HTTP/2 frames, including the refusal of an oversized frame.

**Not covered:** the HTTP/2 connection's state machine and flow control, the
asynchronous servers and clients, ProtoJSON and Connect's JSON errors (Lean's
JSON parser is `partial`), `grpc-status-details-bin`, and `grpc-timeout`,
whose rendering rounds to coarser units. The tests and the conformance suite
cover those.
