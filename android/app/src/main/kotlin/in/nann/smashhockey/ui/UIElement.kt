package `in`.nann.smashhockey.ui

/** What every frame hands a UI element: the tokens, the time, and whether to be calm. One object, reused. */
class UiContext(val motion: Motion) {
    var reduceMotion = false
        internal set
    var time = 0.0
        internal set
}

/** A piece of the 3D UI: one node subtree with its own motion, advanced by the stage's clock. */
interface UiElement {
    val node: UiNode
    fun update(dt: Double, ctx: UiContext)
}

/** An element that arrives and leaves on its own motion (see [Presence]). */
interface Presentable : UiElement {
    /** Where it stands once it has arrived, in its parent's space. */
    val rest: Xform
    fun show(after: Double = 0.0)
    fun hide(after: Double = 0.0)
}

/**
 * What a node tells the accessibility overlay about itself (ADR 0005). The overlay is derived
 * from these every frame — never hand-placed.
 */
class Semantics(
    /** The stable id, the same on both platforms: `<surface>_<action>_button` and friends. */
    val id: String,
    var label: String,
    var value: String? = null,
    val trait: Trait,
    var isEnabled: Boolean = true,
    /** A chosen option among several (a club, a swatch, a formation). */
    var isSelected: Boolean = false,
) {
    enum class Trait { BUTTON, ADJUSTABLE, STATIC_TEXT, HEADER }
}

/**
 * An element TalkBack can find: it declares semantics and the box (in [boundsNode]'s own space)
 * that the overlay projects to the screen.
 */
interface Semantic : UiElement {
    val semantics: Semantics
    val boundsNode: UiNode
    val bounds: Bounds
    /** On screen and settled enough to be found (not arriving, leaving or hidden). */
    val isPresent: Boolean
}

/**
 * A Semantic that takes touches. The stage's own ray test finds it; the overlay's activation and
 * adjust actions route to the same code a finger does. Rays arrive in [boundsNode]'s space.
 */
interface Interactive : Semantic {
    fun touchDown(ray: TouchRay)
    fun touchMoved(ray: TouchRay) {}
    /** [inside]: the finger lifted over the element — a button fires only then. */
    fun touchUp(ray: TouchRay, inside: Boolean)
    fun activate()
    fun adjust(steps: Int) {}
}
