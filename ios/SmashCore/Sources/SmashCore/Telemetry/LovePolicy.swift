/// When the game may ask "Enjoying Smash Hockey?" (spec §17.2), as two pure functions over values.
///
/// The Android twin is `core/telemetry/LovePolicy.kt` — hand-written twice, never shared (ADR 0001),
/// and pinned against each other by `shared/vectors/telemetry/love.txt`, which both suites replay.
///
/// Deliberately holding no clock, no storage and no UI: the clock is an argument. Every threshold in
/// the spec is then a line in a vector rather than something you have to run an app for ninety days
/// to observe — and the whole point of the corpus is that a rule which cannot be pinned headlessly
/// is a rule that ships unproven (ADR 0009).
///
/// Nothing here touches the simulation: it reads a finished match's goals after the fact and draws
/// from no seeded stream, so §4 determinism is untouched by construction.
public enum LovePolicy {

    // MARK: - The thresholds (spec §17.2, shared/data/rules.toml [love])

    /// The hard-fought-win branch arms nothing before this many matches: one good match is a moment,
    /// twenty is a habit. The cup and the league arm at any count — winning either *is* the habit.
    public static let hardFoughtMatches = Tuning.Love.hardFoughtMatches

    /// One showing per cooldown, forever, counted from the presentation and in **absolute** time.
    /// A day is 86 400 000 ms and never a calendar day: calendar arithmetic makes exactly ninety
    /// days read as eighty-nine across an autumn clock change, so the same code would behave
    /// differently by timezone for no reason a player could ever understand.
    public static let cooldownMillis = Int64(Tuning.Love.cooldownDays) * 86_400_000

    // MARK: - Arming (spec §17.2)

    /// What a finished player match earned, if anything. Checked in the order the spec names: a
    /// trophy outranks a good game, so a cup final that was also hard-fought reports the cup.
    public static func trigger(_ match: LoveMatch, matchesPlayed: Int) -> LoveTrigger? {
        if match.wonCup { return .cup }
        if match.wonLeague { return .league }
        guard matchesPlayed >= hardFoughtMatches, match.wasHardFought else { return nil }
        return .hardFought
    }

    // MARK: - Showing (spec §17.3)

    /// Whether the panel may go up right now, and when it may not, why.
    ///
    /// The order of the checks is the order of the rules' strength, and it is part of the contract:
    /// a yes is final, so it is asked first and alone; the kill switch outranks everything we know
    /// about the player; and a cooldown is only interesting once something armed.
    ///
    /// Note `>=` against the cooldown rather than `==` against a count anywhere in here: the old
    /// implementation this is modelled on (`../vidi`) triggered on an *exact* match, so any tick
    /// that skipped the threshold silently cost the player their only prompt. That bug is not ported.
    public static func decide(_ facts: LoveFacts, now: Int64) -> LoveVerdict {
        // A yes ends the asking entirely — the spec's strongest rule (§17.2).
        if facts.answeredPositively { return .saidYes }
        switch facts.remote {
        // Silent until config has been read once, rather than racing the flag (§17.4).
        case .unread: return .switchUnread
        case .off: return .switchOff
        case .on: break
        }
        guard facts.armed != nil else { return .notArmed }
        // Never shown ⇒ no cooldown to serve. A record we lost is stamped as just-shown instead of
        // absent (§17.1), so "absent" here really does mean a device that has never been asked.
        if let last = facts.lastAskedAt, elapsedMillis(from: last, to: now) < cooldownMillis {
            return .cooldown
        }
        return .ask
    }

    /// Elapsed milliseconds between two instants, floored at zero.
    ///
    /// A clock that has gone backwards — timezone travel, a corrected device clock, a restored
    /// backup — must never read as "a long time has passed", which would burn the prompt at the
    /// wrong moment. Negative elapsed time is therefore zero, which fails the cooldown and keeps
    /// the game quiet until the clock catches up with itself.
    public static func elapsedMillis(from start: Int64, to end: Int64) -> Int64 {
        end <= start ? 0 : end - start
    }
}

/// What armed the prompt (spec §17.2). Also the reason reported with the answer, so the four events
/// can be read by what earned them.
public enum LoveTrigger: String, Sendable, Hashable, CaseIterable {
    /// The cup won (§11).
    case cup
    /// The league won (§11).
    case league
    /// A win worth remembering: one goal, late — or one the player came back for.
    case hardFought
}

/// The remote kill switch (spec §17.4). It **defaults to on**: a backend outage can never disable a
/// working feature, only a deliberate flip can, so a failed fetch resolves to `on` and not to
/// `unread`. `unread` is the state before config has been read at all.
public enum LoveSwitch: String, Sendable, Hashable, CaseIterable {
    case unread, on, off
}

/// Everything `decide` is allowed to know: what just happened, and what the device remembers.
/// Grouped so a call site cannot pass arguments in the wrong order, and so a fact added later is
/// not a source break.
public struct LoveFacts: Sendable, Hashable {
    /// What armed the prompt, carried from the moment it happened to the settled screen where it is
    /// shown (§17.3). `nil` is the ordinary case: nothing earned it.
    public var armed: LoveTrigger?
    public var lastAskedAt: Int64?
    public var answeredPositively: Bool
    public var remote: LoveSwitch

