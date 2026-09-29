#!/usr/bin/env bash
# Vendors SwiftTerm into Vendor/SwiftTerm and patches it so it builds with the Command Line Tools
# (which ship no `metal` compiler). SwiftTerm compiles the shader source at runtime when Metal is enabled.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/SwiftTerm"
TAG="v1.20.0"

if [[ ! -f "$DEST/Package.swift" ]]; then
  rm -rf "$DEST"
  mkdir -p "$ROOT/Vendor"
  echo "Cloning SwiftTerm ${TAG}..."
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" https://github.com/migueldeicaza/SwiftTerm.git "$DEST"
  rm -rf "$DEST/.git"
fi

sed -i '' 's|\.process("Apple/Metal/Shaders.metal")|.copy("Apple/Metal/Shaders.metal")|' "$DEST/Package.swift"
if ! grep -q '\.copy("Apple/Metal/Shaders.metal")' "$DEST/Package.swift"; then
  echo "error: SwiftTerm Metal patch failed" >&2
  exit 1
fi
echo "SwiftTerm $TAG ready at $DEST"
