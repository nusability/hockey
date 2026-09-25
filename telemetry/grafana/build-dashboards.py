#!/usr/bin/env python3
"""Generates the dashboard JSON in `dashboards/` (spec §18, ADR 0009).

The JSON is what Grafana provisions, but it is generated rather than hand-written, for the reason
../flashybird's generator gives: the panels share their filter clause, and keeping that in one place
is the difference between a filter fix landing everywhere and landing in whichever panels somebody
remembered.

    python3 telemetry/grafana/build-dashboards.py
    scp -r telemetry/grafana root@94.130.97.58:/opt/smashhockey/

Grafana re-reads the files within 30s. No restart.

## What this dashboard is for

SMASH-50 asked five questions, and the panels are those five questions and nothing else — not a
tour of the columns. Three of the five are **not charts**: a single proportion is a number, and
drawing one number as a bar says less than printing it.

  1. How many matches before someone stops   → a survival curve (one series)
  2. Do they finish a season                 → a number
  3. Do they come back on day 7              → a number, plus the curve it sits on
  4. What fraction ever win the cup          → a number
  5. Does iOS behave like Android            → a table, deliberately

Question 5 is a table because the measures have different units — a percentage, a count and a goal
average — and putting them on one chart would need two y-axes, which is the single worst thing a
chart can do. Two axes lie about correlation. A table just answers.

Colour appears in exactly one place: platform identity, blue then orange, from the categorical
theme, in that fixed order. Both hues were checked with a validator rather than an eye —
`ΔE 26.8` protan on the dark surface, well clear of the 8 floor — and identity is never carried by
colour alone, because every platform series is also labelled in the table's own rows.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DS = {"type": "grafana-postgresql-datasource", "uid": "sh-telemetry"}

# Blue and orange, categorical slots 1 and 2 for the dark surface. Fixed order, never cycled.
IOS_COLOR = "#3987e5"
ANDROID_COLOR = "#d95926"

# --------------------------------------------------------------------------------- the filter
# Two switches, and the defaults are the honest ones: real players on shipping builds, both
# platforms at once.
#
# `env` defaults to **production** rather than to `both`. Mixing a developer's flights into the
# numbers we make decisions from is the failure mode, and it is silent — so seeing staging has to
# be something you ask for. Note the consequence on day one: until a store build exists, the
# production view is empty and the *staging* view is where today's rows are.
#
# `platform` defaults to **both**, deliberately the other way. The dataset is one dataset because
# the game is one specification; splitting it is a question about the port, worth asking on purpose
# rather than by accident.
#
# `synthetic` rows — a launch shortcut, a developer's flight — are always out. There is no switch,
# because no question on this dashboard is about them.
FILTER = """      AND ('$env' = 'both' OR env = '$env')
      AND ('$platform' = 'both' OR platform = '$platform')
      AND NOT synthetic"""


def matches(extra=""):
    return f"""    FROM matches
    WHERE true
{FILTER}
{extra}"""


def seasons(extra=""):
    return f"""    FROM seasons
    WHERE true
{FILTER}
{extra}"""


def panel(kind, title, x, y, w, h, sql, description="", **options):
    p = {
        "type": kind, "title": title, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [{"datasource": DS, "format": "table", "rawQuery": True, "rawSql": sql, "refId": "A"}],
    }
    if description:
        p["description"] = description
    p.update(options)
    return p


def stat(title, x, y, sql, description, unit="percent", decimals=0, w=6, h=5):
    """A number, because a single proportion is a number. No sparkline, no needless colour: the
    graph mode is off, so the value is the whole panel and nothing competes with it for the eye."""
    return panel(
        "stat", title, x, y, w, h, sql, description,
        fieldConfig={"defaults": {"unit": unit, "decimals": decimals,
                                  "color": {"mode": "fixed", "fixedColor": "text"},
                                  "noValue": "no data yet"},
                     "overrides": []},
        options={"graphMode": "none", "colorMode": "none", "textMode": "value",
                 "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                 "justifyMode": "center"},
    )


def timeseries(title, x, y, w, h, sql, description, x_label, y_label, series=None):
    """One or two series over an ordinal axis. Thin 2px lines, a recessive grid, no point markers
    below 8px — and a legend only when there is more than one series to tell apart (a single
    series is named by the title)."""
    overrides = []
    for name, colour in (series or {}).items():
        overrides.append({"matcher": {"id": "byName", "options": name},
                          "properties": [{"id": "color", "value": {"mode": "fixed", "fixedColor": colour}}]})
    return panel(
        "timeseries", title, x, y, w, h, sql, description,
        fieldConfig={
            "defaults": {
                "unit": "percent", "min": 0, "max": 100,
                "custom": {"lineWidth": 2, "fillOpacity": 6, "showPoints": "auto", "pointSize": 8,
                           "drawStyle": "line", "lineInterpolation": "linear",
                           "axisLabel": y_label, "axisGridShow": True, "gradientMode": "none"},
                "noValue": "no data yet",
            },
            "overrides": overrides,
        },
        options={"legend": {"showLegend": bool(series), "displayMode": "list", "placement": "bottom"},
                 "tooltip": {"mode": "single", "sort": "none"}},
        transformations=[{"id": "convertFieldType",
                          "options": {"conversions": [{"destinationType": "number", "targetField": x_label}]}}],
    )


def table(title, x, y, w, h, sql, description, colour_platform=False):
    overrides = []
    if colour_platform:
        # The platform's own hue beside its name, so the table and the rest of the dashboard agree
        # on which is which — and the name is right there, so colour is never the only signal.
        overrides.append({
            "matcher": {"id": "byName", "options": "platform"},
            "properties": [{"id": "custom.cellOptions", "value": {"type": "color-text"}},
                           {"id": "mappings", "value": [
                               {"type": "value", "options": {"ios": {"color": IOS_COLOR, "index": 0},
                                                             "android": {"color": ANDROID_COLOR, "index": 1}}}]}],
        })
    return panel("table", title, x, y, w, h, sql, description,
                 fieldConfig={"defaults": {"custom": {"align": "auto"}, "noValue": "no data yet"},
                              "overrides": overrides},
                 options={"showHeader": True, "cellHeight": "sm",
                          "footer": {"show": False, "reducer": ["sum"], "countRows": False}})


# ------------------------------------------------------------------------------- the questions

# Q1. How many matches before someone stops.
#
# A survival curve, not a histogram of match counts. "Where do people stop" is read off the shape
# of what is left: the fraction of installs that reached at least N matches, which falls where they
# give up. A histogram of the same data puts the answer in the gaps between bars.
#
# Read it against the twenty-match line (§17.2's hard-fought threshold): if the curve is under
# half by then, most players never reach the branch at all.
SURVIVAL = f"""WITH per_install AS (
  SELECT install_id, count(*) AS played
{matches()}
  GROUP BY install_id
), total AS (
  SELECT count(*)::float AS installs FROM per_install
)
SELECT n AS "match",
       CASE WHEN (SELECT installs FROM total) = 0 THEN NULL
            ELSE 100.0 * (SELECT count(*) FROM per_install WHERE played >= n) / (SELECT installs FROM total)
       END AS "installs still playing"
  FROM generate_series(1, 40) AS n
 ORDER BY n"""

# Q3. Do they come back — the curve the day-7 number sits on.
#
# Per install: the days between its first match and its last. A player who came back on day 7 has a
# span of at least 7. Installs younger than the day they are being counted at are excluded, or a
# phone that installed this morning would read as churn on day 7.
RETURN_CURVE = f"""WITH span AS (
  SELECT install_id,
         min(at) AS first_ms,
         (max(at) - min(at)) / 86400000.0 AS days
{matches()}
  GROUP BY install_id
)
SELECT d AS "day",
       CASE WHEN count(*) FILTER (WHERE (extract(epoch FROM now()) * 1000 - first_ms) / 86400000.0 >= d) = 0
            THEN NULL
            ELSE 100.0 * count(*) FILTER (WHERE days >= d)
                 / count(*) FILTER (WHERE (extract(epoch FROM now()) * 1000 - first_ms) / 86400000.0 >= d)
       END AS "installs still coming back"
  FROM generate_series(1, 14) AS d, span
 GROUP BY d
 ORDER BY d"""

DAY7 = f"""WITH span AS (
  SELECT install_id, min(at) AS first_ms, (max(at) - min(at)) / 86400000.0 AS days
{matches()}
  GROUP BY install_id
), eligible AS (
  SELECT * FROM span WHERE (extract(epoch FROM now()) * 1000 - first_ms) / 86400000.0 >= 7
)
SELECT CASE WHEN count(*) = 0 THEN NULL
            ELSE 100.0 * count(*) FILTER (WHERE days >= 7) / count(*) END AS "day 7"
  FROM eligible"""

# Q2. Do they finish a season — of the installs that started one.
#
# The denominator is installs that played a league or cup match, not every install: someone who has
# only ever played a friendly has not declined to finish a season, they have not started one.
FINISH = f"""WITH started AS (
  SELECT DISTINCT install_id
{matches("      AND competition IN ('league', 'cup')")}
), finished AS (
  SELECT DISTINCT install_id
{seasons()}
)
SELECT CASE WHEN (SELECT count(*) FROM started) = 0 THEN NULL
            ELSE 100.0 * (SELECT count(*) FROM finished) / (SELECT count(*) FROM started) END
       AS "finished a season\""""

