package `in`.nann.smashhockey.ui

import com.google.android.filament.EntityManager

/**
 * One node of the 3D UI — the twin of a RealityKit `Entity` as the kit uses it: a local
 * [transform] (translate · rotate · scale), children, an [enabled] flag that hides the whole
 * subtree, an [opacity] that fades it, and optionally a mesh drawn in one colour.
 *
 * Changing [transform] is cheap: call [changed] and the kit writes it to Filament once, at the
 * end of the frame ([Kit.flush]). Visibility and opacity walk the subtree only when they change.
 */
class UiNode internal constructor(
    private val kit: Kit,
    parent: UiNode?,
    parentEntity: Int?,
    mesh: SharedMesh?,
    rgb: Int,
) {
    /** The node above, if it hangs from one (not from a raw entity such as the camera). */
    var parentNode: UiNode? = parent
        private set
    val entity: Int = EntityManager.get().create()

    /**
     * This node's slot in Filament's TransformManager — **looked up every time, never cached**.
     * A TransformManager instance is an index into a packed array, not a handle: destroying any
     * component swaps the last one into the freed slot, so every instance taken before a
     * `destroy` may now name a different entity. A screen taken apart therefore left the
     * surviving screens' nodes writing their pose into a stranger's slot — their own transform
     * stopped moving, frozen wherever the last good write had left it mid-arrival, while their
     * bounds (read through the same stale slot) answered from somewhere else entirely.
     */
    internal val instance: Int get() = kit.engine.transformManager.getInstance(entity)
    /** The local pose. Mutate it, then call [changed]. */
    val transform = Xform()
    private val children = ArrayList<UiNode>(2)
    internal var dirty = false
    private val world = FloatArray(16)

    var mesh: SharedMesh? = mesh
        private set
    var rgb: Int = rgb
        private set
    private var shownVisible = true
    private var shownAlpha = -1

    private var effectiveVisible: Boolean = parent?.effectiveVisible ?: true
    private var effectiveAlpha: Float = parent?.effectiveAlpha ?: 1f

    /** The nodes hanging from this one. */
    internal val childNodes: List<UiNode> get() = children

    init {
        val tm = kit.engine.transformManager
        tm.create(entity)
        val p = parent?.entity ?: parentEntity
        if (p != null) tm.setParent(instance, tm.getInstance(p))
        parent?.children?.add(this)
        if (mesh != null) {
            kit.buildRenderable(entity, mesh, kit.palette.instance(rgb, effectiveAlpha))
            shownAlpha = Palette.level(effectiveAlpha)
            applyVisible()
        }
        changed()
    }

    /** Marks the transform for writing at the end of the frame. */
    fun changed() {
        if (!dirty) { dirty = true; kit.markDirty(this) }
    }

    internal fun commit(scratch: FloatArray) {
        dirty = false
        transform.toMatrix(scratch)
        kit.engine.transformManager.setTransform(instance, scratch)
    }

    /** The node's world matrix, column-major (a scratch array owned by the node — copy to keep). */
    fun worldMatrix(): FloatArray {
        kit.engine.transformManager.getWorldTransform(instance, world)
        return world
    }

    // ------------------------------------------------------------------ transform shorthands

    fun setPosition(x: Float, y: Float, z: Float) { transform.tx = x; transform.ty = y; transform.tz = z; changed() }
    fun setScale(x: Float, y: Float, z: Float) { transform.sx = x; transform.sy = y; transform.sz = z; changed() }
    fun setScale(s: Float) = setScale(s, s, s)
    fun setRotation(q: Quat) { transform.rot.set(q); changed() }
    /** Takes [x] as the local pose; an unchanged pose costs nothing at flush. */
    fun setTransform(x: Xform) {
        val t = transform
        if (t.tx == x.tx && t.ty == x.ty && t.tz == x.tz && t.sx == x.sx && t.sy == x.sy && t.sz == x.sz &&
            t.rot.x == x.rot.x && t.rot.y == x.rot.y && t.rot.z == x.rot.z && t.rot.w == x.rot.w) return
        t.set(x)
        changed()
    }

    // ------------------------------------------------------------------ visibility and opacity

    /** Off hides this node and everything under it (RealityKit's `isEnabled`). */
    var enabled = true
        set(v) {
            if (field == v) return
            field = v
            refresh()
        }

    /** 0…1, multiplied down the subtree (RealityKit's `OpacityComponent`). */
    var opacity = 1f
        set(v) {
            val c = v.coerceIn(0f, 1f)
            if (field == c) return
            field = c
            refresh()
        }

    private fun refresh() {
        val pv = parentNode?.effectiveVisible ?: true
        val pa = parentNode?.effectiveAlpha ?: 1f
        val v = pv && enabled
        val a = pa * opacity
        if (v == effectiveVisible && a == effectiveAlpha) return
        effectiveVisible = v
        effectiveAlpha = a
        applyVisible()
        applyAlpha()
        for (i in 0 until children.size) children[i].refresh()
    }

    private fun applyVisible() {
        if (mesh == null || shownVisible == effectiveVisible) return
        shownVisible = effectiveVisible
        val rm = kit.engine.renderableManager
        rm.setLayerMask(rm.getInstance(entity), 0xFF, if (effectiveVisible) 0x1 else 0x0)
    }

    private fun applyAlpha() {
        if (mesh == null || !effectiveVisible) return
        val level = Palette.level(effectiveAlpha)
        if (level == shownAlpha) return
        shownAlpha = level
        val rm = kit.engine.renderableManager
        rm.setMaterialInstanceAt(rm.getInstance(entity), 0, kit.palette.instance(rgb, effectiveAlpha))
    }

    // ------------------------------------------------------------------ geometry and colour

    /** Paints the node's mesh in [newRgb] (at its current opacity). */
    fun recolour(newRgb: Int) {
        if (newRgb == rgb) return
        rgb = newRgb
        if (mesh == null) return
        shownAlpha = Palette.level(effectiveAlpha)
        val rm = kit.engine.renderableManager
        rm.setMaterialInstanceAt(rm.getInstance(entity), 0, kit.palette.instance(rgb, effectiveAlpha))
    }

    /** Swaps the drawn mesh in place — the same renderable, new (cached) buffers. */
    internal fun remesh(m: SharedMesh) {
        if (m === mesh) return
        mesh = m
        kit.swapGeometry(entity, m)
    }

    /** Hangs this node (and its subtree) under [p], taking on its visibility and opacity. */
    fun reparent(p: UiNode) {
        parentNode?.children?.remove(this)
        parentNode = p
        p.children.add(this)
        val tm = kit.engine.transformManager
        tm.setParent(instance, tm.getInstance(p.entity))
        refresh()
    }

    /** Unhooks this node from its parent's children (it is being destroyed). */
    internal fun detach() {
        parentNode?.children?.remove(this)
        parentNode = null
    }

    internal fun destroy() {
        if (mesh != null) {
            kit.scene.removeEntity(entity)
            kit.engine.renderableManager.destroy(entity)
        }
        kit.engine.transformManager.destroy(entity)
        EntityManager.get().destroy(entity)
    }
}
