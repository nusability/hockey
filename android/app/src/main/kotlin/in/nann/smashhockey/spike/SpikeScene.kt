package `in`.nann.smashhockey.spike

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Typeface
import android.view.SurfaceView
import com.google.android.filament.Camera
import com.google.android.filament.Colors
import com.google.android.filament.ColorGrading
import com.google.android.filament.MaterialInstance
import com.google.android.filament.ToneMapper
import com.google.android.filament.View
import `in`.nann.smashhockey.R
import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.FilamentHost
import `in`.nann.smashhockey.engine.FrameStats
import `in`.nann.smashhockey.engine.GpuMesh
import `in`.nann.smashhockey.engine.MeshBuilder
import `in`.nann.smashhockey.engine.MotionTokens
import `in`.nann.smashhockey.engine.Node
import `in`.nann.smashhockey.engine.Spring
import `in`.nann.smashhockey.engine.TextMesh
import `in`.nann.smashhockey.engine.World
import `in`.nann.smashhockey.core.generated.World as WorldId
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.tan

/** A screen rectangle in pixels, for the accessibility overlay. */
data class ScreenRect(val left: Int, val top: Int, val right: Int, val bottom: Int)

/**
 * The renderer spike's vertical slice (SMASH-2): the Oasis world, a floating title, a
 * camera-parented score HUD and one 3D button that squashes on a spring. Throwaway content on
 * the foundation it exists to prove — the engine package is what stays.
 */