# Q4. What fraction ever win the cup — of the installs that finished a season.
CUP = f"""WITH ended AS (
  SELECT install_id, bool_or(cup_won) AS won
{seasons()}
  GROUP BY install_id
)
SELECT CASE WHEN count(*) = 0 THEN NULL
            ELSE 100.0 * count(*) FILTER (WHERE won) / count(*) END AS "won the cup"
  FROM ended"""

# Q5. Does iOS behave like Android.
#
# A table on purpose. These are a percentage, a count and a goal average — three units — and one
# chart carrying them would need two y-axes, which is the one thing a chart must never do. The
# question is "are these numbers the same", and two rows of numbers answer it exactly.
#
# The platform filter is deliberately not applied here: this panel *is* the comparison, so
# narrowing it to one platform would leave nothing to compare.
PARITY = """WITH m AS (
  SELECT platform, install_id, count(*) AS played,
         avg(goals_for)::numeric(10,2) AS gf, avg(goals_against)::numeric(10,2) AS ga,
         count(*) FILTER (WHERE result = 'won') AS won
    FROM matches
   WHERE ('$env' = 'both' OR env = '$env') AND NOT synthetic
   GROUP BY platform, install_id
)
SELECT platform,
       count(*)                               AS installs,
       sum(played)                            AS matches,
       round(avg(played), 1)                  AS "matches per install",
       round(100.0 * sum(won) / NULLIF(sum(played), 0), 1) AS "won %",
       round(avg(gf), 2)                      AS "goals for",
       round(avg(ga), 2)                      AS "goals against"
  FROM m
 GROUP BY platform
 ORDER BY platform"""