    public init(armed: LoveTrigger?, lastAskedAt: Int64?, answeredPositively: Bool, remote: LoveSwitch) {
        self.armed = armed
        self.lastAskedAt = lastAskedAt
        self.answeredPositively = answeredPositively
        self.remote = remote
    }
}

/// What `decide` said, and why. Every verdict but `ask` is a reason the game stayed quiet; they are
/// distinguished so a vector pins *which* rule held, not merely that one did.
public enum LoveVerdict: String, Sendable, Hashable, CaseIterable {
    case ask
    /// A positive answer ended it, forever (§17.2).
    case saidYes
    case switchOff
    /// Config has not been read yet (§17.4).
    case switchUnread
    /// Nothing earned it.
    case notArmed
    /// Within the cooldown of the last showing (§17.2).
    case cooldown
}

/// A finished player match, as far as the love dialog is concerned (spec §17.2): its goals in the
/// order they were scored, and how long it lasted. Derived from `MatchEvent`s the flow already
/// emits — this adds no match state and never touches the simulation.
///
/// The margin, the comeback and the winning goal are computed **here**, from the goal tape, rather
/// than by each app: one rule, one place, two platforms, pinned by the corpus.
public struct LoveMatch: Sendable, Hashable {
    /// One goal: whose it was, and how far into the match it fell.
    public struct Goal: Sendable, Hashable {
        /// The player's team scored it (an own goal counts for whoever it benefits, as §8 scores it).
        public var mine: Bool
        /// Milliseconds of match time elapsed when it was scored — the whole match, not the period.
        public var atMillis: Int

        public init(mine: Bool, atMillis: Int) {
            self.mine = mine
            self.atMillis = atMillis
        }
    }

    public var goals: [Goal]
    /// The match's whole length in milliseconds, overtime included: periods × period length (§12).
    public var durationMillis: Int
    /// This match won the cup (§11.2) — the final, and the player took it.
    public var wonCup: Bool
    /// This match won the league (§11.1) — the last matchday, and the player finished top.
    public var wonLeague: Bool

    public init(goals: [Goal], durationMillis: Int, wonCup: Bool = false, wonLeague: Bool = false) {
        self.goals = goals
        self.durationMillis = durationMillis
        self.wonCup = wonCup
        self.wonLeague = wonLeague
    }

    public var goalsFor: Int { goals.filter(\.mine).count }
    public var goalsAgainst: Int { goals.count - goalsFor }
    public var won: Bool { goalsFor > goalsAgainst }

    /// The opponent led at some point. Read off the tape in order, so a match that was level all
    /// the way and won at the death does not count as a comeback.
    public var trailed: Bool {
        var mine = 0, theirs = 0
        for goal in goals {
            if goal.mine { mine += 1 } else { theirs += 1 }
            if theirs > mine { return true }
        }
        return false
    }

    /// The winner's `(loser's goals + 1)`-th goal — the one that gave them a lead they never gave
    /// back. `nil` when the player did not win, or when the tape is shorter than the score says.
    public var winningGoalMillis: Int? {
        guard won else { return nil }
        var mine = 0
        for goal in goals where goal.mine {
            mine += 1
            if mine == goalsAgainst + 1 { return goal.atMillis }
        }
        return nil
    }

    /// The winning goal fell in the final third: `3 × elapsed ≥ 2 × duration`, in integers, so both
    /// platforms agree on the boundary to the millisecond instead of to within a rounding.
    ///
    /// Widened to 64-bit for the multiplication alone. Swift's `Int` is 64-bit and Kotlin's is 32-bit,
    /// so at an absurd match length the two would disagree — one overflowing where the other does
    /// not is exactly the divergence the parity rule exists to forbid, and it costs nothing to close.
    public var winningGoalWasLate: Bool {
        guard durationMillis > 0, let at = winningGoalMillis else { return false }
        return 3 * Int64(at) >= 2 * Int64(durationMillis)
    }

    /// A win worth asking about (§17.2): by exactly one goal with the winning goal late, **or** won
    /// after having trailed at any point. A 6–0 stroll is not a story; neither is a draw.
    public var wasHardFought: Bool {
        guard won else { return false }
        return (goalsFor - goalsAgainst == 1 && winningGoalWasLate) || trailed
    }
}

extension LoveMatch {
    /// How far into the match the clock stood, in milliseconds, from what a snapshot holds: the
    /// period, the seconds left in it, and the period's length (§12). This is **match time, not wall
    /// time** — a face-off that took two seconds to drop is not two seconds of the match — which is
    /// what makes it comparable with `durationMillis` and with the final-third boundary (§17.2).
    ///
    /// Overtime reads as the whole match having run: a golden goal is by definition the last one, and
    /// it is late by any measure worth the name.
    public static func elapsedMillis(period: Int, remainingSeconds: Double, periodSeconds: Double,
                                     overtime: Bool, periods: Int = Tuning.Match.periods) -> Int {
        let whole = Int((Double(periods) * periodSeconds * 1000).rounded())
        guard !overtime else { return whole }
        let played = Double(max(period - 1, 0)) * periodSeconds + max(0, periodSeconds - remainingSeconds)
        return min(whole, max(0, Int((played * 1000).rounded())))
    }
}
