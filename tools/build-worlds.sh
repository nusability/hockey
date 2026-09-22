#!/bin/sh
# Rebuilds the world assets in shared/assets/worlds/ from their Blender scripts (ADR 0005, 0006),
# then re-imports each GLB and checks the asset contract (tools/worldkit.py: verify).
# Deterministic: a rebuild with no script change writes the same GLB and palette bytes and a USDZ
# with the same content.
#   tools/build-worlds.sh                  all five
#   tools/build-worlds.sh oasis space      just these
#   PREVIEW=1 tools/build-worlds.sh …      also render each preview.png from the play camera
set -eu
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
if [ ! -x "$BLENDER" ]; then
  echo "Blender not found at $BLENDER — install Blender 5 or set BLENDER=/path/to/blender" >&2
  exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORLDS="${*:-magicwood space oasis himalaya ocean}"
FLAG=""
if [ -n "${PREVIEW:-}" ]; then FLAG="--preview"; fi
for id in $WORLDS; do
  if ! out="$("$BLENDER" --background --factory-startup --python-exit-code 1 \
      --python "$ROOT/shared/assets/worlds/$id/build_$id.py" -- $FLAG 2>&1)"; then
    echo "$out" | tail -15 >&2
    echo "build_$id.py failed" >&2
    exit 1
  fi
  echo "$out" | grep -E "triangles in" || true
done
CHECK="import sys
sys.dont_write_bytecode = True
sys.path.insert(0, '$ROOT/tools')
import worldkit
ok = [worldkit.verify('$ROOT/shared/assets/worlds/%s/%s.glb' % (w, w), 'ice' if w == 'himalaya' else 'field') for w in '$WORLDS'.split()]
sys.exit(0 if all(ok) else 1)"
if ! out="$("$BLENDER" --background --factory-startup --python-exit-code 1 --python-expr "$CHECK" 2>&1)"; then
  echo "$out" | grep -E "^verify|Error" >&2
  echo "the asset contract does not hold" >&2
  exit 1
fi
echo "$out" | grep -E "^verify"
