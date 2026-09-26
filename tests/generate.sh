#!/usr/bin/env bash
# Regenerates tests/EdgeGen from tests/proto: awkward names for the generator.
#   PROTOC_GEN_LEAN4=.lake/tools/protoc-gen-lean4 ./tests/generate.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${PROTOC_GEN_LEAN4:=.lake/tools/protoc-gen-lean4}"
lake build protoc-gen-connect-lean >/dev/null
rm -rf tests/EdgeGen
mkdir -p tests/EdgeGen
protoc \
  --plugin=protoc-gen-lean4="$PROTOC_GEN_LEAN4" \
  --lean4_out=tests/EdgeGen --lean4_opt=lean4_prefix=EdgeGen \
  --plugin=protoc-gen-connect-lean=.lake/build/bin/protoc-gen-connect-lean \
  --connect-lean_out=tests/EdgeGen --connect-lean_opt=lean4_prefix=EdgeGen \
  -I tests/proto edge/v1/types.proto edge/v1/edge.proto nopkg.proto
