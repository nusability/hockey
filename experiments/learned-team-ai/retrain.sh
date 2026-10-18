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
#
# --reward victory is the whole point and is NOT the tool's default. The question this run asks
# is whether width emerges **on its own** now that a trailing pass costs something. Trained on
# the shaped reward, any width that appears is width we asked for (`spread` is one of its terms)
# and the run answers nothing - and the README's own lesson is that an untrained measure is a
# measure the search will spend. Goal difference alone is the only objective that can answer it.
# It is also what the two arms of 2026-10-17 used, so the trajectories are comparable.
#
# --matches 20, likewise theirs: at 4 matches a candidate the fitness is mostly draw noise, and
# victory-only has no dense term to lean on. It costs ~40 s an iteration instead of ~10.
COMMON=(--hidden 128 --reward victory --matches 20 --period 40 --replay-every 25)

# Two arms that ask the same question two ways, because neither is sound alone.
#
# A (from scratch, ease ladder): the strong result if it works - nothing inherited, so width that
#   appears was found rather than kept. It needs --ease-collect because §6.3.1 took away the free
#   possession a random policy bootstrapped on: measured, 91.6 % of a self-play match with the ball
#   loose and a best fitness frozen for 56 iterations. The ladder forgives the rule, then tightens
#   it to 0, so the end state is judged under the real rule.
# B (continue curriculum.txt, full rule): the control, and the cleaner single-variable test - the
#   same policy and the same objective that produced the single file, with only the rule changed.
#   It also guards the risk in A: a policy that learns the file in the eased world first may patch
#   around it rather than discover width.
#
# --no-ladder for B: curriculum.txt already finished the spawn curriculum, so rung 0 is a regression.
ARM_A=(--open-nets --ease-collect --iterations 1000)
ARM_B=(--no-ladder --init curriculum.txt --iterations 1000)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
stamp="$(date +%Y%m%d-%H%M)"

case "${1:-}" in
local)
    out="$repo/.claude/worktrees-out/ease-$stamp-seedA11CE"
    mkdir -p "$out"
    cd "$repo/ios/SmashCore"
    echo "arm A (this Mac, seed 0xA11CE) -> $out"
    exec swift run -c release TrainTeamAI "${COMMON[@]}" "${ARM_A[@]}" --out "$out" \
        2>&1 | tee "$out/train.log"
    ;;
remote)
    # Ship the sources as they stand, then build and run there. --delete keeps the copy honest;
    # .build is preserved so the rebuild is incremental.
    rsync -az --delete \
        --exclude '.build' --exclude '.swiftpm' \
        "$repo/ios/SmashCore/" "$REMOTE_HOST:smash-trainer/"
    ssh "$REMOTE_HOST" "cd smash-trainer && swift build -c release 2>&1 | tail -3"
    out="\$HOME/smash-out/init-$stamp-seed777"
    ssh "$REMOTE_HOST" "mkdir -p $out && cd smash-trainer && \
        nohup swift run -c release TrainTeamAI ${COMMON[*]} ${ARM_B[*]} --seed 777 --out $out \
        > $out/train.log 2>&1 & echo \"arm B (second Mac, seed 777) pid \$!  -> $out\""
    ;;
*)
    echo "usage: $0 {local|remote}" >&2
    exit 2
    ;;
esac
