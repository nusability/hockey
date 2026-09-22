package `in`.nann.smashhockey.scene

import android.graphics.Typeface
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.match.MatchSnapshot
import `in`.nann.smashhockey.engine.GpuMesh
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.engine.MeshBuilder
import `in`.nann.smashhockey.engine.MeshData
import `in`.nann.smashhockey.engine.MotionTokens
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.engine.Spring
import `in`.nann.smashhockey.engine.TextMesh
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.WorldLook
import kotlin.math.ceil
import kotlin.math.tan

/**
 * The match's minimal HUD (spec §8; the kit stream restyles it) — the twin of iOS's Hud.swift:
 * score, clock and period at the top, a pause button in the corner, and a banner for goals and
 * results — extruded text parented to the camera at a fixed depth (ADR 0005), laid out from the
 * frustum and the safe area, toon-shaded by the world's light like everything else (ADR 0006).
 */
class Hud(
    private val engine: Engine,
    private val scene: Scene,
    private val camera: Int,
    private val materials: Materials,
    private val look: WorldLook,
    private val typeface: Typeface,
    motion: MotionTokens,
    codes: List<String>?,
    colours: List<TeamColours>,
) {
    private val h = Presentation.Hud
    private val depth = h.depth.toFloat()
    private val halfHeight = (h.depth * tan(Math.toRadians(Presentation.Camera.hudFov / 2))).toFloat()
    private var aspect = 0.46f
    private var safeTop = 0f
    /** Scales everything so the HUD keeps its size on screen while the field of view breathes. */
    var zoom = 1f

    private val meshes = ArrayList<GpuMesh>()
    private var score: Node? = null
    private var clock: Node? = null
    private var paused: Node? = null
    private var banner: Node? = null
    private var bannerSpring = Spring(motion.bouncy)
    private val bouncy = motion.bouncy
    private var bannerTime = 0.0
    private val codeNodes: List<Node>
    private val pips = ArrayList<Node>()
    val pauseButton: Node
    private val bars: List<Node>
    private var scoreText = ""; private var clockText = ""
    private var period = 0

    init {
        val size = h.buttonSize.toFloat()
        pauseButton = node(MeshBuilder().box(size, size, size * 0.4f).build(), h.button)
        bars = listOf(-size * 0.14f, size * 0.14f).map { x ->
            Node(engine, pauseButton.entity, add(MeshBuilder().box(size * 0.12f, size * 0.5f, size * 0.1f).build(), h.buttonLabel)).also {
                it.x = x; it.z = size * 0.22f; it.apply()
            }
        }
        codeNodes = if (codes == null) emptyList() else codes.zip(colours).map { (code, c) -> text(code, h.clockHeight.toFloat(), 0.03f, c.primary) }
        if (codes != null) repeat(Tuning.Match.periods) { pips += node(MeshBuilder().box(0.07f, 0.07f, 0.02f).build(), PIP_OFF) }
        layout()
    }

    private fun add(data: MeshData, rgb: Int): GpuMesh =
        GpuMesh(engine, data, materials.toon(rgb, look)).also { meshes += it; scene.addEntity(it.entity) }

    private fun node(data: MeshData, rgb: Int) = Node(engine, camera, add(data, rgb))

    private fun text(s: String, height: Float, depth: Float, rgb: Int) = node(TextMesh.build(s, typeface, height, depth), rgb)

    private fun drop(n: Node?) {
        n?.mesh?.let { scene.removeEntity(it.entity); meshes.remove(it); it.destroy() }
    }

    /** The view's shape and its safe area (in pixels), for the layout. */
    fun resize(width: Int, height: Int, safeTopPx: Int) {
        aspect = width.toFloat() / maxOf(height, 1)
        safeTop = safeTopPx.toFloat() / maxOf(height, 1)
        layout()
    }

    private val top get() = halfHeight * (1 - 2 * safeTop) - halfHeight * h.margin.toFloat()
    private val right get() = halfHeight * aspect * (1 - h.margin.toFloat())

    private fun place(n: Node?, x: Float, y: Float, s: Float = 1f) {
        n ?: return
        n.x = x * zoom; n.y = y * zoom; n.z = -depth; n.scale(s * zoom); n.apply()
    }

    fun layout() {
        val size = h.buttonSize.toFloat()
        val sh = h.scoreHeight.toFloat(); val ch = h.clockHeight.toFloat()
        place(pauseButton, right - size / 2, top - size / 2)
        place(score, 0f, top - sh * 0.6f)
        place(clock, 0f, top - sh * 1.25f - ch * 0.5f)
        codeNodes.forEachIndexed { i, c -> place(c, (if (i == 0) -1 else 1) * 0.43f, top - sh * 0.6f) }
        pips.forEachIndexed { i, p -> place(p, (i - 1) * 0.11f, top - sh * 1.25f - ch * 1.7f) }
        place(paused, 0f, 0.25f)
        place(banner, 0f, halfHeight * 0.18f, bannerScale)
    }

    private var bannerScale = 1f

    /** Score, clock and period from the snapshot; a drill shows its goals against its target. */
    fun show(s: MatchSnapshot, drillGoals: Int?) {
        val t = if (drillGoals != null) "${s.score[0]} / $drillGoals" else "${s.score[0]} : ${s.score[1]}"
        if (t != scoreText) { scoreText = t; drop(score); score = text(t, h.scoreHeight.toFloat(), 0.05f, h.text) }
        val secs = ceil(s.clock).toInt()
        val c = "%d:%02d".format(secs / 60, secs % 60)
        if (c != clockText) { clockText = c; drop(clock); clock = text(c, h.clockHeight.toFloat(), 0.03f, h.clock) }
        if (s.period != period) {
            period = s.period
            val rm = engine.renderableManager
            pips.forEachIndexed { i, p ->
                rm.setMaterialInstanceAt(rm.getInstance(p.entity), 0, materials.toon(if (i < period) h.clock else PIP_OFF, look))
            }
        }
        layout()
    }

    /** A banner in the middle of the screen; null clears it. */
    fun raise(text: String?, rgb: Int = h.text, reduceMotion: Boolean) {
        drop(banner); banner = null
        text ?: return
        banner = text(text, h.bannerHeight.toFloat(), 0.1f, rgb)
        bannerTime = 0.0
        bannerSpring = Spring(bouncy, if (reduceMotion) 1.0 else 0.0).also { it.target = 1.0 }
        bannerScale = bannerSpring.value.toFloat()
        layout()
    }

    fun setPaused(on: Boolean, title: String) {
        drop(paused); paused = null
        if (on) paused = text(title, h.bannerHeight.toFloat(), 0.1f, h.text)
        layout()
    }

    /** Real time: the banner pops on its spring and leaves after a while. */
    fun advance(dt: Double, bannerSeconds: Double) {
        if (banner == null) return
        bannerTime += dt
        if (bannerTime > bannerSeconds) bannerSpring.target = 0.0
        bannerSpring.advance(dt)
        bannerScale = maxOf(bannerSpring.value, 0.0).toFloat()
        place(banner, 0f, halfHeight * 0.18f, bannerScale)
        if (bannerTime > bannerSeconds && bannerSpring.value < 0.02) raise(null, reduceMotion = false)
    }

    fun destroy() {
        meshes.forEach { scene.removeEntity(it.entity); it.destroy() }
        meshes.clear()
    }

    companion object { private const val PIP_OFF = 0x6B7280 }
}
