module

public section

/-!
# HPACK tables

The static table (RFC 7541 Appendix A) and the Huffman code (Appendix B).
Generated from golang.org/x/net/http2/hpack; do not edit by hand. The
decoding tables at the end are derived from the Huffman code.
-/

namespace Connect.Http2.Hpack

/-- The static table, indexed from 1. -/
def staticTable : Array (String × String) := #[
  (":authority", ""),
  (":method", "GET"),
  (":method", "POST"),
  (":path", "/"),
  (":path", "/index.html"),
  (":scheme", "http"),
  (":scheme", "https"),
  (":status", "200"),
  (":status", "204"),
  (":status", "206"),
  (":status", "304"),
  (":status", "400"),
  (":status", "404"),
  (":status", "500"),
  ("accept-charset", ""),
  ("accept-encoding", "gzip, deflate"),
  ("accept-language", ""),
  ("accept-ranges", ""),
  ("accept", ""),
  ("access-control-allow-origin", ""),
  ("age", ""),
  ("allow", ""),
  ("authorization", ""),
  ("cache-control", ""),
  ("content-disposition", ""),
  ("content-encoding", ""),
  ("content-language", ""),
  ("content-length", ""),
  ("content-location", ""),
  ("content-range", ""),
  ("content-type", ""),
  ("cookie", ""),
  ("date", ""),
  ("etag", ""),
  ("expect", ""),
  ("expires", ""),
  ("from", ""),
  ("host", ""),
  ("if-match", ""),
  ("if-modified-since", ""),
  ("if-none-match", ""),
  ("if-range", ""),
  ("if-unmodified-since", ""),
  ("last-modified", ""),
  ("link", ""),
  ("location", ""),
  ("max-forwards", ""),
  ("proxy-authenticate", ""),
  ("proxy-authorization", ""),
  ("range", ""),
  ("referer", ""),
  ("refresh", ""),
  ("retry-after", ""),
  ("server", ""),
  ("set-cookie", ""),
  ("strict-transport-security", ""),
  ("transfer-encoding", ""),
  ("user-agent", ""),
  ("vary", ""),
  ("via", ""),
  ("www-authenticate", "")]