# The header: is anything arriving at all? Not one of the five questions, but the first thing to
# look at when an answer is empty — an empty dashboard and a broken pipe look identical otherwise.
INSTALLS = f"""SELECT count(DISTINCT install_id) AS installs
{matches()}"""
PLAYED = f"""SELECT count(*) AS matches
{matches()}"""
LATEST = f"""SELECT to_timestamp(max(at) / 1000) AS "last row"
{matches()}"""

RECENT = f"""SELECT to_timestamp(at / 1000) AS "played at", platform, env, commit, world, competition,
       goals_for AS gf, goals_against AS ga, result, trailed, hard_fought, matches_played AS "lifetime"
{matches()}
 ORDER BY at DESC
 LIMIT 50"""


def row(title, y):
    return {"type": "row", "title": title, "collapsed": False, "gridPos": {"x": 0, "y": y, "w": 24, "h": 1},
            "panels": []}


def dashboard():
    panels = [
        row("Is anything arriving?", 0),
        stat("Installs", 0, 1, INSTALLS, "Distinct install ids that have played a match.",
             unit="none", w=5, h=4),
        stat("Matches", 5, 1, PLAYED, "Rows in `matches`.", unit="none", w=5, h=4),
        stat("Last row", 10, 1, LATEST,
             "By the device's own clock. If this is old, nothing is sending — check the app's launch log.",
             unit="dateTimeAsIso", w=14, h=4),

        row("The five questions", 5),
        timeseries("1 · How many matches before someone stops", 0, 6, 12, 8, SURVIVAL,
                   "The fraction of installs that reached at least N matches. Read where it falls; "
                   "the 20-match mark is §17.2's hard-fought threshold.",
                   x_label="match", y_label="% of installs"),
        timeseries("3 · Do they come back", 12, 6, 12, 8, RETURN_CURVE,
                   "The fraction still returning N days after their first match. Installs younger "
                   "than the day being counted are excluded, so a phone set up this morning is not churn.",
                   x_label="day", y_label="% of installs"),
        stat("2 · Finished a season", 0, 14, FINISH,
             "Of installs that played a league or cup match. Someone who has only played a friendly "
             "has not started a season, so they are not in the denominator."),
        stat("3 · Came back on day 7", 6, 14, DAY7,
             "Of installs at least 7 days old. This is the number A3 lives or dies by."),
        stat("4 · Ever won the cup", 12, 14, CUP,
             "Of installs that finished a season. If this is near zero the cup is not a reward, it is a rumour."),
        stat("Seasons finished", 18, 14, f"""SELECT count(*) AS seasons
{seasons()}""",
             "Rows in `seasons`.", unit="none"),

        row("5 · Does iOS behave like Android", 19),
        table("Both platforms, same measures", 0, 20, 24, 6, PARITY,
              "A table and not a chart: these are a percentage, a count and a goal average, and one "
              "chart carrying three units would need two y-axes. A difference here that is not a "
              "written platform-delta row is a bug. Ignores the platform picker — this panel is the "
              "comparison.", colour_platform=True),

        row("The last 50 rows", 26),
        table("Most recent matches", 0, 27, 24, 10, RECENT,
              "For confirming a build actually reports, and what it reports. `commit` is the code that "
              "wrote the row (§18.1).", colour_platform=True),
    ]
    return {
        "uid": "smash-overview",
        "title": "Smash Hockey — how it is played",
        "description": "The five questions SMASH-50 asked, and nothing else. Panels are generated: "
                       "edit telemetry/grafana/build-dashboards.py, not this JSON, and not the UI.",
        "tags": ["smash-hockey"],
        "timezone": "utc",
        "editable": False,
        "schemaVersion": 39,
        "refresh": "",
        # Every panel filters on the device's own clock in milliseconds, not on Grafana's time range,
        # because these are lifetime questions: "how many matches before someone stops" is not a
        # question about the last six hours. The picker is left in place but nothing reads it.
        "time": {"from": "now-90d", "to": "now"},
        "templating": {"list": [
            {"name": "env", "label": "Build", "type": "custom",
             "query": "production,staging,both", "current": {"text": "production", "value": "production"},
             "options": [{"text": t, "value": t, "selected": t == "production"}
                         for t in ("production", "staging", "both")],
             "description": "Defaults to production: a developer's flights must never quietly join the "
                            "numbers. Until a store build exists, production is empty and today's rows "
                            "are under staging."},
            {"name": "platform", "label": "Platform", "type": "custom",
             "query": "both,ios,android", "current": {"text": "both", "value": "both"},
             "options": [{"text": t, "value": t, "selected": t == "both"}
                         for t in ("both", "ios", "android")],
             "description": "Defaults to both: one game, one dataset. Splitting it is a question about "
                            "the port, worth asking on purpose."},
        ]},
        "panels": panels,
    }


def main():
    out = os.path.join(HERE, "dashboards", "smash-overview.json")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(dashboard(), f, indent=2, sort_keys=False)
        f.write("\n")
    print(f"wrote {os.path.relpath(out, os.path.dirname(HERE))}")


if __name__ == "__main__":
    main()
