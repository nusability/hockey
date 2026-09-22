#!/bin/sh
# Compiles Android's Filament materials (android/app/src/main/materials/*.mat) into
# android/app/src/main/assets/materials/*.filamat. The material format is versioned with the
# runtime, so matc MUST be the same Filament release as `filament` in gradle/libs.versions.toml.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(grep '^filament *=' "$ROOT/android/gradle/libs.versions.toml" | sed 's/.*"\(.*\)".*/\1/')"
TOOLS="${FILAMENT_TOOLS:-$HOME/.cache/smash/filament-$VERSION}"
if [ ! -x "$TOOLS/bin/matc" ]; then
  echo "Fetching Filament $VERSION tools into $TOOLS"
  mkdir -p "$TOOLS"
  curl -sL "https://github.com/google/filament/releases/download/v$VERSION/filament-v$VERSION-mac.tgz" \
    | tar xz -C "$TOOLS" --strip-components 1
fi
OUT="$ROOT/android/app/src/main/assets/materials"
mkdir -p "$OUT"
for mat in "$ROOT"/android/app/src/main/materials/*.mat; do
  name="$(basename "$mat" .mat)"
  "$TOOLS/bin/matc" -a opengl -a vulkan -p mobile -o "$OUT/$name.filamat" "$mat"
  echo "compiled $name"
done
