# Telemetry collector

The server half of spec §18 / ADR 0009. **Deployed** — `https://ingest.nann.in/smash/*`, live since
2026-09-23, `/opt/smashhockey` on **box #2 (`stori-monitoring`)**, collector on loopback **3014**
(3000–3003 and 3010–3013 were already taken).

Nothing here is part of either app, and neither app depends on it being up: with no endpoint
configured the client is inert, and a failed send is dropped rather than retried (A0, A2 — nothing
may sit between a result and the next face-off).

**Both apps send** (spec §18, since 2026-09-23): a played match and a finished season, queued in memory
and flushed when the player reaches the hub or the app goes to the background. The love dialog's two
routes have their senders and no call site yet — no screen asks the question (§17). A build with no
endpoint configured sends nothing, and a test run sends nothing ever; the client refuses both at the
source, because a robot's row is indistinguishable from a person's once it has arrived.

## The one thing to understand

`schema.sql` and `columns.json` are **generated** from `shared/data/telemetry.toml` by
`tools/generate-data.py`, which also writes the two apps' record types from the same declaration.
`server.js` has **no column list in it** — it reads `columns.json` at boot and builds its INSERTs
from that.

This is not tidiness. `../flashybird`'s collector kept its columns by hand, and its own schema header
records the result: `platform`, `language` and the five columns its difficulty question grouped on
were *sent and not inserted* for months. In its words —

> A column missing from this list is not an error at any layer; it is a default quietly standing in
> for a measurement.

A column cannot go missing here, because nothing here names one. Edit `telemetry.toml`, run the
generator, and the Swift type, the Kotlin type, the DDL, the contract and the INSERT all move
together — or `python3 tools/generate-data.py --check` fails.

⚠️ **Never edit `schema.sql`, `columns.json` or the generated record types.** Edit the declaration.

⚠️ **A wire column may not be a `double` or an `rgb`** — the generator refuses one. The canonical JSON
writer both apps share encodes a double as its exact bit pattern, a JSON *string* (`"0x405E…"`), which
is right for a save a vector pins byte for byte and wrong for a column typed as a number: the collector
would reject the whole row with `period_seconds is not a number`. Found the honest way, by generating
the client's bytes and reading them, before anything was sent — `period_seconds` became `period_ms`.
Say instants and durations in integer milliseconds, which is what everything else here already does.

The two versions in `telemetry.toml` are not one: `[format]` is `device.json`'s file format (§17.1) and
`[wire]` is these four tables' column contract (§18.6). `columns.json` carries the latter as `"wire"`,
and the collector logs it at boot. A change to one must never move the other.

## Shape

`ingest.nann.in` is a **shared ingest host**, not Smash Hockey's own. `*.nann.in` resolves to this
box, so every future product is a path here and needs no DNS record, no certificate and no new vhost.
Per-product paths, separate collectors, **separate schemas** — never a shared table: two games'
telemetry are not one dataset, and a shared table would be either a union of every game's columns
(mostly NULL) or a JSON blob.

That settles the open caveat ADR 0009 left for the day the collector was built: **flat, one column
set per event kind.**

| route | table | one row per |
|---|---|---|
| `POST /smash/matches` | `matches` | played match |
| `POST /smash/seasons` | `seasons` | finished season |
| `POST /smash/love` | `love` | love-dialog showing and its answer |
| `POST /smash/feedback` | `feedback` | message a player typed |

`feedback` is a separate table **because it is the only one that carries a player's words**, and the
type that holds them is not an analytics row — so a call site cannot put free text into one.

Both `env` values (`staging`, `production`) share a table with a column to tell them apart, so the two
can be compared; every query that means production says so. Same for `platform` — "does iOS behave
like Android" is a question you cannot ask of two tables.

⚠️ **Routes, event names, column names and the payload shape are a ONE-WAY DOOR from the first
shipped build.** An installed app cannot be rewired: `fb.nann.in` has to keep answering forever
because real phones hold it. Nothing ships yet, so they are still free to change.

## What the collector refuses

A row is **rejected, never defaulted**. A missing required column is a 400 with the column named in
the log, because a default standing in for a measurement is the failure this design exists against.

| | |
|---|---|
| no / wrong bearer token | `401` |
| a table that is not declared | `404` |
| body over 1 MB, batch over 200 | `413` / `400` |
| a missing required column | `400` — `synthetic is required` |
| a value outside a declared enum | `400` — `answer is not one of positive\|negative\|dismissed` |

The token is **not a secret in any real sense** — it ships inside the app binary and anyone who wants
it can read it out. It is a doormat, not a lock: it stops a scanner writing rows into the dataset we
make design decisions from. Real abuse means rotating it and shipping a build.

## Deploy

