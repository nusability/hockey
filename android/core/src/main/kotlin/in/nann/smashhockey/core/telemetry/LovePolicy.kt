package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.Tuning

/*
 * When the game may ask "Enjoying Smash Hockey?" (spec §17.2), as two pure functions over values.
 *
 * The iOS twin is SmashCore's `Telemetry/LovePolicy.swift` — hand-written twice, never shared
 * (ADR 0001), and pinned against each other by shared/vectors/telemetry/love.txt, which both suites
 * replay.
 *
 * Deliberately holding no clock, no storage and no UI: the clock is an argument. Every threshold in
 * the spec is then a line in a vector rather than something you have to run an app for ninety days to
 * observe — and the whole point of the corpus is that a rule which cannot be pinned headlessly is a
 * rule that ships unproven (ADR 0009).
 *
 * Nothing here touches the simulation: it reads a finished match's goals after the fact and draws
 * from no seeded stream, so §4 determinism is untouched by construction.
 */
object LovePolicy {

    // --- The thresholds (spec §17.2, shared/data/rules.toml [love]) -------------------------------

    /**
     * The hard-fought-win branch arms nothing before this many matches: one good match is a moment,
     * twenty is a habit. The cup and the league arm at any count — winning either *is* the habit.
     */
    const val HARD_FOUGHT_MATCHES: Int = Tuning.Love.hardFoughtMatches

    /**
     * One showing per cooldown, forever, counted from the presentation and in **absolute** time. A
     * day is 86 400 000 ms and never a calendar day: calendar arithmetic makes exactly ninety days
     * read as eighty-nine across an autumn clock change, so the same code would behave differently by
     * timezone for no reason a player could ever understand.
     */
    const val COOLDOWN_MILLIS: Long = Tuning.Love.cooldownDays * 86_400_000L

    // --- Arming (spec §17.2) ---------------------------------------------------------------------

    /**
     * What a finished player match earned, if anything. Checked in the order the spec names: a trophy
     * outranks a good game, so a cup final that was also hard-fought reports the cup.
     */
    fun trigger(match: LoveMatch, matchesPlayed: Int): LoveTrigger? = when {
        match.wonCup -> LoveTrigger.CUP
        match.wonLeague -> LoveTrigger.LEAGUE
        matchesPlayed >= HARD_FOUGHT_MATCHES && match.wasHardFought -> LoveTrigger.HARD_FOUGHT
        else -> null
    }

    // --- Showing (spec §17.3) --------------------------------------------------------------------

    /**
     * Whether the panel may go up right now, and when it may not, why.
     *
     * The order of the checks is the order of the rules' strength, and it is part of the contract: a
     * yes is final, so it is asked first and alone; the kill switch outranks everything we know about
     * the player; and a cooldown is only interesting once something armed.
     *
     * Note `>=` against the cooldown rather than `==` against a count anywhere in here: the old
     * implementation this is modelled on (`../vidi`) triggered on an *exact* match, so any tick that
     * skipped the threshold silently cost the player their only prompt. That bug is not ported.
     */
    fun decide(facts: LoveFacts, now: Long): LoveVerdict {
        // A yes ends the asking entirely — the spec's strongest rule (§17.2).
        if (facts.answeredPositively) return LoveVerdict.SAID_YES
        when (facts.remote) {
            // Silent until config has been read once, rather than racing the flag (§17.4).
            LoveSwitch.UNREAD -> return LoveVerdict.SWITCH_UNREAD
            LoveSwitch.OFF -> return LoveVerdict.SWITCH_OFF
            LoveSwitch.ON -> Unit
        }
        if (facts.armed == null) return LoveVerdict.NOT_ARMED
        // Never shown ⇒ no cooldown to serve. A record we lost is stamped as just-shown instead of
        // absent (§17.1), so "absent" here really does mean a device that has never been asked.
        val last = facts.lastAskedAt
        if (last != null && elapsedMillis(last, now) < COOLDOWN_MILLIS) return LoveVerdict.COOLDOWN
        return LoveVerdict.ASK
    }

    /**
     * Elapsed milliseconds between two instants, floored at zero.
     *
     * A clock that has gone backwards — timezone travel, a corrected device clock, a restored
     * backup — must never read as "a long time has passed", which would burn the prompt at the wrong
     * moment. Negative elapsed time is therefore zero, which fails the cooldown and keeps the game
     * quiet until the clock catches up with itself.
     */
    fun elapsedMillis(start: Long, end: Long): Long = if (end <= start) 0L else end - start
}

/**
 * What armed the prompt (spec §17.2). Also the reason reported with the answer, so the four events
 * can be read by what earned them.
 */
enum class LoveTrigger(val key: String) {
    /** The cup won (§11). */
    CUP("cup"),

    /** The league won (§11). */
    LEAGUE("league"),

    /** A win worth remembering: one goal, late — or one the player came back for. */
    HARD_FOUGHT("hardFought"),
}

/**
 * The remote kill switch (spec §17.4). It **defaults to on**: a backend outage can never disable a
 * working feature, only a deliberate flip can, so a failed fetch resolves to [ON] and not to
 * [UNREAD]. [UNREAD] is the state before config has been read at all.
 */
enum class LoveSwitch(val key: String) {
    UNREAD("unread"),
    ON("on"),
    OFF("off"),
}

