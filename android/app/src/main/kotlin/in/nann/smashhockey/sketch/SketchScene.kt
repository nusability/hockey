package `in`.nann.smashhockey.sketch

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Typeface
import android.util.Log
import android.view.MotionEvent
import android.view.SurfaceView
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.google.android.filament.Camera
import com.google.android.filament.ColorGrading
import com.google.android.filament.ToneMapper
import com.google.android.filament.View
import `in`.nann.smashhockey.core.generated.World as WorldId
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.FilamentHost
import `in`.nann.smashhockey.engine.FrameStats
import `in`.nann.smashhockey.engine.World
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.CameraPose
import `in`.nann.smashhockey.ui.Kit
import `in`.nann.smashhockey.ui.Motion
import `in`.nann.smashhockey.ui.Slider3D
import `in`.nann.smashhockey.ui.UIStage

/**
 * THROWAWAY (SMASH-5): the clickable motion sketch — the twin of iOS's SketchScene: Title → Season
 * hub → Match HUD → Result, and the coach's board — over the Oasis world, built only from the UI
 * kit, for the owner to judge the 3D UI's feel on a phone (AGENTS: "Click-dummy new UI first").
 * Every transition is a camera swoop with things tumbling out and in; nothing cuts.
 *
 * The screens are laid out from the surface's size and the safe area, so they are built on the
 * first frame that knows both.
 */
