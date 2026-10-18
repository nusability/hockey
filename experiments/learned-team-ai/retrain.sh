#!/usr/bin/env bash
# Retrain the team policy from scratch under §6.3.1 (a ball from behind is not reliably
# collected). Two arms, one per Mac, differing only in the seed — the same pair as the night of
# 2026-10-17, so the two runs are comparable with each other and with curriculum.txt.
#
#   ./retrain.sh local          # this Mac, seed 0xA11CE (the default arm)
#   ./retrain.sh remote         # the second Mac, seed 777, over ssh
#
# Checkpoints land in <out>/iter-NNNN.txt every iteration and an HTML replay every 25, so a run
# can be stopped at any time and whatever it reached is on disk. The replay now carries three
# pitches — learned v §7, **learned v itself**, §7 v §7 — and the middle one is the one to watch
# for shape.
#
# Nothing here is a gate and nothing here ships: ADR 0010 and shared/data/policy.toml own the
# shipped path for weights.
set -euo pipefail

REMOTE_HOST=hannes@192.168.178.62        # Hanness-MacBook-Pro.local, NOT .fritz.box
REMOTE_DIR=\$HOME/smash-trainer          # a plain rsync of ios/SmashCore, not a git checkout

# --open-nets starts the backwards-chaining curriculum: our ball at 6, 14, 24 m, a loose ball at
# 18 and 30, their ball 24 m from our own goal, then the real game. --hidden 128 is the capacity
# ADR 0010 measured as affordable (3.73 us a pass on an M1, ~2 % of a frame on the OnePlus) and
# the only width that ever reached §7's 6.5 m.
COMMON=(--open-nets --hidden 128 --iterations 4000 --period 40 --replay-every 25)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
stamp="$(date +%Y%m%d-%H%M)"

case "${1:-}" in
local)
    out="$repo/.claude/worktrees-out/behind-$stamp-seedA11CE"
    mkdir -p "$out"
    cd "$repo/ios/SmashCore"
    echo "arm A (this Mac, seed 0xA11CE) -> $out"
    exec swift run -c release TrainTeamAI "${COMMON[@]}" --out "$out" \
        2>&1 | tee "$out/train.log"
    ;;
remote)
    # Ship the sources as they stand, then build and run there. --delete keeps the copy honest;
    # .build is preserved so the rebuild is incremental.
    rsync -az --delete \
        --exclude '.build' --exclude '.swiftpm' \
        "$repo/ios/SmashCore/" "$REMOTE_HOST:smash-trainer/"
    ssh "$REMOTE_HOST" "cd smash-trainer && swift build -c release 2>&1 | tail -3"
    out="\$HOME/smash-out/behind-$stamp-seed777"
    ssh "$REMOTE_HOST" "mkdir -p $out && cd smash-trainer && \
        nohup swift run -c release TrainTeamAI ${COMMON[*]} --seed 777 --out $out \
        > $out/train.log 2>&1 & echo \"arm B (second Mac, seed 777) pid \$!  -> $out\""
    ;;
*)
    echo "usage: $0 {local|remote}" >&2
    exit 2
    ;;
esac