/**
 * Everything [LovePolicy.decide] is allowed to know: what just happened, and what the device
 * remembers. Grouped so a call site cannot pass arguments in the wrong order, and so a fact added
 * later is not a source break.
 */
data class LoveFacts(
    /**
     * What armed the prompt, carried from the moment it happened to the settled screen where it is
     * shown (§17.3). Null is the ordinary case: nothing earned it.
     */
    val armed: LoveTrigger?,
    val lastAskedAt: Long?,
    val answeredPositively: Boolean,
    val remote: LoveSwitch,
)

/**
 * What [LovePolicy.decide] said, and why. Every verdict but [ASK] is a reason the game stayed quiet;
 * they are distinguished so a vector pins *which* rule held, not merely that one did.
 */
enum class LoveVerdict(val key: String) {
    ASK("ask"),

    /** A positive answer ended it, forever (§17.2). */
    SAID_YES("saidYes"),
    SWITCH_OFF("switchOff"),

    /** Config has not been read yet (§17.4). */
    SWITCH_UNREAD("switchUnread"),

    /** Nothing earned it. */
    NOT_ARMED("notArmed"),

    /** Within the cooldown of the last showing (§17.2). */
    COOLDOWN("cooldown"),
}

/**
 * A finished player match, as far as the love dialog is concerned (spec §17.2): its goals in the
 * order they were scored, and how long it lasted. Derived from the match events the flow already
 * emits — this adds no match state and never touches the simulation.
 *
 * The margin, the comeback and the winning goal are computed **here**, from the goal tape, rather
 * than by each app: one rule, one place, two platforms, pinned by the corpus.
 */
data class LoveMatch(
    val goals: List<Goal>,
    /** The match's whole length in milliseconds, overtime included: periods × period length (§12). */
    val durationMillis: Int,
    /** This match won the cup (§11.2) — the final, and the player took it. */
    val wonCup: Boolean = false,
    /** This match won the league (§11.1) — the last matchday, and the player finished top. */
    val wonLeague: Boolean = false,
) {
    /** One goal: whose it was, and how far into the match it fell. */
    data class Goal(
        /** The player's team scored it (an own goal counts for whoever it benefits, as §8 scores it). */
        val mine: Boolean,
        /** Milliseconds of match time elapsed when it was scored — the whole match, not the period. */
        val atMillis: Int,
    )

    val goalsFor: Int get() = goals.count { it.mine }
    val goalsAgainst: Int get() = goals.size - goalsFor
    val won: Boolean get() = goalsFor > goalsAgainst

    /**
     * The opponent led at some point. Read off the tape in order, so a match that was level all the
     * way and won at the death does not count as a comeback.
     */
    val trailed: Boolean
        get() {
            var mine = 0
            var theirs = 0
            for (goal in goals) {
                if (goal.mine) mine++ else theirs++
                if (theirs > mine) return true
            }
            return false
        }

    /**
     * The winner's `(loser's goals + 1)`-th goal — the one that gave them a lead they never gave
     * back. Null when the player did not win, or when the tape is shorter than the score says.
     */
    val winningGoalMillis: Int?
        get() {
            if (!won) return null
            var mine = 0
            for (goal in goals) {
                if (!goal.mine) continue
                mine++
                if (mine == goalsAgainst + 1) return goal.atMillis
            }
            return null
        }

    /**
     * The winning goal fell in the final third: `3 × elapsed ≥ 2 × duration`, in integers, so both
     * platforms agree on the boundary to the millisecond instead of to within a rounding.
     *
     * Widened to 64-bit for the multiplication alone. Kotlin's `Int` is 32-bit and Swift's is 64-bit,
     * so at an absurd match length the two would disagree — one overflowing where the other does not
     * is exactly the divergence the parity rule exists to forbid, and it costs nothing to close.
     */
    val winningGoalWasLate: Boolean
        get() {
            val at = winningGoalMillis ?: return false
            return durationMillis > 0 && 3L * at >= 2L * durationMillis
        }

    /**
     * A win worth asking about (§17.2): by exactly one goal with the winning goal late, **or** won
     * after having trailed at any point. A 6–0 stroll is not a story; neither is a draw.
     */
    val wasHardFought: Boolean
        get() = won && ((goalsFor - goalsAgainst == 1 && winningGoalWasLate) || trailed)

    companion object {
        /**
         * How far into the match the clock stood, in milliseconds, from what a snapshot holds: the
         * period, the seconds left in it, and the period's length (§12). This is **match time, not
         * wall time** — a face-off that took two seconds to drop is not two seconds of the match —
         * which is what makes it comparable with [durationMillis] and with the final-third boundary
         * (§17.2).
         *
         * Overtime reads as the whole match having run: a golden goal is by definition the last one,
         * and it is late by any measure worth the name.
         */
        fun elapsedMillis(
            period: Int,
            remainingSeconds: Double,
            periodSeconds: Double,
            overtime: Boolean,
            periods: Int = Tuning.Match.periods,
        ): Int {
            val whole = Math.round(periods * periodSeconds * 1000).toInt()
            if (overtime) return whole
            val played = maxOf(period - 1, 0) * periodSeconds + maxOf(0.0, periodSeconds - remainingSeconds)
            return minOf(whole, maxOf(0, Math.round(played * 1000).toInt()))
        }
    }
}
