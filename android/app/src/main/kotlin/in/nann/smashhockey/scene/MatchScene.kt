package `in`.nann.smashhockey.scene

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Typeface
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceView
import com.google.android.filament.Camera
import com.google.android.filament.ColorGrading
import com.google.android.filament.EntityManager
import com.google.android.filament.ToneMapper
import com.google.android.filament.View
import `in`.nann.smashhockey.R
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.DrillInterruption
import `in`.nann.smashhockey.core.match.Match
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.core.match.MatchState
import `in`.nann.smashhockey.core.match.lastShotDistance
import `in`.nann.smashhockey.core.match.shotAboutToScore
import `in`.nann.smashhockey.core.match.snapshot
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.FilamentHost
import `in`.nann.smashhockey.engine.FrameStats
import `in`.nann.smashhockey.engine.InputLatency
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.MotionTokens
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.engine.World
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.spike.ScreenRect
import kotlin.math.tan

/**
 * The match on screen (SMASH-8, SMASH-9) — the twin of iOS's MatchScene: a `Match` from the core,
 * drawn in its world, with the camera and slow motion of §8.6, the finger of §5.3 and a minimal HUD.
 * One Filament scene, one camera, one clock — the Choreographer callback (ADR 0005).
 */
class MatchScene(
    private val context: Context,
    surfaceView: SurfaceView,
    private var plan: MatchPlan,
    private var seed: Long,
    private val onPauseRect: (ScreenRect?, Boolean) -> Unit,
) {
    private val host = FilamentHost(surfaceView, ::frame)
    private val engine = host.engine
    private val assets = Assets(context.assets)
    private val motion = MotionTokens.load(assets)
    private val stats = FrameStats(context)
    private val latency = InputLatency()
    private val typeface = Typeface.createFromAsset(context.assets, "fonts/LilitaOne-Regular.ttf")
    private val materials = Materials(engine, assets)
    var reduceMotion = !ValueAnimator.areAnimatorsEnabled()

    /** The world and everything in it: what the camera shake moves. The HUD hangs from the camera. */
    private val worldRoot = Node(engine)
    private var match: Match
    private var snapshot: MatchSnapshot
    private var orbitPeriod: Double
    private var world: World? = null
    private var actors: Actors? = null
    private var confetti: Confetti? = null
    private var hud: Hud? = null
    private var director = Director()

    private var aspect = 0.46
    private var width = 1; private var height = 1; private var safeTop = 0
    private var phase = 0.0
    private var clock = 0.0
    private var celebrating: Int? = null
    private var endedFor = 0.0
    var paused = false; private set
    private val onPitch = HashSet<Int>()
    private var lastRect: ScreenRect? = null
    private var fov = Presentation.Camera.Play.maxFov

    init {
        host.view.colorGrading = ColorGrading.Builder().toneMapper(ToneMapper.Linear()).build(engine)
        host.view.dynamicResolutionOptions = View.DynamicResolutionOptions().apply { enabled = true; minScale = 0.6f }
        host.camera.setExposure(16f, 1f / 125f, 100f)
        host.onResize = { w, h ->
            width = w; height = h; aspect = w.toDouble() / h; director.aspect = aspect
            projection(); hud?.resize(w, h, safeTop)
        }
        val (m, o) = plan.start(seed)
        match = m; orbitPeriod = o
        snapshot = match.snapshot
        build()
    }

    private val drillGoals: Int? get() = (plan as? MatchPlan.Practice)?.drill?.goals

    /** Builds the plan's world and everything in it (the world only when it changes). */
    private fun build() {
        val w = world?.takeIf { it.id == plan.world } ?: run {
            world?.destroy()
            World(engine, host.scene, assets, plan.world).also {
                val tm = engine.transformManager
                tm.setParent(tm.getInstance(it.root), tm.getInstance(worldRoot.entity))
            }
        }
        world = w
        actors?.destroy(); confetti?.destroy(); hud?.destroy()
        actors = Actors(engine, host.scene, worldRoot.entity, snapshot, plan.colours(seed), plan.world.sport, orbitPeriod, materials, w.look)
        confetti = Confetti(engine, host.scene, worldRoot.entity, materials, w.look)
        hud = Hud(engine, host.scene, host.camera.entity, materials, w.look, typeface, motion, plan.codes(seed), plan.colours(seed)).also {
            it.resize(width, height, safeTop)
            it.show(snapshot, drillGoals)
        }
        Log.i(TAG, "world ${plan.world.key} seed $seed")
    }

    fun setSafeTop(px: Int) { safeTop = px; hud?.resize(width, height, px) }

    fun start() = host.start()
    fun stop() = host.stop()

    // ---------------------------------------------------------------- the frame — the one clock

    private fun frame(dt: Double, @Suppress("UNUSED_PARAMETER") frameTimeNanos: Long) {
        stats.record(dt)
        val real = dt.coerceIn(0.0, Tuning.Time.maxRealGap)
        clock += real
        val hud = hud ?: return
        if (!paused) {
            director.reduceMotion = reduceMotion
            director.update(real, directorInput())
            val scale = director.timeScale
            val ran = match.advance(dt, scale)
            phase = (phase + real * scale / Tuning.Time.tickSeconds - ran).coerceIn(0.0, 0.999)
            if (ran > 0) {
                latency.ticked()
                snapshot = match.snapshot
                for (e in match.drainEvents()) handle(e)
                hud.show(snapshot, drillGoals)
            }
        }
        if (snapshot.state != MatchState.GOAL) celebrating = null
        actors?.update(snapshot, if (paused) 0.0 else phase * Tuning.Time.tickSeconds, celebrating, clock)
        confetti?.advance(real)
        hud.advance(real, 1.6)
        val pose = director.pose
        host.camera.lookAt(pose.eye[0], pose.eye[1], pose.eye[2], pose.target[0], pose.target[1], pose.target[2], 0.0, 1.0, 0.0)
        if (pose.fov != fov) { fov = pose.fov; projection() }
        val shake = director.shakeOffset
        worldRoot.x = -shake[0].toFloat(); worldRoot.y = -shake[1].toFloat(); worldRoot.z = -shake[2].toFloat(); worldRoot.apply()
        // The HUD keeps its size on screen while the field of view breathes: across only, not in depth.
        hud.zoom = (tan(Math.toRadians(fov / 2)) / tan(Math.toRadians(Presentation.Camera.hudFov / 2))).toFloat()
        hud.layout()
        project()
        afterTheEnd(real)
    }

    private fun projection() =
        host.camera.setProjection(fov, aspect, Presentation.Camera.near, Presentation.Camera.far, Camera.Fov.VERTICAL)

    private fun directorInput(): DirectorInput {
        val b = snapshot.ball
        return DirectorInput(match.state, match.shotAboutToScore, match.lastShotDistance, b.x, b.z, b.vx, b.vz,
            b.carrier?.let { snapshot.players[it].team })
    }

    private fun handle(e: MatchEvent) {
        when (e) {
            is MatchEvent.Goal -> {
                val goalZ = (if (e.team == 0) 1.0 else -1.0) * Tuning.Pitch.goalLineZ
                director.goalScored(goalZ, snapshot.ball.x, match.lastShotDistance)
                confetti?.burst(goalZ.toFloat())
                celebrating = e.team
                val ours = e.team == 0
                banner(if (ours) R.string.event_goal else R.string.event_goalAgainst, if (ours) Presentation.Aim.shot else Presentation.Hud.text)
                Log.i(TAG, "goal team ${e.team} own ${e.ownGoal} score ${snapshot.score[0]}-${snapshot.score[1]}")
            }
            MatchEvent.Post -> director.knock(Presentation.Camera.Shake.post)
            is MatchEvent.Board -> director.knock(Presentation.Camera.Shake.board * minOf(e.speed / 12, 1.0))
            is MatchEvent.DrillInterrupted -> banner(when (e.reason) {
                DrillInterruption.SAVED -> R.string.event_saved
                DrillInterruption.STOLEN -> R.string.event_stolen
                DrillInterruption.WRONG_NET -> R.string.event_wrongNet
                DrillInterruption.NO_ASSIST -> R.string.event_passFirst
                DrillInterruption.DEAD_BALL -> R.string.event_reset
            }, Presentation.Hud.clock)
            is MatchEvent.End -> {
                banner(when (e.result) {
                    MatchResult.WON -> R.string.result_win
                    MatchResult.LOST -> R.string.result_loss
                    MatchResult.DRAWN -> R.string.result_draw
                }, Presentation.Hud.clock)
                Log.i(TAG, "end ${e.result.key}")
            }
            is MatchEvent.Shot -> Log.i(TAG, "shot by ${e.by} ${e.kind.key}")
            else -> Unit
        }
    }

    private fun banner(res: Int, rgb: Int) = hud?.raise(context.getString(res), rgb, reduceMotion)

    private fun afterTheEnd(dt: Double) {
        if (snapshot.state != MatchState.ENDED) { endedFor = 0.0; return }
        endedFor += dt
        val p = plan
        if (p is MatchPlan.Demo && endedFor > 4) restart(MatchPlan.Demo(p.round + 1))
    }

    /** The next match or the retry — one tap, no interstitial (principle A2). */
    private fun restart(next: MatchPlan) {
        plan = next
        seed = MatchPlan.seed(null)
        val (m, o) = next.start(seed)
        match = m; orbitPeriod = o
        snapshot = match.snapshot
        director = Director().also { it.aspect = aspect }
        phase = 0.0; endedFor = 0.0
        build()
    }

    // ---------------------------------------------------------------- the finger (§5.3)

    /**
     * Every finger on the surface: the first one down on the pitch holds, the last one up
     * releases, any number of fingers. A touch on a HUD control belongs to the UI.
     */
    fun onTouch(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                if (!touchIsUi(e.getX(i), e.getY(i))) {
                    val first = onPitch.isEmpty()
                    onPitch += e.getPointerId(i)
                    if (first) finger(true, e.eventTime)
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> lift(e.getPointerId(e.actionIndex), e.eventTime)
            MotionEvent.ACTION_CANCEL -> for (i in 0 until e.pointerCount) lift(e.getPointerId(i), e.eventTime)
        }
        return true
    }

    private fun lift(id: Int, time: Long) {
        if (onPitch.remove(id) && onPitch.isEmpty()) finger(false, time)
    }

    /** Handed to the match at once; it applies at the next tick boundary (§4.1). */
    private fun finger(down: Boolean, eventTimeMs: Long) {
        match.hold(down)
        latency.edge(down, eventTimeMs)
        if (!down) Log.i(TAG, "lift aim ${snapshot.aim}")
    }

    private fun touchIsUi(px: Float, py: Float): Boolean {
        val hud = hud ?: return false
        val (origin, dir) = ray(px, py)
        if (hud.pauseButton.hit(origin, dir) != null) { togglePause(); return true }
        if (paused) return true
        if (snapshot.state == MatchState.ENDED && plan !is MatchPlan.Demo) { restart(plan); return true }
        return false
    }

    fun togglePause() = setPaused(!paused)

    /** Pause (the button, or the app leaving the foreground, §8.7): the match stops, the UI doesn't. */
    fun setPaused(on: Boolean) {
        if (paused == on) return
        paused = on
        hud?.setPaused(on, context.getString(R.string.pause_title))
        lastRect = null
    }

    // ---------------------------------------------------------------- hit-testing and projection

    private fun ray(px: Float, py: Float): Pair<FloatArray, FloatArray> {
        val ndcX = 2.0 * px / width - 1.0
        val ndcY = 1.0 - 2.0 * py / height
        val t = tan(Math.toRadians(fov / 2))
        val dv = doubleArrayOf(ndcX * t * aspect, ndcY * t, -1.0)
        val m = DoubleArray(16).also { host.camera.getModelMatrix(it) }
        val dir = FloatArray(3) { i -> (m[i] * dv[0] + m[4 + i] * dv[1] + m[8 + i] * dv[2]).toFloat() }
        return floatArrayOf(m[12].toFloat(), m[13].toFloat(), m[14].toFloat()) to dir
    }

    private fun project() {
        val button = hud?.pauseButton ?: return
        val view = DoubleArray(16).also { host.camera.getViewMatrix(it) }
        val proj = DoubleArray(16).also { host.camera.getProjectionMatrix(it) }
        var l = Float.MAX_VALUE; var t = Float.MAX_VALUE; var r = -Float.MAX_VALUE; var b = -Float.MAX_VALUE
        for (p in button.worldCorners()) {
            val v = mul(view, doubleArrayOf(p[0].toDouble(), p[1].toDouble(), p[2].toDouble(), 1.0)); val c = mul(proj, v)
            if (c[3] <= 0) continue
            val sx = ((c[0] / c[3] + 1) / 2 * width).toFloat(); val sy = ((1 - c[1] / c[3]) / 2 * height).toFloat()
            l = minOf(l, sx); r = maxOf(r, sx); t = minOf(t, sy); b = maxOf(b, sy)
        }
        val rect = if (l < r) ScreenRect(l.toInt(), t.toInt(), r.toInt(), b.toInt()) else null
        if (rect != lastRect) { lastRect = rect; onPauseRect(rect, paused) }
    }

    private fun mul(m: DoubleArray, p: DoubleArray) = DoubleArray(4) { i -> m[i] * p[0] + m[4 + i] * p[1] + m[8 + i] * p[2] + m[12 + i] * p[3] }

    fun destroy() {
        host.stop()
        actors?.destroy(); confetti?.destroy(); hud?.destroy(); world?.destroy()
        materials.destroy()
        engine.destroyEntity(worldRoot.entity); EntityManager.get().destroy(worldRoot.entity)
        host.destroy()
    }

    companion object { const val TAG = "SmashMatch" }
}