```sh
# from the repo, after `python3 tools/generate-data.py` and
# `python3 telemetry/grafana/build-dashboards.py`
scp telemetry/{server.js,package.json,schema.sql,columns.json,docker-compose.yml} \
    root@94.130.97.58:/opt/smashhockey/
scp -r telemetry/grafana root@94.130.97.58:/opt/smashhockey/

# on box #2, as root
cd /opt/smashhockey
umask 077                                   # generate ON the box; never echo them
{ echo "SH_DB_PASSWORD=$(openssl rand -hex 24)"
  echo "SH_INGEST_TOKEN=$(openssl rand -hex 16)"
  echo "SH_GRAFANA_PASSWORD=$(openssl rand -hex 16)"; } > .env
docker compose up -d                        # schema.sql runs on first boot

# then the two vhosts — ingest, and the dashboard on its own host
cp -a /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%s)
cat Caddyfile.snippet Caddyfile.dash.snippet >> /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile && systemctl reload caddy
```

A dashboard-only change needs no `docker compose` anything: `scp -r telemetry/grafana` and wait 30s.

⚠️ **`caddy validate` is not a rehearsal of the reload.** A `log { output file … }` block validates
clean and then fails the *reload* on permissions, because Caddy runs as `caddy` and cannot create a
file in a root-owned directory (`../flashybird` learned this). The snippet therefore has no log
block — every other vhost on this box logs to journald, which Loki already collects. **Check
`systemctl is-active caddy` actually says `active`.**

`columns.json` is read **at boot**, so a declaration change needs `docker compose restart collector`
before the new column exists as far as the INSERT is concerned.

`schema.sql` only runs on the database's *first* boot. A later declaration change is applied by hand —
the db service is `smashhockey-db`:

```sh
docker compose exec -T smashhockey-db psql -U smashhockey -d smashhockey -c "DROP TABLE matches;"
docker compose exec -T smashhockey-db psql -U smashhockey -d smashhockey -f - < schema.sql
```

— it is idempotent. While nothing has shipped, a change may simply drop and rebuild a
table (`conventions.md`, greenfield); from the first shipped build a column is added with an explicit
default, never renamed or removed.

**To read the ingest token** for the client's config, on the box: `grep SH_INGEST_TOKEN
/opt/smashhockey/.env`. Never paste it into a commit, a ticket or a chat.

## Backups

`smashhockey-backup.timer`, nightly **04:07 UTC** — after bugsink (03:17) and flashybird (03:42), so
three `pg_dump`s never contend on a 8 GB box. `pg_dump -Fc` streamed straight to B2 under
`smashhockey-pg/`; no dump file touches the box's disk. Source of truth is `backup.sh` here — edit it
here, then `scp` to `/usr/local/bin/smashhockey-backup.sh`.

The box's D7 rule is that config-as-code *is* the backup. This is the exception: the schema needs no
backup (it is generated), but the rows do — regenerating them means asking players to replay the game.

## The dashboard

`https://dash.nann.in/smash` — its own Grafana, a service in `docker-compose.yml`, live since
2026-09-23. A **different host from the ingest one on purpose**: `ingest.nann.in` says "nothing here
reads" in its vhost and its README, and that stays true. `*.nann.in` is a wildcard, so the second
hostname cost one vhost and no DNS record.

Its own instance rather than a folder in the box's shared Grafana, for the three reasons
`../flashybird` wrote down: the shared instance's provisioning is config-as-code in the *stori* repo,
so every panel change here would be a cross-repo edit into a project under active development; its
`grafana_data` volume is in no backup, so panels made there survive only as long as the volume; and
two products would share an upgrade cadence they have no reason to share.

**The dashboards are the backup.** `grafana/dashboards/*.json` is generated by
`grafana/build-dashboards.py`, provisioned read-only (`allowUiUpdates: false`), and a total loss of
the volume costs a login. A panel edited in the browser would be silently reverted on the next
restart — edit the generator, run it, `scp -r telemetry/grafana`, and Grafana re-reads within 30s
with no restart.

⚠️ **Never hand-edit `grafana/dashboards/*.json`.** Edit the generator.

The panels are SMASH-50's five questions and nothing else, not a tour of the columns. `env` defaults
to **production**, because mixing a developer's flights into the numbers we decide from is the silent
failure.

## Not here

This is the **seventh** Postgres on this box — noted rather than shrugged at. It fits (5.1 GB
available, ~150 MB for this one); if it ever gets tight, the cheaper shape is a `smashhockey` database
inside an existing cluster, at the cost of coupling this schema to another product's container
lifecycle.

⚠️ This adds another public service to a box whose **D4 says "only Grafana is public."** A collector
has to be publicly reachable — phones POST to it — so the exception is unavoidable, but it *is* an
exception, and it is why the token, the body cap and the write-only routes exist. Nothing here reads.

And since `*.nann.in` is a wildcard, **the Caddyfile is now the only gate on what is public**: a stray
vhost is a publish. Do not enable Caddy's `on_demand_tls` without an `ask` gate — every invented
hostname resolves, so it would turn this box into an unbounded ACME client against Let's Encrypt.
