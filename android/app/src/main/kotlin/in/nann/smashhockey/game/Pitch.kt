package `in`.nann.smashhockey.game

import android.content.Context
import android.util.Log
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.Match
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.core.match.lastShotDistance
import `in`.nann.smashhockey.core.feel.Atmosphere
import `in`.nann.smashhockey.core.match.shotAboutToScore
import `in`.nann.smashhockey.core.match.snapshot
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.FrameStats
import `in`.nann.smashhockey.engine.InputLatency
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.engine.World
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.scene.Actors
import `in`.nann.smashhockey.core.feel.Cue
import `in`.nann.smashhockey.core.feel.MatchCues
import `in`.nann.smashhockey.scene.Confetti
import `in`.nann.smashhockey.scene.NetRipple
import `in`.nann.smashhockey.scene.Pops
import `in`.nann.smashhockey.scene.Director
import `in`.nann.smashhockey.scene.DirectorInput
import `in`.nann.smashhockey.ui.CameraPose
import `in`.nann.smashhockey.core.generated.World as WorldId

/**
 * The pitch and whatever match is on it (spec §8, §9) — the twin of iOS's Pitch.swift: a `Match`
 * from the core, drawn in its world — the players, the ball, the aim arrow, the confetti, the pops and
 * the rippling nets — with the
 * director's camera and slow motion (§8.6). The demo behind the menus and the player's own matches
 * are the same thing here; the game decides which one runs. It never draws a HUD: the screens do.
 *
 * A world loads synchronously on the main thread (Filament's gltfio), between two frames.
 */
class Pitch(context: Context, private val engine: Engine, private val scene: Scene, private val assets: Assets) {
    /** The world and everything in it: what the camera shake moves. */
    private val root = Node(engine)
    private val materials = Materials(engine, assets)
    private val stats = FrameStats(context)
    private val latency = InputLatency()
    var reduceMotion = false
    /** The view's width over its height, for the play camera's fit. */
    var aspect = 0.46
        set(v) { field = v; director.aspect = v }
    /** A paused match stops; the camera and the UI don't (§8.7). */
    var paused = false
    /** What the match emitted this frame, after the pitch itself has reacted. */
    var onEvent: ((MatchEvent) -> Unit)? = null
    /** What the match sets off that the pitch does not draw itself: banners, sounds, haptics (§8.8). */
    var onCue: ((Cue) -> Unit)? = null

    var plan: MatchPlan? = null; private set
    var kickoff: Kickoff? = null; private set
    var snapshot: MatchSnapshot? = null; private set
    /** Real seconds since the match ended; 0 while it runs. */
    var endedFor = 0.0; private set
    private var match: Match? = null
    private var world: World? = null
    private var actors: Actors? = null
    private var confetti: Confetti? = null
    private val pops = Pops(engine, scene, root.entity, materials)
    private val nets = NetRipple(engine, scene, root.entity, materials)
    private var cues: MatchCues? = null
    private var director = Director()
    private var phase = 0.0
    private var clock = 0.0
    private var celebrating: Int? = null

    /** The world standing now. */
    val worldShown: WorldId? get() = world?.id

    /** Puts [kickoff] on the pitch, in its world (loaded now if another one stands). */
    fun start(plan: MatchPlan, kickoff: Kickoff) {
        val w = world?.takeIf { it.id == kickoff.world } ?: run {
            world?.destroy()
            World(engine, scene, assets, kickoff.world).also {
                val tm = engine.transformManager
                tm.setParent(tm.getInstance(it.root), tm.getInstance(root.entity))
            }
        }
        world = w
        actors?.destroy(); confetti?.destroy()
        val first = kickoff.match.snapshot
        actors = Actors(engine, scene, root.entity, first, kickoff.colours, kickoff.world.sport, kickoff.orbitPeriod, materials, w.look)
        confetti = Confetti(engine, scene, root.entity, materials, w.look, kickoff.colours)
        cues = MatchCues(Feel.params, drill = plan is MatchPlan.Practice, audible = !plan.isDemo)
        this.plan = plan
        this.kickoff = kickoff
        match = kickoff.match
        snapshot = first
        director = Director().also { it.aspect = aspect }
        phase = 0.0; endedFor = 0.0; celebrating = null; paused = false
        Log.i(TAG, "kickoff $plan in ${kickoff.world.key}")
    }

    // ---------------------------------------------------------------- the frame

