package `in`.nann.smashhockey.game

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
import `in`.nann.smashhockey.core.generated.BoardRecord
import `in`.nann.smashhockey.core.generated.SaveRecord
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.audio.Haptics
import `in`.nann.smashhockey.audio.Beds
import `in`.nann.smashhockey.audio.Sfx
import `in`.nann.smashhockey.core.feel.Atmosphere
import `in`.nann.smashhockey.core.feel.Cue
import `in`.nann.smashhockey.core.match.MatchEvent
import `in`.nann.smashhockey.core.match.MatchResult
import `in`.nann.smashhockey.core.season.GameException
import `in`.nann.smashhockey.core.season.SaveStore
import `in`.nann.smashhockey.core.season.TableRow
import `in`.nann.smashhockey.core.season.forfeit
import `in`.nann.smashhockey.core.season.fresh
import `in`.nann.smashhockey.core.season.recordPlayed
import `in`.nann.smashhockey.core.season.table
import `in`.nann.smashhockey.core.season.withBoard
import `in`.nann.smashhockey.core.season.won
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.FilamentHost
import `in`.nann.smashhockey.generated.AtmosphereData
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.look
import `in`.nann.smashhockey.scene.TeamColours
import `in`.nann.smashhockey.screens.CoachScreen
import `in`.nann.smashhockey.screens.HelpScreen
import `in`.nann.smashhockey.screens.HubScreen
import `in`.nann.smashhockey.screens.MatchHud
import `in`.nann.smashhockey.screens.RefusedScreen
import `in`.nann.smashhockey.screens.ResultScreen
import `in`.nann.smashhockey.screens.Screen
import `in`.nann.smashhockey.screens.TeamScreen
import `in`.nann.smashhockey.screens.TitleScreen
import `in`.nann.smashhockey.screens.TrainingScreen
import `in`.nann.smashhockey.ui.CameraPose
import `in`.nann.smashhockey.ui.Kit
import `in`.nann.smashhockey.ui.generated.DesignTokens
import `in`.nann.smashhockey.ui.KitSound
import `in`.nann.smashhockey.ui.Motion
import `in`.nann.smashhockey.ui.UIStage
import `in`.nann.smashhockey.core.generated.Drill

/**
 * The whole game on one stage (spec §15, §16) — the twin of iOS's Game.swift: one Filament scene
 * with one camera and one clock (ADR 0005), the pitch with the demo or the player's match on it,
 * the 3D UI's screens standing around it, and the save. Every screen change is a camera move;
 * every recorded result, career change and board change is written to the device before the next
 * screen appears. Main thread only, like the Choreographer frame that drives it.
 *
 * The screens are laid out from the surface's size and the safe area, so the stage is built on
 * the first frame that knows both.
 */
class Game(context: Context, private val surfaceView: SurfaceView, private val launch: MatchPlan?) {
    /** Where the player can be. Each is a screen of §16. */
    sealed interface Place {
        data class Refused(val why: String) : Place
        data object Team : Place
        data object Title : Place
        data object Hub : Place
        data class Training(val intro: Drill?) : Place
        data object Coach : Place
        data object Help : Place
        data class Result(val outcome: Outcome) : Place
    }

    private val host = FilamentHost(surfaceView, ::frame)
    private val engine = host.engine
    private val assets = Assets(context.assets)
    // The UI blocks are toon-shaded under the UI's own light (design.json), not the light of the world
    // standing behind them: a menu looks the same everywhere and a white slab stays white.
    val kit = Kit(engine, host.scene, assets, Typeface.createFromAsset(context.assets, "fonts/LilitaOne-Regular.ttf"),
        Motion.load(assets), DesignTokens.LOOK)
    val pitch = Pitch(context, engine, host.scene, assets)
    val keyboard = Keyboard()
    private val haptics = Haptics(context)
    /** The sound bank, loaded (and checked — a missing file fails the launch) before anything plays. */
    private val sfx = Sfx(context.assets)
    private val beds = Beds(context.assets)
    /** The stadium and the drums (§8.8): the core decides the levels, [beds] plays them. */
    private val atmosphere = Atmosphere(AtmosphereData.params)
    /** The player's two volumes (§12); until the coach's board offers them, their declared defaults. */
    private var crowdVolume = AtmosphereData.crowdDefault
    private var musicVolume = AtmosphereData.musicDefault
    private val store = SaveStore(context.filesDir)
    var save: SaveRecord; private set
    private val refusal: String?
    private val stageState = mutableStateOf<UIStage?>(null)
    /** The stage, once built — the semantics overlay reads it. */
    val stageRef: State<UIStage?> get() = stageState
    val stage: UIStage get() = stageState.value!!
    private var screen: Screen? = null
    private var hud: MatchHud? = null
    /** The player's match in progress — null while the demo plays. */
    var playing: MatchPlan? = null; private set
    /** The league table before the player's latest result, for the hub's reshuffle (§16.3). */
    var tableBefore: List<TableRow>? = null
    private var demoRound = 0
    private var demoOn = false
    private var opened = false
    private var boardDirty = false
    private var width = 0
    private var height = 0
    private var ui: Int? = null
    private val onPitch = HashSet<Int>()