/-- The Huffman code of each byte, right-aligned, and its length in bits. -/
@[expose] def huffmanCodes : Array (UInt32 × UInt8) := #[
  (0x1ff8, 13), (0x7fffd8, 23), (0xfffffe2, 28), (0xfffffe3, 28), (0xfffffe4, 28), (0xfffffe5, 28),
  (0xfffffe6, 28), (0xfffffe7, 28), (0xfffffe8, 28), (0xffffea, 24), (0x3ffffffc, 30), (0xfffffe9, 28),
  (0xfffffea, 28), (0x3ffffffd, 30), (0xfffffeb, 28), (0xfffffec, 28), (0xfffffed, 28), (0xfffffee, 28),
  (0xfffffef, 28), (0xffffff0, 28), (0xffffff1, 28), (0xffffff2, 28), (0x3ffffffe, 30), (0xffffff3, 28),
  (0xffffff4, 28), (0xffffff5, 28), (0xffffff6, 28), (0xffffff7, 28), (0xffffff8, 28), (0xffffff9, 28),
  (0xffffffa, 28), (0xffffffb, 28), (0x14, 6), (0x3f8, 10), (0x3f9, 10), (0xffa, 12),
  (0x1ff9, 13), (0x15, 6), (0xf8, 8), (0x7fa, 11), (0x3fa, 10), (0x3fb, 10),
  (0xf9, 8), (0x7fb, 11), (0xfa, 8), (0x16, 6), (0x17, 6), (0x18, 6),
  (0x0, 5), (0x1, 5), (0x2, 5), (0x19, 6), (0x1a, 6), (0x1b, 6),
  (0x1c, 6), (0x1d, 6), (0x1e, 6), (0x1f, 6), (0x5c, 7), (0xfb, 8),
  (0x7ffc, 15), (0x20, 6), (0xffb, 12), (0x3fc, 10), (0x1ffa, 13), (0x21, 6),
  (0x5d, 7), (0x5e, 7), (0x5f, 7), (0x60, 7), (0x61, 7), (0x62, 7),
  (0x63, 7), (0x64, 7), (0x65, 7), (0x66, 7), (0x67, 7), (0x68, 7),
  (0x69, 7), (0x6a, 7), (0x6b, 7), (0x6c, 7), (0x6d, 7), (0x6e, 7),
  (0x6f, 7), (0x70, 7), (0x71, 7), (0x72, 7), (0xfc, 8), (0x73, 7),
  (0xfd, 8), (0x1ffb, 13), (0x7fff0, 19), (0x1ffc, 13), (0x3ffc, 14), (0x22, 6),
  (0x7ffd, 15), (0x3, 5), (0x23, 6), (0x4, 5), (0x24, 6), (0x5, 5),
  (0x25, 6), (0x26, 6), (0x27, 6), (0x6, 5), (0x74, 7), (0x75, 7),
  (0x28, 6), (0x29, 6), (0x2a, 6), (0x7, 5), (0x2b, 6), (0x76, 7),
  (0x2c, 6), (0x8, 5), (0x9, 5), (0x2d, 6), (0x77, 7), (0x78, 7),
  (0x79, 7), (0x7a, 7), (0x7b, 7), (0x7ffe, 15), (0x7fc, 11), (0x3ffd, 14),
  (0x1ffd, 13), (0xffffffc, 28), (0xfffe6, 20), (0x3fffd2, 22), (0xfffe7, 20), (0xfffe8, 20),
  (0x3fffd3, 22), (0x3fffd4, 22), (0x3fffd5, 22), (0x7fffd9, 23), (0x3fffd6, 22), (0x7fffda, 23),
  (0x7fffdb, 23), (0x7fffdc, 23), (0x7fffdd, 23), (0x7fffde, 23), (0xffffeb, 24), (0x7fffdf, 23),
  (0xffffec, 24), (0xffffed, 24), (0x3fffd7, 22), (0x7fffe0, 23), (0xffffee, 24), (0x7fffe1, 23),
  (0x7fffe2, 23), (0x7fffe3, 23), (0x7fffe4, 23), (0x1fffdc, 21), (0x3fffd8, 22), (0x7fffe5, 23),
  (0x3fffd9, 22), (0x7fffe6, 23), (0x7fffe7, 23), (0xffffef, 24), (0x3fffda, 22), (0x1fffdd, 21),
  (0xfffe9, 20), (0x3fffdb, 22), (0x3fffdc, 22), (0x7fffe8, 23), (0x7fffe9, 23), (0x1fffde, 21),
  (0x7fffea, 23), (0x3fffdd, 22), (0x3fffde, 22), (0xfffff0, 24), (0x1fffdf, 21), (0x3fffdf, 22),
  (0x7fffeb, 23), (0x7fffec, 23), (0x1fffe0, 21), (0x1fffe1, 21), (0x3fffe0, 22), (0x1fffe2, 21),
  (0x7fffed, 23), (0x3fffe1, 22), (0x7fffee, 23), (0x7fffef, 23), (0xfffea, 20), (0x3fffe2, 22),
  (0x3fffe3, 22), (0x3fffe4, 22), (0x7ffff0, 23), (0x3fffe5, 22), (0x3fffe6, 22), (0x7ffff1, 23),
  (0x3ffffe0, 26), (0x3ffffe1, 26), (0xfffeb, 20), (0x7fff1, 19), (0x3fffe7, 22), (0x7ffff2, 23),
  (0x3fffe8, 22), (0x1ffffec, 25), (0x3ffffe2, 26), (0x3ffffe3, 26), (0x3ffffe4, 26), (0x7ffffde, 27),
  (0x7ffffdf, 27), (0x3ffffe5, 26), (0xfffff1, 24), (0x1ffffed, 25), (0x7fff2, 19), (0x1fffe3, 21),
  (0x3ffffe6, 26), (0x7ffffe0, 27), (0x7ffffe1, 27), (0x3ffffe7, 26), (0x7ffffe2, 27), (0xfffff2, 24),
  (0x1fffe4, 21), (0x1fffe5, 21), (0x3ffffe8, 26), (0x3ffffe9, 26), (0xffffffd, 28), (0x7ffffe3, 27),
  (0x7ffffe4, 27), (0x7ffffe5, 27), (0xfffec, 20), (0xfffff3, 24), (0xfffed, 20), (0x1fffe6, 21),
  (0x3fffe9, 22), (0x1fffe7, 21), (0x1fffe8, 21), (0x7ffff3, 23), (0x3fffea, 22), (0x3fffeb, 22),
  (0x1ffffee, 25), (0x1ffffef, 25), (0xfffff4, 24), (0xfffff5, 24), (0x3ffffea, 26), (0x7ffff4, 23),
  (0x3ffffeb, 26), (0x7ffffe6, 27), (0x3ffffec, 26), (0x3ffffed, 26), (0x7ffffe7, 27), (0x7ffffe8, 27),
  (0x7ffffe9, 27), (0x7ffffea, 27), (0x7ffffeb, 27), (0xffffffe, 28), (0x7ffffec, 27), (0x7ffffed, 27),
  (0x7ffffee, 27), (0x7ffffef, 27), (0x7fffff0, 27), (0x3ffffee, 26)]