    fun update(dt: Double) {
        stats.record(dt)
        val real = dt.coerceIn(0.0, Tuning.Time.maxRealGap)
        clock += real
        val m = match ?: return
        var s = snapshot ?: return
        if (!paused) {
            director.reduceMotion = reduceMotion
            director.update(real, input(m, s))
            val scale = director.timeScale
            val ran = m.advance(dt, scale)
            phase = (phase + real * scale / Tuning.Time.tickSeconds - ran).coerceIn(0.0, 0.999)
            if (ran > 0) {
                latency.ticked()
                s = m.snapshot
                snapshot = s
                for (e in m.drainEvents()) handle(e, m, s)
                cues?.frame(s)?.forEach(::cue)
            }
        }
        if (s.state != MatchState.GOAL) celebrating = null
        actors?.update(s, if (paused) 0.0 else phase * Tuning.Time.tickSeconds, celebrating, clock)
        confetti?.advance(real)
        pops.advance(real)
        nets.advance(real, reduceMotion)
        val shake = director.shakeOffset
        root.x = -shake[0].toFloat(); root.y = -shake[1].toFloat(); root.z = -shake[2].toFloat(); root.apply()
        if (s.state == MatchState.ENDED) endedFor += real else endedFor = 0.0
    }

    /** The director's camera: its pose and vertical field of view. */
    val pose: Pair<CameraPose, Double>
        get() {
            val p = director.pose
            return CameraPose(p.eye[0].toFloat(), p.eye[1].toFloat(), p.eye[2].toFloat(),
                p.target[0].toFloat(), p.target[1].toFloat(), p.target[2].toFloat()) to p.fov
        }

    private fun input(m: Match, s: MatchSnapshot): DirectorInput {
        val b = s.ball
        return DirectorInput(m.state, m.shotAboutToScore, m.lastShotDistance, b.x, b.z, b.vx, b.vz,
            b.carrier?.let { s.players[it].team })
    }

    /** §8.6's time scale now — what the match's sounds play at (§8.8); 0 while paused. */
    val timeScale: Double get() = if (paused || match == null) 0.0 else director.timeScale

    /**
     * What the stadium reads this frame (§8.8): the player's match as it stands, and which goal a
     * shot about to score (§8.6) is heading for. Null behind the menus — the demo has no crowd (§9).
     */
    val atmosphere: Pair<MatchSnapshot, Atmosphere.Danger?>?
        get() {
            val m = match ?: return null
            val s = snapshot ?: return null
            if (plan?.isDemo != false) return null
            val danger = if (m.shotAboutToScore) {
                if (s.ball.vz > 0) Atmosphere.Danger.THEIRS else Atmosphere.Danger.OURS
            } else {
                null
            }
            return s to danger
        }

    /** A player's match (not a drill) opens with "Home vs Away" (§16.4). */
    fun intro(home: String, away: String) { cues?.intro(home, away)?.forEach(::cue) }

    /** The pitch draws the shakes and pops itself; the rest goes to the game. */
    private fun cue(c: Cue) {
        when (c) {
            is Cue.Shake -> director.knock(c.metres)
            is Cue.Pop -> pops.pop(c.kind, c.x, c.z)
            else -> onCue?.invoke(c)
        }
    }

    /** The camera, the confetti and the celebration react; then the game hears of it. */
    private fun handle(e: MatchEvent, m: Match, s: MatchSnapshot) {
        when (e) {
            is MatchEvent.Goal -> {
                val goalZ = (if (e.team == 0) 1.0 else -1.0) * Tuning.Pitch.goalLineZ
                director.goalScored(goalZ, s.ball.x, m.lastShotDistance)
                confetti?.burst(goalZ.toFloat(), e.team)
                nets.ripple(goalZ, s.ball.x)
                celebrating = e.team
                Log.i(TAG, "goal team ${e.team} own ${e.ownGoal} score ${s.score[0]}-${s.score[1]}")
            }
            is MatchEvent.End -> Log.i(TAG, "end ${e.result.key}")
            else -> Unit
        }
        cues?.hear(e, s)?.forEach(::cue)
        onEvent?.invoke(e)
    }

    // ---------------------------------------------------------------- the finger (§5.3)

    /** Handed to the match at once; it applies at the next tick boundary (§4.1). */
    fun hold(down: Boolean, eventTimeMs: Long) {
        val m = match ?: return
        m.hold(down)
        latency.edge(down, eventTimeMs)
    }

    fun destroy() {
        actors?.destroy(); confetti?.destroy(); world?.destroy(); pops.destroy(); nets.destroy()
        materials.destroy()
        engine.destroyEntity(root.entity); EntityManager.get().destroy(root.entity)
    }

    companion object { const val TAG = "SmashMatch" }
}