class SketchScene(
    context: Context,
    private val surfaceView: SurfaceView,
    private val autoplay: Boolean,
    private val forceReduceMotion: Boolean,
) {
    private val host = FilamentHost(surfaceView, ::frame)
    private val engine = host.engine
    private val assets = Assets(context.assets)
    private val stats = FrameStats(context)
    private val kit = Kit(engine, host.scene, assets, Typeface.createFromAsset(context.assets, "fonts/LilitaOne-Regular.ttf"),
        Motion.load(assets))
    private val world = World(engine, host.scene, host.view, assets, WorldId.OASIS)
    private val copy = Copy { context.getString(it) }
    private val stageState = mutableStateOf<UIStage?>(null)
    /** The stage, once built — the semantics overlay reads it. */
    val stage: State<UIStage?> get() = stageState

    private val screens = HashMap<SketchScreenId, SketchScreen>()
    private var current: SketchScreenId? = null
    private lateinit var title: TitleScreen
    private lateinit var hub: HubScreen
    private lateinit var match: SketchMatchScreen
    private lateinit var result: ResultScreen
    private lateinit var coach: CoachScreen
    private var width = 0
    private var height = 0
    private var touching = false

    init {
        host.view.colorGrading = ColorGrading.Builder().toneMapper(ToneMapper.Linear()).build(engine)
        host.view.dynamicResolutionOptions = View.DynamicResolutionOptions().apply { enabled = true; minScale = 0.6f }
        host.camera.setExposure(16f, 1f / 125f, 100f)
        host.onResize = { w, h ->
            width = w; height = h
            host.camera.setProjection(FOV, w.toDouble() / h, 0.1, 500.0, Camera.Fov.VERTICAL)
            stageState.value?.resize(w, h)
        }
    }

    private fun build() {
        val insets = ViewCompat.getRootWindowInsets(surfaceView)
            ?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
        val start = CameraPose(0f, 30f, -70f, 0f, 4f, 0f)
        val stage = UIStage(kit, host.camera, host.camera.entity, start, width, height, insets?.top ?: 0, insets?.bottom ?: 0)
        stage.reduceMotion = reduceMotion()
        val go: Go = { go(it) }
        title = TitleScreen(stage, copy, go)
        hub = HubScreen(stage, copy, go)
        match = SketchMatchScreen(stage, copy, kit.node(null), go)
        result = ResultScreen(stage, copy, go)
        coach = CoachScreen(stage, copy, go)
        screens.putAll(listOf(SketchScreenId.TITLE to title, SketchScreenId.HUB to hub, SketchScreenId.MATCH to match,
            SketchScreenId.RESULT to result, SketchScreenId.COACH to coach))
        match.onFinished = { home, away ->
            result.setScore(home, away)
            hub.applyMatchday()
            go(SketchScreenId.RESULT)
        }
        stageState.value = stage
        go(SketchScreenId.TITLE)
        if (autoplay) startAutoplay(stage)
    }

    /** Reduce Motion: the system's animator duration scale at 0, or `--ez sketchReduceMotion true`. */
    private fun reduceMotion() = forceReduceMotion || !ValueAnimator.areAnimatorsEnabled()

    /**
     * The one way between screens: the old one's parts hop away, the camera swoops, the new one's
     * parts tumble in as it arrives.
     */
    fun go(id: SketchScreenId) {
        val stage = stageState.value ?: return
        if (id == current) return
        val next = screens[id] ?: return
        Log.i(TAG, "screen ${id.name.lowercase()} t=${"%.2f".format(stage.time)}")
        current?.let { screens[it]?.hide() }
        val first = current == null
        current = id
        stage.rig.swoop(next.pose, roll = if (first) 0f else 0.12f)
        next.show(if (first) 0.9 else 0.45)
    }

    fun start() = host.start()
    fun stop() = host.stop()

    /** The one clock (ADR 0005): the Choreographer frame. */
    private fun frame(dt: Double, @Suppress("UNUSED_PARAMETER") frameTimeNanos: Long) {
        stats.record(dt)
        if (stageState.value == null) {
            if (width <= 1 || height <= 1) return
            build()
        }
        val stage = stageState.value ?: return
        val step = minOf(dt, 0.1)
        stage.reduceMotion = reduceMotion()
        current?.let { screens[it]?.update(step) }
        stage.update(step)
    }

    /** Fingers reach the stage's own hit-test: the first finger only, like iOS's drag gesture. */
    fun onTouch(e: MotionEvent): Boolean {
        val stage = stageState.value ?: return true
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> { touching = true; stage.touchDown(e.x, e.y) }
            MotionEvent.ACTION_MOVE -> if (touching) stage.touchMoved(e.x, e.y)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (touching) { touching = false; stage.touchUp(e.x, e.y) }
        }
        return true
    }

    // ------------------------------------------------------------------ autoplay (--ez sketchAutoplay true)

    /**
     * Walks the whole sketch on a timer, through the same actions a finger fires — the same
     * schedule as iOS's `-sketchAutoplay`.
     */
    private fun startAutoplay(stage: UIStage) {
        val steps: List<Pair<Double, () -> Unit>> = listOf(
            4.0 to { tap(stage, title.training) },
            5.0 to { tap(stage, title.play) },
            10.0 to { tap(stage, hub.playMatch) },
            19.0 to { tap(stage, match.pause) },
            22.0 to { tap(stage, match.resume) },
            // the match finishes on its own (~45 s) and swoops to the result
            52.0 to { tap(stage, result.next) },
            58.0 to { tap(stage, hub.back) },
            62.0 to { tap(stage, title.coach) },
            65.0 to { drag(stage, coach.sliders[0], 0.85) },
            66.0 to { drag(stage, coach.sliders[1], 0.2) },
            67.0 to { drag(stage, coach.sliders[2], 0.7) },
            69.0 to { tap(stage, coach.back) },
        )
        for ((t, run) in steps) stage.after(t, run)
    }

    /**
     * A pretend finger on the button's projected rectangle: the overlay's frame, fed back through
     * the stage's own ray hit-test — so autoplay proves projection and picking agree.
     */
    private fun tap(stage: UIStage, b: BlockButton) {
        val r = stage.rect(b.semantics.id) ?: run { Log.e(TAG, "autoplay: ${b.semantics.id} is not on screen"); return }
        val x = (r.left + r.right) / 2f; val y = (r.top + r.bottom) / 2f
        stage.touchDown(x, y)
        stage.after(0.14) { stage.touchUp(x, y) }
    }

    /** A pretend drag along a slider, from its value to [value], in eight moves. */
    private fun drag(stage: UIStage, s: Slider3D, value: Double) {
        val r = stage.rect(s.semantics.id) ?: run { Log.e(TAG, "autoplay: ${s.semantics.id} is not on screen"); return }
        val w = (r.right - r.left).toFloat()
        // The rail spans the node's box minus 0.1 m of grab room each side (Slider3D.bounds).
        val pad = w * 0.1f / (s.length + 0.2f)
        fun x(v: Double) = r.left + pad + (w - 2 * pad) * v.toFloat()
        val y = (r.top + r.bottom) / 2f + (r.bottom - r.top) * 0.2f
        stage.touchDown(x(s.value), y)
        val from = s.value
        for (i in 1..8) {
            val v = from + (value - from) * i / 8
            stage.after(i * 0.05) { stage.touchMoved(x(v), y) }
        }
        stage.after(0.5) { stage.touchUp(x(value), y) }
    }

    fun destroy() {
        host.stop()
        kit.destroy()
        world.destroy()
        host.destroy()
    }

    companion object {
        const val TAG = "SmashSketch"
        private const val FOV = 50.0
    }
}
