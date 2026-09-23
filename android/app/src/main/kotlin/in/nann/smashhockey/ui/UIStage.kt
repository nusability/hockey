package `in`.nann.smashhockey.ui

import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import com.google.android.filament.Camera
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.sqrt
import kotlin.math.tan

/** One accessibility element, projected from a 3D node for the Compose overlay. Pixels. */
data class A11yNode(
    val id: String,
    val label: String,
    val value: String?,
    val trait: Semantics.Trait,
    val isEnabled: Boolean,
    val isSelected: Boolean,
    val left: Int, val top: Int, val right: Int, val bottom: Int,
)

/**
 * The 3D UI's stage — the twin of iOS's `UIStage`: the camera rig, the HUD rig, every element's
 * clock, our own ray hit-test (ADR 0005 — synchronous in the touch handler), and the derived
 * accessibility overlay. Screens add elements; the stage updates, hit-tests and projects them.
 * Nothing else drives UI motion. Main thread only, like the Choreographer frame that drives it.
 */
class UIStage(
    val kit: Kit,
    camera: Camera,
    cameraEntity: Int,
    start: CameraPose,
    viewW: Int, viewH: Int,
    private val insetTop: Int, private val insetBottom: Int,
) {
    val motion = kit.motion
    val root = kit.node(null)
    val rig = CameraRig(camera, start, motion)
    val hud: ScreenFrame
    var reduceMotion = false
    var viewW = viewW; private set
    var viewH = viewH; private set
    val time get() = ctx.time
    private val ctx = UiContext(motion)
    private val elements = ArrayList<UiElement>()
    private val semantic = ArrayList<Semantic>()
    private val interactive = ArrayList<Interactive>()
    private var active: Interactive? = null
    /**
     * A card standing in front of the screen (§16.6): while one is up, only what hangs under it
     * takes fingers or reaches TalkBack. Everything behind is inert, not merely disabled.
     */
    private var modalRoot: UiNode? = null

    private class Timer(val at: Double, val run: () -> Unit)
    private val timers = ArrayList<Timer>()
    private val due = ArrayList<Timer>()

    private val nodes = mutableStateOf<List<A11yNode>>(emptyList())
    /** What the overlay reads: the projected nodes of this frame. Written only when it changed. */
    val semanticsNodes: State<List<A11yNode>> get() = nodes

    init {
        hud = ScreenFrame(kit.node(null, parentEntity = cameraEntity), CameraRig.MENU_FOV, viewW, viewH, insetTop, insetBottom)
    }

    fun resize(w: Int, h: Int) { viewW = w; viewH = h }

    /**
     * Puts a card in front of everything: nothing outside [root] is touchable or findable until
     * this is called again with null. A finger held on something behind is let go without firing.
     */
    fun setModal(root: UiNode?) {
        modalRoot = root
        active?.let { if (!reachable(it.node)) active = null }
    }

    /** Whether [n] is reachable at all — always, unless a card stands in front of it. */
    private fun reachable(n: UiNode): Boolean {
        val root = modalRoot ?: return true
        var p: UiNode? = n
        while (p != null) { if (p === root) return true; p = p.parentNode }
        return false
    }

    /** A world-standing frame for a screen seen from [pose]. */
    fun frame(pose: CameraPose): ScreenFrame {
        val f = ScreenFrame(kit.node(root), CameraRig.MENU_FOV, viewW, viewH, insetTop, insetBottom)
        f.stand(rig.transform(pose))
        return f
    }

    /** Registers [element] and hangs it under [parent]. The stage drives it from now on. */
    fun <E : UiElement> add(element: E, parent: UiNode): E {
        element.node.reparent(parent)
        elements += element
        if (element is Semantic) semantic += element
        if (element is Interactive) interactive += element
        return element
    }

    /** Runs [body] after [seconds] of stage time — for choreography, never for input. */
    fun after(seconds: Double, body: () -> Unit) { timers += Timer(ctx.time + seconds, body) }

    // ------------------------------------------------------------------ frame

    fun update(dt: Double) {
        ctx.time += dt
        if (timers.isNotEmpty()) {
            val now = ctx.time
            for (i in 0 until timers.size) if (timers[i].at <= now) due += timers[i]
            if (due.isNotEmpty()) {
                timers.removeAll { it.at <= now }
                for (i in 0 until due.size) due[i].run()
                due.clear()
            }
        }
        rig.update(dt, reduceMotion)
        hud.zoom(rig.fovDegrees)
        ctx.reduceMotion = reduceMotion
        for (i in 0 until elements.size) elements[i].update(dt, ctx)
        kit.flush()
        project()
    }

    // ------------------------------------------------------------------ touches (pixels)

    /** A finger went down at (px, py): true when a present interactive element took it. */
    fun touchDown(px: Float, py: Float): Boolean {
        val ray = ray(px, py)
        val a = pick(ray)
        active = a
        a?.touchDown(ray.local(a.boundsNode))
        return a != null
    }

    /**
     * Forgets every element under [root] (a screen leaving for good) and destroys [root] with its
     * subtree. A finger on one of them is let go without firing.
     */
    fun remove(root: UiNode) {
        fun inside(n: UiNode): Boolean {
            var p: UiNode? = n
            while (p != null) { if (p === root) return true; p = p.parentNode }
            return false
        }
        elements.removeAll { inside(it.node) }
        semantic.removeAll { inside(it.node) }
        interactive.removeAll { inside(it.node) }
        active?.let { if (inside(it.node)) active = null }
        modalRoot?.let { if (inside(it)) modalRoot = null }
        kit.destroy(root)
    }

    fun touchMoved(px: Float, py: Float) {
        val a = active ?: return
        a.touchMoved(ray(px, py).local(a.boundsNode))
    }

    fun touchUp(px: Float, py: Float) {
        val a = active ?: return
        active = null
        val local = ray(px, py).local(a.boundsNode)
        a.touchUp(local, a.isPresent && local.hit(a.bounds) != null)
    }

    /** The nearest present interactive element under the ray. Disabled ones are hit too, so they can say no. */
    private fun pick(ray: TouchRay): Interactive? {
        var best: Interactive? = null
        var bestDistance = Float.MAX_VALUE
        for (i in 0 until interactive.size) {
            val e = interactive[i]
            if (!e.isPresent || !e.takesTouches || !reachable(e.node)) continue
            val local = ray.local(e.boundsNode)
            val t = local.hit(e.bounds) ?: continue
            // Compare in world distance: local t is scaled by the node's scale.
            val m = e.boundsNode.worldMatrix()
            val lx = local.ox + local.dx * t; val ly = local.oy + local.dy * t; val lz = local.oz + local.dz * t
            val wx = m[0] * lx + m[4] * ly + m[8] * lz + m[12] - ray.ox
            val wy = m[1] * lx + m[5] * ly + m[9] * lz + m[13] - ray.oy
            val wz = m[2] * lx + m[6] * ly + m[10] * lz + m[14] - ray.oz
            val d = sqrt(wx * wx + wy * wy + wz * wz)
            if (d < bestDistance) { best = e; bestDistance = d }
        }
        return best
    }

    private fun ray(px: Float, py: Float): TouchRay {
        val aspect = viewW.toFloat() / maxOf(viewH, 1)
        val ndcX = 2 * px / viewW - 1
        val ndcY = 1 - 2 * py / viewH
        val t = tan(Math.toRadians(rig.fovDegrees / 2)).toFloat()
        val vx = ndcX * t * aspect; val vy = ndcY * t; val vz = -1f
        val w = rig.world
        return TouchRay(w[12], w[13], w[14],
            w[0] * vx + w[4] * vy + w[8] * vz, w[1] * vx + w[5] * vy + w[9] * vz, w[2] * vx + w[6] * vy + w[10] * vz)
    }

    // ------------------------------------------------------------------ accessibility

    /** TalkBack's activation of node [id] — the same action a tap fires. */
    fun activate(id: String) { find(id)?.activate() }

    fun adjust(id: String, steps: Int) { find(id)?.adjust(steps) }

    private fun find(id: String): Interactive? {
        for (i in 0 until interactive.size) {
            val e = interactive[i]
            if (e.semantics.id == id && e.isPresent && reachable(e.node)) return e
        }
        return null
    }

    /** The current screen rectangle of node [id], if it is on screen — for autoplay's pretend finger. */
    fun rect(id: String): A11yNode? = nodes.value.firstOrNull { it.id == id }

    // Scratch for the per-frame projection.
    private val found = arrayOfNulls<Semantic>(64)
    private val rects = IntArray(64 * 4)
    private val view = FloatArray(16)
    private val toView = FloatArray(16)

    /** Projects every present semantic node's box to the screen: the overlay is output, like pixels. */
    private fun project() {
        android.opengl.Matrix.invertM(view, 0, rig.world, 0)
        val aspect = viewW.toFloat() / maxOf(viewH, 1)
        val t = tan(Math.toRadians(rig.fovDegrees / 2)).toFloat()
        var count = 0
        for (i in 0 until semantic.size) {
            val s = semantic[i]
            if (!s.isPresent || !reachable(s.node) || count == found.size) continue
            val b = s.bounds
            android.opengl.Matrix.multiplyMM(toView, 0, view, 0, s.boundsNode.worldMatrix(), 0)
            var minX = Float.MAX_VALUE; var minY = Float.MAX_VALUE; var maxX = -Float.MAX_VALUE; var maxY = -Float.MAX_VALUE
            var behind = false
            for (c in 0 until 8) {
                val x = if (c and 1 == 0) b.minX else b.maxX
                val y = if (c and 2 == 0) b.minY else b.maxY
                val z = if (c and 4 == 0) b.minZ else b.maxZ
                val vx = toView[0] * x + toView[4] * y + toView[8] * z + toView[12]
                val vy = toView[1] * x + toView[5] * y + toView[9] * z + toView[13]
                val vz = toView[2] * x + toView[6] * y + toView[10] * z + toView[14]
                if (vz >= 0) { behind = true; continue }
                val nx = (vx / -vz) / (t * aspect); val ny = (vy / -vz) / t
                val sx = (nx + 1) / 2 * viewW; val sy = (1 - ny) / 2 * viewH
                if (sx < minX) minX = sx; if (sx > maxX) maxX = sx
                if (sy < minY) minY = sy; if (sy > maxY) maxY = sy
            }
            if (behind || minX >= maxX) continue
            val l = floor(minX).toInt(); val tp = floor(minY).toInt(); val r = ceil(maxX).toInt(); val bt = ceil(maxY).toInt()
            if (r <= 0 || bt <= 0 || l >= viewW || tp >= viewH) continue
            found[count] = s
            rects[count * 4] = l; rects[count * 4 + 1] = tp; rects[count * 4 + 2] = r; rects[count * 4 + 3] = bt
            count++
        }
        if (same(count)) return
        nodes.value = List(count) { i ->
            val sem = found[i]!!.semantics
            A11yNode(sem.id, sem.label, sem.value, sem.trait, sem.isEnabled, sem.isSelected, rects[i * 4], rects[i * 4 + 1], rects[i * 4 + 2], rects[i * 4 + 3])
        }
    }

    private fun same(count: Int): Boolean {
        val old = nodes.value
        if (old.size != count) return false
        for (i in 0 until count) {
            val o = old[i]; val s = found[i]!!.semantics
            if (o.id != s.id || o.label != s.label || o.value != s.value || o.isEnabled != s.isEnabled || o.isSelected != s.isSelected ||
                o.left != rects[i * 4] || o.top != rects[i * 4 + 1] || o.right != rects[i * 4 + 2] || o.bottom != rects[i * 4 + 3]) return false
        }
        return true
    }
}