/-- The end-of-string code, which only ever appears as padding. -/
def huffmanEos : UInt32 × UInt8 := (0x3fffffff, 30)

/-! The code is canonical: the codes of each length are consecutive numbers, in
the order of their symbols. So a decoder needs, for each length, only the first
code and how many codes there are, and the symbols in code order. These tables
are derived from `huffmanCodes`, leaving out EOS; `huffmanSymbol?_code` in
`Hpack` proves they agree with it. The Huffman tables are exposed so that the
kernel can check that. -/

/-- How many symbols have a code of each length. -/
@[expose] def huffmanCount : Array Nat := #[
  0, 0, 0, 0, 0, 10, 26, 32, 6, 0, 5, 3,
  2, 6, 2, 3, 0, 0, 0, 3, 8, 13, 26, 29,
  12, 4, 15, 19, 29, 0, 3]

/-- The first code of each length. -/
@[expose] def huffmanFirst : Array Nat := #[
  0, 0, 0, 0, 0, 0, 20, 92, 248, 508, 1016, 2042,
  4090, 8184, 16380, 32764, 65534, 131068, 262136, 524272, 1048550, 2097116, 4194258, 8388568,
  16777194, 33554412, 67108832, 134217694, 268435426, 536870910, 1073741820]

/-- How many symbols have shorter codes than each length. -/
@[expose] def huffmanOffset : Array Nat := #[
  0, 0, 0, 0, 0, 0, 10, 36, 68, 74, 74, 79,
  82, 84, 90, 92, 95, 95, 95, 95, 98, 106, 119, 145,
  174, 186, 190, 205, 224, 253, 253]

/-- The symbols in the order of their codes. -/
@[expose] def huffmanSymbols : Array UInt8 := #[
  48, 49, 50, 97, 99, 101, 105, 111, 115, 116, 32, 37, 45, 46, 47, 51,
  52, 53, 54, 55, 56, 57, 61, 65, 95, 98, 100, 102, 103, 104, 108, 109,
  110, 112, 114, 117, 58, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76,
  77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 89, 106, 107, 113, 118,
  119, 120, 121, 122, 38, 42, 44, 59, 88, 90, 33, 34, 40, 41, 63, 39,
  43, 124, 35, 62, 0, 36, 64, 91, 93, 126, 94, 125, 60, 96, 123, 92,
  195, 208, 128, 130, 131, 162, 184, 194, 224, 226, 153, 161, 167, 172, 176, 177,
  179, 209, 216, 217, 227, 229, 230, 129, 132, 133, 134, 136, 146, 154, 156, 160,
  163, 164, 169, 170, 173, 178, 181, 185, 186, 187, 189, 190, 196, 198, 228, 232,
  233, 1, 135, 137, 138, 139, 140, 141, 143, 147, 149, 150, 151, 152, 155, 157,
  158, 165, 166, 168, 174, 175, 180, 182, 183, 188, 191, 197, 231, 239, 9, 142,
  144, 145, 148, 159, 171, 206, 215, 225, 236, 237, 199, 207, 234, 235, 192, 193,
  200, 201, 202, 205, 210, 213, 218, 219, 238, 240, 242, 243, 255, 203, 204, 211,
  212, 214, 221, 222, 223, 241, 244, 245, 246, 247, 248, 250, 251, 252, 253, 254,
  2, 3, 4, 5, 6, 7, 8, 11, 12, 14, 15, 16, 17, 18, 19, 20,
  21, 23, 24, 25, 26, 27, 28, 29, 30, 31, 127, 220, 249, 10, 13, 22]

end Connect.Http2.Hpack
