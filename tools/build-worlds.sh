#!/bin/sh
# Rebuilds every world asset in shared/assets/worlds/ from its Blender script (ADR 0005).
# Deterministic: a rebuild with no script change produces the same geometry.
set -eu
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
if [ ! -x "$BLENDER" ]; then
  echo "Blender not found at $BLENDER — install Blender 5 or set BLENDER=/path/to/blender" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for script in "$ROOT"/shared/assets/worlds/*/build_*.py; do
  "$BLENDER" --background --factory-startup --python "$script" 2>&1 | grep -E "triangles|Error|error" || true
done
