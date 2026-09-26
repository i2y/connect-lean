module

public import Connect.Compression.Gzip
public import Connect.Error

public section

/-!
# Compression

Message payloads may be compressed. The client names the compression it used
and the ones it accepts; the server answers with one it supports. `identity`
(no compression) is always available. `gzip` is built in, written in Lean;
others, such as zstd through a C library, can be added as `Compression` values.
-/

namespace Connect

/-- A payload compression algorithm. -/
structure Compression where
  /-- The name used on the wire, such as `gzip`. -/
  name : String
  compress : ByteArray → ByteArray
  /-- Decompresses. Fails with `.limitExceeded` once the output would pass the
      limit, so a small payload cannot expand without bound. -/
  decompress : ByteArray → (limit : Nat) → Except Gzip.Error ByteArray

namespace Compression

/-- No compression. -/
def identity : Compression where
  name := "identity"
  compress := id
  decompress b limit := if b.size > limit then .error .limitExceeded else .ok b

/-- gzip (RFC 1952). -/
def gzip : Compression where
  name := "gzip"
  compress := Gzip.compress
  decompress b limit := Gzip.decompress b limit

/-- The compressions supported unless configured otherwise. -/
def defaults : Array Compression := #[gzip]

/-- Finds a compression by name. `identity` and the empty name always resolve. -/
def find? (available : Array Compression) (name : String) : Option Compression :=
  let name := name.trimAscii.toString.toLower
  if name.isEmpty || name == "identity" then some identity
  else available.find? (·.name == name)

/-- The first compression in a comma-separated accept list, such as
    `gzip, br`, that is available. `none` means send uncompressed. -/
def negotiate (available : Array Compression) (accept : String) : Option Compression :=
  (accept.splitOn ",").findSome? fun n =>
    let n := n.trimAscii.toString.toLower
    if n.isEmpty || n == "identity" then none
    else available.find? (·.name == n)

/-- The accept list to advertise: the available compressions' names. -/
def acceptList (available : Array Compression) : String :=
  ", ".intercalate (available.map (·.name)).toList

/-- Decompresses a payload the peer sent, mapping failures to Connect errors:
    an oversized result is `resource_exhausted`, a corrupt one `invalid_argument`. -/
def decompressPayload (c : Compression) (payload : ByteArray) (limit : Nat) :
    Except ConnectError ByteArray :=
  (c.decompress payload limit).mapError fun
    | .limitExceeded =>
      .resourceExhausted s!"message is larger than configured max {limit} after decompression"
    | .invalid reason => .invalidArgument s!"failed to decompress {c.name}: {reason}"

end Compression

end Connect
