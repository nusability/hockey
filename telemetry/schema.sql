-- Smash Hockey telemetry — the schema (spec §18, ADR 0009).
--
-- GENERATED from shared/data/telemetry.toml by tools/generate-data.py. Do not edit: run the
-- generator. A hand edit here is caught by `python3 tools/generate-data.py --check`, which is the
-- guard that makes this file trustworthy — and the reason it is generated at all is written at the
-- top of tools/datagen/collector.py.
--
-- Idempotent: every statement is IF NOT EXISTS, so running it twice is running it once.
--
-- There are deliberately **no ALTER statements**. Nothing has been submitted to either store, so
-- conventions.md's greenfield section is still awake and a declaration change simply drops and
-- rebuilds the table. From the first shipped build that stops being true — rows written by installs
-- we can no longer update have to stay readable — and a change then adds a column with an explicit
-- default, never renames or removes one. Generating an ALTER per column before then was worse than
-- useless: it emitted `UUID NOT NULL DEFAULT ''` and would have failed on the table it claimed to
-- catch up.

-- One played match (spec §18.2). Enough to answer how many matches a player gets through, whether they come back, and whether the two platforms behave alike — and deliberately not a per-touch tape: there is no difficulty heatmap here to fill.
CREATE TABLE IF NOT EXISTS matches (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    "install_id"       UUID NOT NULL,
    "commit"           TEXT NOT NULL,
    "at"               BIGINT NOT NULL,
    "platform"         TEXT NOT NULL
        CHECK ("platform" IN ('ios', 'android')),
    "env"              TEXT NOT NULL
        CHECK ("env" IN ('staging', 'production')),
    "language"         TEXT NOT NULL,
    "synthetic"        BOOLEAN NOT NULL,
    "sport"            TEXT NOT NULL,
    "world"            TEXT NOT NULL,
    "competition"      TEXT NOT NULL
        CHECK ("competition" IN ('league', 'cup', 'quick', 'drill')),
    "season_number"    INT,
    "matchday"         INT,
    "goals_for"        INT NOT NULL,
    "goals_against"    INT NOT NULL,
    "result"           TEXT NOT NULL
        CHECK ("result" IN ('won', 'drew', 'lost')),
    "overtime"         BOOLEAN NOT NULL,
    "forfeit"          BOOLEAN NOT NULL,
    "duration_ms"      INT NOT NULL,
    "period_ms"        INT NOT NULL,
    "formation"        TEXT NOT NULL,
    "matches_played"   INT NOT NULL,
    "trailed"          BOOLEAN NOT NULL,
    "hard_fought"      BOOLEAN NOT NULL
);
CREATE INDEX IF NOT EXISTS matches_env     ON matches ("env", "synthetic", "at" DESC);
CREATE INDEX IF NOT EXISTS matches_install ON matches ("install_id", "at");

-- One finished season (spec §18.3): where the player came and what they won. This is what 'do they finish a season' and 'what fraction ever win the cup' are read from.
CREATE TABLE IF NOT EXISTS seasons (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    "install_id"       UUID NOT NULL,
    "commit"           TEXT NOT NULL,
    "at"               BIGINT NOT NULL,
    "platform"         TEXT NOT NULL
        CHECK ("platform" IN ('ios', 'android')),
    "env"              TEXT NOT NULL
        CHECK ("env" IN ('staging', 'production')),
    "language"         TEXT NOT NULL,
    "synthetic"        BOOLEAN NOT NULL,
    "season_number"    INT NOT NULL,
    "position"         INT NOT NULL,
    "points"           INT NOT NULL,
    "played"           INT NOT NULL,
    "won"              INT NOT NULL,
    "drawn"            INT NOT NULL,
    "lost"             INT NOT NULL,
    "goals_for"        INT NOT NULL,
    "goals_against"    INT NOT NULL,
    "champion"         BOOLEAN NOT NULL,
    "cup_won"          BOOLEAN NOT NULL,
    "matches_played"   INT NOT NULL
);
CREATE INDEX IF NOT EXISTS seasons_env     ON seasons ("env", "synthetic", "at" DESC);
CREATE INDEX IF NOT EXISTS seasons_install ON seasons ("install_id", "at");

-- One love-dialog showing and the answer it got (spec §18.4). Carries no free text — by type: the message has its own record and its own table, so a call site cannot put a player's words into an analytics row.
CREATE TABLE IF NOT EXISTS love (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    "install_id"       UUID NOT NULL,
    "commit"           TEXT NOT NULL,
    "at"               BIGINT NOT NULL,
    "platform"         TEXT NOT NULL
        CHECK ("platform" IN ('ios', 'android')),
    "env"              TEXT NOT NULL
        CHECK ("env" IN ('staging', 'production')),
    "language"         TEXT NOT NULL,
    "synthetic"        BOOLEAN NOT NULL,
    "trigger"          TEXT NOT NULL
        CHECK ("trigger" IN ('cup', 'league', 'hardFought')),
    "answer"           TEXT NOT NULL
        CHECK ("answer" IN ('positive', 'negative', 'dismissed')),
    "shown_at"         BIGINT NOT NULL,
    "matches_played"   INT NOT NULL
);
CREATE INDEX IF NOT EXISTS love_env     ON love ("env", "synthetic", "at" DESC);
CREATE INDEX IF NOT EXISTS love_install ON love ("install_id", "at");

-- One message a player typed after answering 'Not really' (spec §18.5). **The only row that carries free text, and it is the whole reason this table exists apart from the others**: an analytics row can never hold a player's words, because the type that holds them is not an analytics row.
CREATE TABLE IF NOT EXISTS feedback (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    "install_id"       UUID NOT NULL,
    "commit"           TEXT NOT NULL,
    "at"               BIGINT NOT NULL,
    "platform"         TEXT NOT NULL
        CHECK ("platform" IN ('ios', 'android')),
    "env"              TEXT NOT NULL
        CHECK ("env" IN ('staging', 'production')),
    "language"         TEXT NOT NULL,
    "synthetic"        BOOLEAN NOT NULL,
    "message"          TEXT NOT NULL,
    "trigger"          TEXT NOT NULL
        CHECK ("trigger" IN ('cup', 'league', 'hardFought')),
    "matches_played"   INT NOT NULL
);
CREATE INDEX IF NOT EXISTS feedback_env     ON feedback ("env", "synthetic", "at" DESC);
CREATE INDEX IF NOT EXISTS feedback_install ON feedback ("install_id", "at");