    init {
        Copy.init(context)
        host.view.colorGrading = ColorGrading.Builder().toneMapper(ToneMapper.Linear()).build(engine)
        host.view.dynamicResolutionOptions = View.DynamicResolutionOptions().apply { enabled = true; minScale = 0.6f }
        host.camera.setExposure(16f, 1f / 125f, 100f)
        host.onResize = { w, h -> width = w; height = h; pitch.aspect = w.toDouble() / h; stageState.value?.resize(w, h) }
        pitch.onEvent = { matchEvent(it) }
        pitch.onCue = { cue(it) }
        KitSound.play = { sfx.play(it) }
        when (val loaded = store.load()) {
            is SaveStore.Loaded.New -> { save = loaded.record; refusal = null }
            is SaveStore.Loaded.Found -> { save = loaded.record; refusal = null }
            is SaveStore.Loaded.Refused -> { save = SaveRecord.fresh(); refusal = loaded.why }
        }
    }

    /** The menu the game comes back to: the title, or the team choice until there is a career. */
    val home: Place get() = if (save.career == null) Place.Team else Place.Title

    private fun build() {
        val insets = ViewCompat.getRootWindowInsets(surfaceView)
            ?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
        val start = pose(Presentation.Screens.Refused.eye, Presentation.Screens.Refused.target)
        stageState.value = UIStage(kit, host.camera, host.camera.entity, start, width, height, insets?.top ?: 0, insets?.bottom ?: 0)
        if (refusal != null) {
            Log.e(TAG, "save refused: $refusal")
            go(Place.Refused(refusal))
        } else {
            go(home)
            launch?.let { play(it) }
        }
    }

    // ---------------------------------------------------------------- screens

    /**
     * The one way between screens: the old one's parts hop away, the camera swoops, the new one's
     * parts tumble in as it arrives. The demo plays behind every menu (§9).
     */
    fun go(next: Place) {
        flush()
        keyboard.end()
        val first = !opened
        opened = true
        screen?.leave()
        val s = when (next) {
            is Place.Refused -> RefusedScreen(this, next.why)
            Place.Team -> TeamScreen(this)
            Place.Title -> TitleScreen(this)
            Place.Hub -> HubScreen(this)
            is Place.Training -> TrainingScreen(this, next.intro)
            Place.Coach -> CoachScreen(this)
            Place.Help -> HelpScreen(this)
            is Place.Result -> ResultScreen(this, next.outcome)
        }
        screen = s
        stage.rig.swoop(s.pose, roll = if (first) 0f else 0.12f)
        s.show(if (first) 0.9 else 0.45)
        if (playing != null) endMatch()
        if (!demoOn) startDemo()
        Log.i(TAG, "screen $next")
    }

    // ---------------------------------------------------------------- the save (§15)

    /**
     * Changes the save and writes it before anything else happens. A change the core refuses is
     * logged and dropped — the screens only offer what the rules allow.
     */
    fun commit(change: (SaveRecord) -> SaveRecord): Boolean {
        val next = try { change(save) } catch (e: GameException) {
            Log.e(TAG, "refused change: ${e.error}")
            return false
        }
        save = next
        write()
        return true
    }

    /**
     * A change on the coach's board (§12): taken at once, written by the end of the frame — a
     * dragged slider changes many times a second, the file once per frame at most (§15).
     */
    fun setBoard(board: BoardRecord) {
        save = try { save.withBoard(board) } catch (e: GameException) {
            Log.e(TAG, "refused board: ${e.error}")
            return
        }
        boardDirty = true
    }

    private fun flush() { if (boardDirty) write() }

    private fun write() {
        boardDirty = false
        try { store.write(save) } catch (e: Exception) { Log.wtf(TAG, "the save could not be written", e) }
    }

    /** The refusal's one way on (§15): the refused file moved aside, untouched; a new one begun. */
    fun startOver() {
        save = try { store.replaceRefused().first } catch (e: Exception) {
            Log.wtf(TAG, "starting over failed", e)
            return
        }
        go(Place.Team)
    }

