#!/usr/bin/env bash
# Regenerates conformance/ConformanceGen from the conformance protos.
#
#   PROTOC_GEN_LEAN4=/path/to/protoc-gen-lean4 ./conformance/generate.sh
#
# protoc-gen-lean4 comes from https://github.com/Lean-zh/protobuf
# (`lake build Plugin` there); protoc-gen-connect-lean from this repository.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${PROTOC_GEN_LEAN4:?set PROTOC_GEN_LEAN4 to the protoc-gen-lean4 binary}"
lake build protoc-gen-connect-lean >/dev/null

WKT_INCLUDE="${WKT_INCLUDE:-$(dirname "$(command -v protoc)")/../include}"
OUT=conformance/ConformanceGen
rm -rf "$OUT"
mkdir -p "$OUT"

protoc \
  --plugin=protoc-gen-lean4="$PROTOC_GEN_LEAN4" \
  --lean4_out="$OUT" --lean4_opt=lean4_prefix=ConformanceGen \
  --plugin=protoc-gen-connect-lean=.lake/build/bin/protoc-gen-connect-lean \
  --connect-lean_out="$OUT" --connect-lean_opt=lean4_prefix=ConformanceGen \
  -I conformance/proto -I "$WKT_INCLUDE" \
  google/protobuf/any.proto google/protobuf/empty.proto google/protobuf/struct.proto \
  connectrpc/conformance/v1/config.proto connectrpc/conformance/v1/service.proto \
  connectrpc/conformance/v1/client_compat.proto connectrpc/conformance/v1/server_compat.proto

# protoc-gen-lean4 marks deprecated enum values with an `attribute` command
# naming the value without its enum's namespace, which does not resolve.
# Deprecation is only advisory, so drop those commands.
find "$OUT" -name '*.lean' -exec perl -0pi -e 's/\n *attribute +\[ *deprecated [^\]]*\] +«[^»]*» *\n/\n/g' {} +
