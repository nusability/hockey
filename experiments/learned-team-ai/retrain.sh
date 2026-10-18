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
# --stamina is NOT optional and is not the tool's default. The policies of 2026-10-17 were
# trained with it, and running one without it changes the game under the policy. Recovered by
# probing rather than from any record: §7's own baseline at seed 777 is 5.9 m spread, 0.73 recv,
# +0.38 terr, 0.249 att with stamina and 5.8 / 0.68 / +0.43 / 0.268 without, and nightB.log's
# header reads the first set. Five metrics to the last digit.
# The goal is an opponent that FEELS real to play against, judged by the owner on replays and on
# his phone - not a better scoreline. What 2026-10-18 established, the hard way:
#
#   * Goal difference alone does not buy realism. It produced a 1.2-1.4 m wide column that wins
#     0.4 balls a match where §7 wins 2.2, on both seeds, and no amount of training moved it.
#   * The shaped reward's six terms all *match §7* - possession, spacing, width, press, attacking
#     third, depth - so on its own it can only ever produce §7 with a learned brain. The README
#     records it winning nothing at the strong setting and selling the shape at the weak one.
#   * Nothing in either reward ever asked a player to TAKE the ball. That is the new term.
#
# So: the shaped reward at the middle weight the README names as the untried experiment, with
# §6.3.1 in force and ball-winning paid for. The three things have never been run together.
COMMON=(--hidden 128 --matches 20 --period 40 --replay-every 25 --stamina
        --shape-weight 0.3 --turnover-weight 0.9 --turnover-target 2.2)

# No --reward victory: the shaped reward is the one that has ever produced a §7-like shape, and
# realism is the goal. Goal difference stays in it at weight 4.0, so winning still matters most.
#
# A: continued from the existing policy - the fast read, since it already plays a match.
# B: from scratch with the ease ladder - the clean one, nothing inherited.
ARM_A=(--no-ladder --init curriculum.txt --iterations 1200 --seed 777)
ARM_B=(--open-nets --ease-collect --iterations 1200 --seed 4242)

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
stamp="$(date +%Y%m%d-%H%M)"

case "${1:-}" in
local)
    out="$repo/.claude/worktrees-out/shaped-$stamp-scratch"
    mkdir -p "$out"
    cd "$repo/ios/SmashCore"
    echo "from scratch + ease ladder, shaped reward (this Mac) -> $out"
    exec swift run -c release TrainTeamAI "${COMMON[@]}" "${ARM_B[@]}" --out "$out" \
        2>&1 | tee "$out/train.log"
    ;;
remote)
    # Ship the sources as they stand, then build and run there. --delete keeps the copy honest;
    # .build is preserved so the rebuild is incremental.
    rsync -az --delete \
        --exclude '.build' --exclude '.swiftpm' \
        "$repo/ios/SmashCore/" "$REMOTE_HOST:smash-trainer/"
    # The checkpoint has to be re-sent AFTER the rsync: --delete prunes anything not in
    # ios/SmashCore, which includes it, so copying it once is not enough.
    scp -q "$here/curriculum.txt" "$REMOTE_HOST:smash-trainer/curriculum.txt"
    ssh "$REMOTE_HOST" "cd smash-trainer && swift build -c release 2>&1 | tail -3"
    out="\$HOME/smash-out/shaped-$stamp-continued"
    ssh "$REMOTE_HOST" "mkdir -p $out && cd smash-trainer && \
        nohup swift run -c release TrainTeamAI ${COMMON[*]} ${ARM_A[*]} --seed 777 --out $out \
        > $out/train.log 2>&1 & echo \"continued from curriculum.txt, shaped reward (second Mac) pid \$!  -> $out\""
    ;;
*)
    echo "usage: $0 {local|remote}" >&2
    exit 2
    ;;
esac
