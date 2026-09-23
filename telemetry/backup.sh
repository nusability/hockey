#!/bin/bash
# Smash Hockey telemetry DB — nightly dump → B2, on box #2 (stori-monitoring).
#
# Why back this up at all: the box's D7 rule is that config-as-code IS the backup, and measurement is
# the exception. The schema here is generated from shared/data/telemetry.toml and needs no backup at
# all — but the rows do, because regenerating them means asking players to replay the game.
#
# Deliberately its own timer rather than one more line in `stori-bugsink-backup.sh` or
# `flashybird-backup.sh`: those scripts' sources of truth live in other repos, and adding a Smash
# Hockey concern to them would be the cross-repo coupling the compose file already avoids. Cost of
# separating: a third timer and a third dead-man check. It reuses stori's write-only B2 remote under
# its own prefix — the key can neither list nor delete.
#
# Source of truth is telemetry/backup.sh in the hockey repo. Edit there, then scp to
# /usr/local/bin/smashhockey-backup.sh. Runs as root via systemd at 04:07 UTC — after bugsink (03:17)
# and flashybird (03:42), so three pg_dumps never contend on a 8 GB box.

set -uo pipefail # NOT -e: we want to ping on failure, not die on the first error

# HC_URL (Healthchecks dead-man) is box-specific — set it in this env file on the box. Until it is
# set the backup still runs and logs; only the dead-man ping is skipped.
ENVF=/etc/smashhockey-backup.env
[ -f "$ENVF" ] && . "$ENVF"
HC_URL="${HC_URL:-}"

STAMP=$(date -u +%Y-%m-%dT%H%M%SZ)
LOG=/var/log/smashhockey-backup.log
exec >>"$LOG" 2>&1
echo "=== $STAMP === smash hockey telemetry backup run start"

[ -n "$HC_URL" ] && curl -fsS --retry 2 --max-time 10 "$HC_URL/start" >/dev/null 2>&1 || true

fail=0
CID=smashhockey-smashhockey-db-1

# pg_dump runs inside the container over the local socket (trust auth, no password) and streams
# straight to rclone — no dump file ever touches this box's disk.
echo "[$STAMP] smashhockey: dumping (pg_dump -Fc, in-container)…"
if docker exec "$CID" pg_dump -U smashhockey -d smashhockey -Fc \
  | rclone rcat "b2-stori-backups:stori-backups/smashhockey-pg/$STAMP.dump" --quiet; then
  echo "[$STAMP] smashhockey: ok"
else
  echo "[$STAMP] smashhockey: FAILED"
  fail=1
fi

echo "=== $STAMP === backup run end (fail=$fail)"

if [ "$fail" -eq 0 ]; then
  [ -n "$HC_URL" ] && { curl -fsS --retry 3 --max-time 20 "$HC_URL" >/dev/null 2>&1 || echo "[$STAMP] WARN: healthchecks success-ping failed"; }
else
  [ -n "$HC_URL" ] && tail -50 "$LOG" | curl -fsS --retry 3 --max-time 20 --data-binary @- "$HC_URL/fail" >/dev/null 2>&1 || true
fi

exit $fail