class SpikeScene(
    private val context: Context,
    surfaceView: SurfaceView,
    private val onButtonRect: (ScreenRect?) -> Unit,
) {
    private val host = FilamentHost(surfaceView, ::frame)
    private val engine = host.engine
    private val assets = Assets(context.assets)
    private val motion = MotionTokens.load(assets)
    private val stats = FrameStats(context)
    private val typeface = Typeface.createFromAsset(context.assets, "fonts/LilitaOne-Regular.ttf")
    private val reduceMotion = !ValueAnimator.areAnimatorsEnabled()
    private val uiMaterial = assets.material(engine, "ui_lit")
    // The world and its light and fog as the match draws them (World): the spike's Oasis.
    private val world = World(engine, host.scene, host.view, assets, WorldId.OASIS)
    private val instances = mutableListOf<MaterialInstance>()
    private val meshes = mutableListOf<GpuMesh>()
    private val palette = mutableMapOf<Int, MaterialInstance>()
    private lateinit var buttonMaterial: MaterialInstance
    private lateinit var labelMaterial: MaterialInstance

    private val fovDegrees = 50.0
    private var aspect = 0.5
    private val hudDepth = 4f

    private lateinit var title: Node
    private lateinit var probe: Node
    private lateinit var button: Node
    private lateinit var buttonLabel: Node
    private var score: Node? = null
    private var clock: Node? = null
    private var clockText = ""
    private var goals = 0

    private val press = Spring(motion.bouncy)
    private var fade = 0.0
    private var time = 0.0
    private var lastRect: ScreenRect? = null

    val buttonLabelText: String = context.getString(R.string.play_button)

    init {
        host.view.colorGrading = ColorGrading.Builder().toneMapper(ToneMapper.Linear()).build(engine)
        host.view.dynamicResolutionOptions = View.DynamicResolutionOptions().apply { enabled = true; minScale = 0.6f }
        host.camera.setExposure(16f, 1f / 125f, 100f)
        host.camera.lookAt(0.0, 24.0, -46.0, 0.0, 0.0, 2.0, 0.0, 1.0, 0.0)
        host.onResize = { w, h ->
            aspect = w.toDouble() / h
            host.camera.setProjection(fovDegrees, aspect, 0.1, 500.0, Camera.Fov.VERTICAL)
            project()
        }

        buildTitle()
        buildHud()
        buildButton()
    }

    fun start() = host.start()
    fun stop() = host.stop()

    /** A tap on the surface: our own hit-test against the 3D UI. True when the UI took it. */
    fun tap(px: Float, py: Float): Boolean {
        val (origin, dir) = ray(px, py)
        return if (button.hit(origin, dir) != null || buttonLabel.hit(origin, dir) != null) { press(); true } else false
    }

    /** The button's action — reached by a tap on the 3D button or by the accessibility overlay. */
    fun press() {
        if (reduceMotion) fade = 1.0 else press.kick(motion.pressKick)
        goals = (goals + 1) % 10
        score = replaceText(score, "$goals : 0", 0.2f, 0.05f, 0xFFFFFF) { n -> hudPlace(n, 0.82f) }
    }

    // ---------------------------------------------------------------- frame

    private fun frame(dt: Double, @Suppress("UNUSED_PARAMETER") frameTimeNanos: Long) {
        stats.record(dt)
        val step = dt.coerceAtMost(0.1)
        time += step
        press.advance(step)
        if (fade > 0) fade = (fade - step / motion.fadeSeconds).coerceAtLeast(0.0)

        title.y = 4.5f + 0.3f * sin(time * 1.4).toFloat()
        title.yaw = PI.toFloat() + 0.12f * sin(time * 0.9).toFloat()
        title.apply()

        val s = press.value.toFloat()
        button.sy = 1f - motion.pressSquash.toFloat() * s
        button.sx = 1f + motion.pressBulge.toFloat() * s
        button.sz = button.sx
        button.apply()
        val alpha = (1.0 - 0.6 * fade).toFloat()
        buttonMaterial.setParameter("alpha", alpha)
        labelMaterial.setParameter("alpha", alpha)

        val remaining = (120 - time.toInt() % 121).coerceAtLeast(0)
        val text = "%d:%02d".format(remaining / 60, remaining % 60)
        if (text != clockText) {
            clockText = text
            clock = replaceText(clock, text, 0.11f, 0.03f, 0xFFE8A3) { n -> hudPlace(n, 0.69f) }
        }
        project()
    }

    // ---------------------------------------------------------------- building

    private fun buildTitle() {
        title = textNode(null, context.getString(R.string.app_name), 2.0f, 0.55f, 0xFFF4D6)
        title.z = 18f
        probe = textNode(null, context.getString(R.string.umlaut_probe), 1.1f, 0.35f, 0xFF6B6B)
        probe.x = 0f; probe.y = 1.6f; probe.z = 17f; probe.yaw = PI.toFloat(); probe.apply()
    }

    private fun buildHud() {
        score = replaceText(null, "0 : 0", 0.2f, 0.05f, 0xFFFFFF) { n -> hudPlace(n, 0.82f) }
    }

    private fun buildButton() {
        val block = MeshBuilder().box(0.95f, 0.34f, 0.16f).build()
        buttonMaterial = colour(0xFFC83D)
        labelMaterial = colour(0x1E1B4B)
        button = Node(engine, host.camera.entity, gpu(block, buttonMaterial))
        button.y = -hudHalfHeight() * 0.62f; button.z = -hudDepth
        button.apply()
        buttonLabel = Node(engine, button.entity, gpu(TextMesh.build(buttonLabelText, typeface, 0.15f, 0.04f), labelMaterial))
        buttonLabel.z = 0.09f
        buttonLabel.apply()
    }

    private fun hudHalfHeight() = (hudDepth * tan(Math.toRadians(fovDegrees / 2))).toFloat()

    private fun hudPlace(n: Node, fromTop: Float) {
        n.y = hudHalfHeight() * fromTop
        n.z = -hudDepth
        n.apply()
    }

    private fun textNode(parent: Int?, text: String, height: Float, depth: Float, rgb: Int): Node {
        val node = Node(engine, parent, gpu(TextMesh.build(text, typeface, height, depth), colour(rgb)))
        node.apply()
        return node
    }

    private fun replaceText(old: Node?, text: String, height: Float, depth: Float, rgb: Int, place: (Node) -> Unit): Node {
        old?.mesh?.let { host.scene.removeEntity(it.entity); meshes.remove(it); it.destroy() }
        val node = Node(engine, host.camera.entity, gpu(TextMesh.build(text, typeface, height, depth), colour(rgb)))
        place(node)
        return node
    }

    /** One material instance per colour, reused — text re-meshing must not leak instances. */
    private fun colour(rgb: Int): MaterialInstance = palette.getOrPut(rgb) {
        uiMaterial.createInstance().also { mi ->
            val c = Colors.toLinear(Colors.RgbType.SRGB, ((rgb shr 16) and 0xFF) / 255f, ((rgb shr 8) and 0xFF) / 255f, (rgb and 0xFF) / 255f)
            mi.setParameter("baseColor", Colors.RgbType.LINEAR, c[0], c[1], c[2])
            mi.setParameter("alpha", 1f)
            instances += mi
        }
    }

    private fun gpu(data: `in`.nann.smashhockey.engine.MeshData, mi: MaterialInstance): GpuMesh {
        val mesh = GpuMesh(engine, data, mi)
        meshes += mesh
        host.scene.addEntity(mesh.entity)
        return mesh
    }

    // ---------------------------------------------------------------- camera maths

    private fun ray(px: Float, py: Float): Pair<FloatArray, FloatArray> {
        val ndcX = 2.0 * px / host.width - 1.0
        val ndcY = 1.0 - 2.0 * py / host.height
        val t = tan(Math.toRadians(fovDegrees / 2))
        val dv = doubleArrayOf(ndcX * t * aspect, ndcY * t, -1.0)
        val m = DoubleArray(16).also { host.camera.getModelMatrix(it) }
        val dir = FloatArray(3) { i -> (m[i] * dv[0] + m[4 + i] * dv[1] + m[8 + i] * dv[2]).toFloat() }
        val origin = floatArrayOf(m[12].toFloat(), m[13].toFloat(), m[14].toFloat())
        return origin to dir
    }

    /** Projects the button's bounds to the screen for the accessibility overlay. */
    private fun project() {
        if (!::button.isInitialized) return
        val view = DoubleArray(16).also { host.camera.getViewMatrix(it) }
        val proj = DoubleArray(16).also { host.camera.getProjectionMatrix(it) }
        var l = Float.MAX_VALUE; var t = Float.MAX_VALUE; var r = -Float.MAX_VALUE; var b = -Float.MAX_VALUE
        for (p in button.worldCorners()) {
            val v = mul(view, p); val c = mul(proj, v)
            if (c[3] <= 0) continue
            val sx = ((c[0] / c[3] + 1) / 2 * host.width).toFloat()
            val sy = ((1 - c[1] / c[3]) / 2 * host.height).toFloat()
            l = minOf(l, sx); r = maxOf(r, sx); t = minOf(t, sy); b = maxOf(b, sy)
        }
        val rect = if (l < r) ScreenRect(l.toInt(), t.toInt(), r.toInt(), b.toInt()) else null
        if (rect != lastRect) { lastRect = rect; onButtonRect(rect) }
    }

    private fun mul(m: DoubleArray, p: FloatArray): DoubleArray = DoubleArray(4) { i ->
        m[i] * p[0] + m[4 + i] * p[1] + m[8 + i] * p[2] + m[12 + i] * (if (p.size > 3) p[3].toDouble() else 1.0)
    }

    private fun mul(m: DoubleArray, p: DoubleArray): DoubleArray = DoubleArray(4) { i ->
        m[i] * p[0] + m[4 + i] * p[1] + m[8 + i] * p[2] + m[12 + i] * p[3]
    }

    fun destroy() {
        host.stop()
        meshes.forEach { it.destroy() }
        instances.forEach { engine.destroyMaterialInstance(it) }
        engine.destroyMaterial(uiMaterial)
        world.destroy()
        host.destroy()
    }
}