    // ---------------------------------------------------------------- the match

    /** Starts [plan] — one tap from the menu to the face-off (A2). The camera swoops onto the match camera. */
    fun play(plan: MatchPlan) {
        flush()
        val kickoff = plan.kickoff(save, MatchPlan.seed()) ?: return
        keyboard.end()
        screen?.leave()
        screen = null
        hud?.leave()
        playing = plan
        demoOn = false
        pitch.start(plan, kickoff)
        sfx.sport = kickoff.world.sport
        beds.stadium(true)
        hud = MatchHud(this, plan, kickoff).also { it.show(0.5) }
        kickoff.names?.let { pitch.intro(it[0], it[1]) }
        stage.rig.track { pitch.pose }
    }

    /** The pause button, and the app leaving the foreground (§8.7). */
    fun pause(on: Boolean) {
        if (playing == null || pitch.plan != playing) return
        pitch.paused = on
        hud?.setPaused(on)
    }

    /** Quit from the pause panel (§8.7): a season match is forfeited 0–3 (the panel said so); anything else just leaves. */
    fun quit() {
        when (val plan = playing ?: return) {
            MatchPlan.Season -> {
                rememberTable()
                commit { it.forfeit().first }
                go(Place.Hub)
            }
            is MatchPlan.Practice -> go(Place.Training(plan.drill))
            else -> go(home)
        }
    }

    private fun rememberTable() { save.career?.let { c -> tableBefore = save.season?.table(c) } }

    private fun endMatch() {
        sfx.clearLater()
        beds.stadium(false)
        hud?.leave()
        hud = null
        playing = null
        pitch.paused = false
    }

    private fun matchEvent(e: MatchEvent) {
        val plan = playing ?: return
        if (pitch.plan != plan) return
        hud?.event(e)
        pitch.snapshot?.let { atmosphere.hear(e, it) }
        if (e !is MatchEvent.End) return
        val s = pitch.snapshot ?: return
        val k = pitch.kickoff
        val outcome = Outcome(plan, s.score, s.overtime, e.result, k?.codes, k?.colours ?: emptyList(), k?.drillGoals)
        // Recorded now, before anything else can happen (§15); shown once the banner has had its moment.
        when {
            plan == MatchPlan.Season -> {
                rememberTable()
                commit { it.recordPlayed(s.score[0], s.score[1], s.overtime).first }
            }
            plan is MatchPlan.Practice && e.result == MatchResult.WON -> commit { it.won(plan.drill) }
        }
        stage.after(Presentation.Screens.resultDelay) { if (playing == plan) go(Place.Result(outcome)) }
    }

    /** What the match sets off beyond the pitch (§8.8, §16.4): the HUD's banners, the haptics, the sounds. */
    private fun cue(c: Cue) {
        when (c) {
            is Cue.Show -> hud?.banner(c.banner)
            is Cue.Sound -> {
                sfx.play(c.cue, c.x, c.delay)
                if (c.cue in AtmosphereData.duckCues) atmosphere.duck(c.delay)
            }
            is Cue.Feel -> if (c.delay > 0) stage.after(c.delay) { if (playing != null) haptics.play(c.haptic) } else haptics.play(c.haptic)
            is Cue.Shake, is Cue.Pop -> Unit      // the pitch draws these itself
        }
    }

    /**
     * The demo behind the menus (§9): the player's team against a random club, in the worlds in
     * turn — starting from whichever world stands, so a menu never waits for a load.
     */
    private fun startDemo() {
        pitch.worldShown?.let { demoRound = demoRound - demoRound % World.entries.size + World.entries.indexOf(it) }
        val plan = MatchPlan.demo(demoRound, save)
        val kickoff = plan.kickoff(save, MatchPlan.seed()) ?: return
        demoOn = true
        pitch.start(plan, kickoff)
    }

    // ---------------------------------------------------------------- the frame, the one clock (ADR 0005)

    fun start() { host.start(); sfx.resume(); beds.resume() }
    fun stop() { host.stop(); sfx.pause(); beds.pause(); haptics.stop() }

