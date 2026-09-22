package `in`.nann.smashhockey.ui

/**
 * A slab that things sit on: a fixture card, a scoreboard housing, the pause sign — the twin of
 * iOS's `Panel`. It tumbles (or pops, or drops) in, hops away on the way out, and jiggles when
 * something happens to it. Children go on [content], whose z = 0 is the slab's front face.
 */
class Panel(
    kit: Kit,
    val w: Float, val h: Float, val d: Float,
    colour: Int,
    entrance: Entrance = Entrance.Tumble,
    corner: Float = DesignTokens.Size.CORNER,
) : Presentable {
    override val node = kit.node(null)
    /** The panel's own wobble lives here; children move with it. */
    val body = kit.node(node)
    val content = kit.node(body)
    override val rest = Xform()
    val presence = Presence(entrance, kit.motion)
    private val jiggle = Jiggle(kit.motion.spring(SpringName.WOBBLY))
    private val motion = kit.motion

    init {
        kit.slab(w, h, d, colour, body, corner)
        content.setPosition(0f, 0f, d / 2)
        node.enabled = false
    }

    override fun show(after: Double) = presence.show(after)
    override fun hide(after: Double) = presence.hide(after)
    val isSettledIn get() = presence.isSettledIn

    /** A happy jelly wobble — a goal, a win. [strength] scales the celebrate kick. */
    fun celebrate(strength: Double = 1.0) {
        val k = motion.kick(KickName.CELEBRATE) * strength
        jiggle.kick(k * 0.5, k * 0.4)
    }

    /** A little thud — a flipped number landing on it. */
    fun thud() = jiggle.kick(0.0, -motion.kick(KickName.CELEBRATE) * 0.15)

    override fun update(dt: Double, ctx: UiContext) {
        presence.advance(dt, ctx)
        presence.apply(node, rest, ctx.reduceMotion)
        if (!node.enabled) return
        jiggle.advance(dt, ctx.reduceMotion)
        body.transform.rot.set(jiggle.rotation)
        body.setScale(jiggle.scale)
    }
}
