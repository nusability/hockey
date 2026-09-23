package `in`.nann.smashhockey.core.match

import `in`.nann.smashhockey.core.generated.Drill
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.LineupSpot
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Sport
import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Tactics
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.math.SplitMix64

/**
 * One match or training drill, simulated (spec §1–§8, §10).
 *
 * Pure: no clock, no randomness but its own SplitMix64 stream, no Android API — so the same setup
 * and the same input produce the same match to the bit here and on iOS (§4.3–§4.7).
 *
 * Drive it with [hold] (the finger) and [tick] (1/120 s of match time, two 1/240 s steps), or
 * [advance] to turn real time into ticks (§4.2). Read [snapshot] to draw and [drainEvents] for
 * what happened. Not thread-safe: one owner drives it.
 */
class Match private constructor(
    internal val sport: Sport,
    internal val control: Control,
    internal val drill: Drill?,
    internal val periodSeconds: Double,
    internal val cup: Boolean,
    orbitPeriod: Double,
    internal val tactics: List<Tactics>,
    ratings: List<Int>,
    internal val players: List<Athlete>,
    seed: Long,
) {
    /** A match (§8): rosters from the formations, the stream seeded, the first face-off at centre. */
    constructor(setup: MatchSetup) : this(
        setup.sport, setup.control, null, setup.periodSeconds, setup.cup, setup.orbitPeriod,
        listOf(setup.home.tactics, setup.away.tactics), listOf(setup.home.rating, setup.away.rating),
        matchRoster(setup), setup.seed,
    )

    /** A training drill (§10): its fixed lineups and ratings, the ball with the named player. */
    constructor(setup: DrillSetup) : this(
        setup.drill.world.sport, Control.PLAYER, setup.drill, setup.drill.seconds, false, setup.orbitPeriod,
        listOf(setup.tactics, Tactics.defaults.copy(pressing = Tuning.Training.opponentPressing)),
        drillRatings(setup.drill), drillRoster(setup.drill), setup.seed,
    )

    // Configuration
    /** Radians per second of every orbit (§5.1). */
    internal val omega: Double
    internal val skill: List<Double> = ratings.map { skill(it) }
    /** Each team's roster indices, in roster order (§3). */
    internal val rosters: List<List<Int>> = (0 until 2).map { team -> players.indices.filter { players[it].team == team } }

    // State
    internal val ball = Ball()
    internal val rng = SplitMix64.seeded(seed)
    var state = MatchState.FACE_OFF
        internal set
    internal var stateTimer = 0.0
    var clock: Double = periodSeconds
        internal set
    var period = 1
        internal set
    var overtime = false
        internal set
    internal val score = intArrayOf(0, 0)
    /** Match time (§4.1). */
    var time = 0.0
        internal set
    var ticks = 0
        internal set
    var result: MatchResult? = null
        internal set
    /** Seconds the ball has been loose in play (§7.1). */
    internal var looseTimer = 0.0

    /** Seconds the ball has been loose and slow in play (§6.5). */
    internal var deadTimer = 0.0

    /** Seconds each team is still on alert as the defending side (§7.9). */
    internal val alert = doubleArrayOf(0.0, 0.0)

    /**
     * How hard this match tilts back toward whoever is behind (§7.10). Drawn once, at set-up; a
     * drill has none. Presentation never shows it — it is exposed for the bench and the tests.
     */
    var temperament = 0.0
        internal set

    /**
     * Each team's tilt (§7.10): positive is *chase* — the side behind — negative is *hold*, the
     * side ahead, and both are zero at a level or a one-goal score. Recomputed each step in play.
     */
    internal val balance = doubleArrayOf(0.0, 0.0)

    /** The outfield carrier watched for a crossing of the centre line, and their z last step (§7.9). */
    internal var crossingCarrier: Int? = null
    internal var crossingZ = 0.0
    internal var restartSpot: Spot = Tuning.Pitch.faceoffCenter
    /** Set while a scored ball rolls on in the net: the net's goal line and its team's direction. */
    internal var netRoll: Pair<Double, Double>? = null
    internal val events = ArrayList<MatchEvent>()

    // Input
    private val pendingInput = ArrayList<Boolean>()
    var fingerDown = false
        private set
    private val realClock = TickClock()

    init {
        require(periodSeconds > 0 && orbitPeriod > 0) { "Match: period length and orbit period must be positive" }
        omega = Pitch.TWO_PI / orbitPeriod
        if (drill == null) drawTemperament()
        drawFirstThinks()
        if (drill == null) setUpFaceOff(Tuning.Pitch.faceoffCenter) else resetDrill()
    }

    /** The score, team 0 first. */
    val scores: List<Int> get() = score.toList()

    /**
     * Which team is defending on alert (§7.9) — the sharpened defence a carried ball opens by
     * crossing the centre line. Presentation may show it; it never changes a tick.
     */
    val alerted: List<Boolean> get() = listOf(alert[0] > 0, alert[1] > 0)

    /** The SplitMix64 stream's position — for the golden vectors (§4.7). */
    val streamState: Long get() = rng.state

    /** Each outfield player's first re-think falls at 0.2u, drawn in roster order (§7). */
    private fun drawFirstThinks() {
        for (p in players) if (p.isOutfield) p.thinkTimer = Tuning.AI.firstThinkSpread * rng.uniform()
    }

    /**
     * The match's temperament (§7.10), drawn once at set-up before the first re-thinks (§4.3). A
     * drill has none and draws nothing.
     */
    private fun drawTemperament() {
        val b = Tuning.AI.Balance
        temperament = Pitch.clamp(b.temperamentBase + rng.noise(b.temperamentNoise), 0.0, b.temperamentMax)
    }

    // Input and time

    /**
     * The finger: `true` on touch-down, `false` when the last finger lifts. Applied at the next tick
     * boundary, in order, so a tap shorter than a tick still releases (§4.1, §5.3).
     */
    fun hold(down: Boolean) {
        pendingInput.add(down)
    }

    /** One tick: the input since the last tick, then two steps (§4.1). */
    fun tick() {
        for (down in pendingInput) {
            if (down) {
                fingerDown = true
            } else if (fingerDown) {
                fingerDown = false
                playerLift()
            }
        }
        pendingInput.clear()
        repeat(Tuning.Time.stepsPerTick) { step() }
        ticks += 1
    }

    /**
     * Runs the ticks [realSeconds] of real time at [timeScale] amount to (§4.2): the gap is clamped
     * to 0.1 s and the remainder carries to the next call. Returns the ticks run.
     */
    fun advance(realSeconds: Double, timeScale: Double): Int {
        val n = realClock.ticks(realSeconds, timeScale)
        repeat(n) { tick() }
        return n
    }

    /** Everything emitted since the last drain, in order. */
    fun drainEvents(): List<MatchEvent> {
        val out = events.toList()
        events.clear()
        return out
    }

    // The step (§4.5)

    private fun step() {
        val dt = Tuning.Time.stepSeconds
        time += dt                                            // 1
        advanceStateMachine(dt)                               // 2
        val live = state == MatchState.PLAY
        if (live) runClock(dt)                                // 3
        if (live) {                                           // 4
            updateBalance()
            updateAlert(dt)
            if (ball.carrier != null) looseTimer = 0.0 else looseTimer += dt
            thinkTeam(0, dt)
            thinkTeam(1, dt)
        }
        movePlayers(dt, live)                                 // 5
        resolveContacts()                                     // 6
        constrainPlayers()
        if (live) moveLiveBall(dt) else moveIdleBall(dt)      // 7
        if (live) checkDeadBall(dt)                           // 8
    }

    internal fun emit(event: MatchEvent) {
        events.add(event)
    }

    // Roster queries

    /** Team [team]'s outfield players (defenders and forwards), in roster order. */
    internal fun outfield(team: Int): List<Int> = rosters[team].filter { players[it].isOutfield }

    internal fun goalieOf(team: Int): Int? = rosters[team].firstOrNull { players[it].isGoalie }

    /** The roster index nearest [point] among [candidates] (the first on a tie), with its distance. */
    internal fun nearest(point: Vec, candidates: List<Int>): Nearest? {
        var best: Nearest? = null
        for (j in candidates) {
            val d = Pitch.distance(players[j].pos, point)
            if (best == null || d < best.distance) best = Nearest(j, d)
        }
        return best
    }

    /** Whether team 0's outfield releases wait for the player's finger (§5.3). */
    internal fun isPlayerControlled(i: Int): Boolean =
        control == Control.PLAYER && players[i].team == 0 && !players[i].isGoalie

    internal data class Nearest(val index: Int, val distance: Double)

    companion object {
        /** `skill = clamp((rating − 60) / 30, 0, 1)` (§2.1). */
        internal fun skill(rating: Int): Double =
            Pitch.clamp((rating.toDouble() - Tuning.Player.ratingOrigin) / Tuning.Player.skillSpan, 0.0, 1.0)

        private fun matchRoster(setup: MatchSetup): List<Athlete> {
            val out = ArrayList<Athlete>()
            for ((team, side) in listOf(setup.home, setup.away).withIndex()) {
                val lineup = listOf(LineupSpot(Role.GOALIE, Formation.goalie)) + side.formation.players
                for ((slot, spot) in lineup.withIndex()) {
                    val home = if (team == 0) Vec(spot.spot.x, spot.spot.z) else Vec(-spot.spot.x, -spot.spot.z)
                    out.add(Athlete(team, slot, spot.role, home, 1.0, side.rating, null))
                }
            }
            return out
        }

        private fun drillRatings(drill: Drill): List<Int> {
            val real = drill.away.any { it.role == Role.DEFENDER || it.role == Role.FORWARD }
            return listOf(
                Tuning.Training.playerRating,
                if (real) Tuning.Training.opponentRatingOutfield else Tuning.Training.opponentRating,
            )
        }

        private fun drillRoster(drill: Drill): List<Athlete> {
            val ratings = drillRatings(drill)
            val out = ArrayList<Athlete>()
            for ((team, lineup) in listOf(drill.home, drill.away).withIndex()) {
                for ((slot, p) in lineup.withIndex()) {
                    out.add(Athlete(team, slot, p.role, Vec(p.spot.x, p.spot.z), p.speed, ratings[team], p.patrol))
                }
            }
            return out
        }
    }
}