    private fun frame(dt: Double, @Suppress("UNUSED_PARAMETER") frameTimeNanos: Long) {
        if (stageState.value == null) {
            if (width <= 1 || height <= 1) return
            build()
        }
        val stage = stage
        val step = dt.coerceIn(0.0, 0.1)
        val reduce = !ValueAnimator.areAnimatorsEnabled()
        stage.reduceMotion = reduce
        pitch.reduceMotion = reduce
        pitch.update(dt)
        sfx.update(step, pitch.timeScale)
        beds.menu(playing == null)
        val heard = pitch.atmosphere
        beds.apply(atmosphere.update(step, heard?.first, heard?.second, pitch.timeScale), crowdVolume, musicVolume)
        val p = pitch.plan
        if (demoOn && p is MatchPlan.Demo && pitch.endedFor > Presentation.Screens.demoRest) {
            demoRound = p.round + 1
            val plan = MatchPlan.demo(demoRound, save)
            plan.kickoff(save, MatchPlan.seed())?.let { pitch.start(plan, it) }
        }
        screen?.update(step)
        hud?.update(step)
        stage.update(step)
        host.camera.setProjection(stage.rig.fovDegrees, width.toDouble() / maxOf(height, 1),
            Presentation.Camera.near, Presentation.Camera.far, Camera.Fov.VERTICAL)
        flush()
    }

    // ---------------------------------------------------------------- touches

    /**
     * Every finger on the surface. A finger that lands on a 3D control belongs to the UI (the first
     * such finger drives it); every other finger is the match's while a match is being played: the
     * first one down holds, the last one up releases (§5.3).
     */
    fun onTouch(e: MotionEvent): Boolean {
        val stage = stageState.value ?: return true
        val i = e.actionIndex
        val id = e.getPointerId(i)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (ui == null && stage.touchDown(e.getX(i), e.getY(i))) {
                    ui = id
                } else if (pitchTakesFingers) {
                    val first = onPitch.isEmpty()
                    onPitch += id
                    if (first) pitch.hold(true, e.eventTime)
                }
            }
            MotionEvent.ACTION_MOVE -> ui?.let { u ->
                val at = e.findPointerIndex(u)
                if (at >= 0) stage.touchMoved(e.getX(at), e.getY(at))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> lift(stage, id, e.getX(i), e.getY(i), e.eventTime)
            MotionEvent.ACTION_CANCEL -> for (k in 0 until e.pointerCount) lift(stage, e.getPointerId(k), e.getX(k), e.getY(k), e.eventTime)
        }
        return true
    }

    private fun lift(stage: UIStage, id: Int, x: Float, y: Float, time: Long) {
        if (id == ui) {
            ui = null
            stage.touchUp(x, y)
        } else if (onPitch.remove(id) && onPitch.isEmpty()) {
            pitch.hold(false, time)
        }
    }

    private val pitchTakesFingers get() = playing != null && pitch.plan == playing && !pitch.paused

    fun destroy() {
        host.stop()
        kit.destroy()
        pitch.destroy()
        sfx.release()
        beds.release()
        KitSound.play = null
        host.destroy()
    }

    companion object {
        const val TAG = "SmashGame"
        fun pose(eye: List<Double>, target: List<Double>) =
            CameraPose(eye[0].toFloat(), eye[1].toFloat(), eye[2].toFloat(), target[0].toFloat(), target[1].toFloat(), target[2].toFloat())
    }
}

/** How a match or drill ended, for the result screen (§16.5). */
data class Outcome(
    val plan: MatchPlan,
    val score: List<Int>,
    val overtime: Boolean,
    val result: MatchResult,
    val codes: List<String>?,
    val colours: List<TeamColours>,
    val drillGoals: Int?,
)

/**
 * The system keyboard for the create screen's name and code (§16.1) — the twin of iOS's
 * `Keyboard`: what is being typed, into which field, read by the hidden text field in the Compose
 * layer.
 */
class Keyboard {
    enum class Field { NAME, CODE }
    val field = mutableStateOf<Field?>(null)
    val text = mutableStateOf("")
    private var onChange: ((String) -> Unit)? = null
    private var onEnd: (() -> Unit)? = null

    fun begin(f: Field, initial: String, onChange: (String) -> Unit, onEnd: () -> Unit) {
        val previous = this.onEnd
        this.onChange = null
        this.onEnd = null
        previous?.invoke()
        text.value = initial
        this.onChange = onChange
        this.onEnd = onEnd
        field.value = f
    }

    /** The hidden field typed: the screen hears of it. */
    fun typed(value: String) {
        if (field.value == null || value == text.value) return
        text.value = value
        onChange?.invoke(value)
    }

    /** Typing is over (done, the keyboard dismissed, or the screen left). */
    fun end() {
        if (field.value == null) return
        field.value = null
        onChange = null
        val done = onEnd
        onEnd = null
        done?.invoke()
    }
}
