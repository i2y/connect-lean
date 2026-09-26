#!/usr/bin/env bash
# Downloads the Connect conformance runner to .lake/tools/connectconformance.
#
#   ./scripts/download-conformance.sh [version]
#
# The version defaults to the one conformance/config.yaml was written for.
set -euo pipefail
version="${1:-v1.0.5}"
root="$(cd "$(dirname "$0")/.." && pwd)"
bin="$root/.lake/tools/connectconformance"
if [ -x "$bin" ] && [ "$("$bin" --version 2>/dev/null)" = "connectconformance $version" ]; then
  echo "$bin"
  exit 0
fi
case "$(uname -s)" in
  Linux) os=Linux ;;
  Darwin) os=Darwin ;;
  *) echo "no conformance runner for $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "no conformance runner for $(uname -m)" >&2; exit 1 ;;
esac
tarball="connectconformance-$version-$os-$arch.tar.gz"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$tarball" \
  "https://github.com/connectrpc/conformance/releases/download/$version/$tarball"
tar -xzf "$tmp/$tarball" -C "$tmp"
mkdir -p "$(dirname "$bin")"
mv "$tmp/connectconformance" "$bin"
echo "$bin"
