#!/usr/bin/env bash
# Builds protoc-gen-lean4, the message generator of Lean-zh/protobuf, at the
# revision this package depends on, with this package's Lean toolchain, and
# copies it to .lake/tools/protoc-gen-lean4.
#
# It is built from a separate checkout: the plugin loads plugin.proto with a
# path relative to the workspace root, so it only builds with the protobuf
# package as the root, and building inside .lake/packages would disturb this
# workspace's own build of the library.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
rev="$(python3 -c 'import json;print(next(p["rev"] for p in json.load(open("lake-manifest.json"))["packages"] if p["name"]=="protobuf"))')"
src="$root/.lake/tools/protobuf-src"
if [ ! -d "$src/.git" ]; then
  git clone --quiet https://github.com/Lean-zh/protobuf.git "$src"
fi
git -C "$src" fetch --quiet origin
git -C "$src" checkout --quiet "$rev"
cp "$root/lean-toolchain" "$src/lean-toolchain"
(cd "$src" && lake build Plugin)
cp "$src/.lake/build/bin/protoc-gen-lean4" "$root/.lake/tools/protoc-gen-lean4"
echo "$root/.lake/tools/protoc-gen-lean4"
