package `in`.nann.smashhockey.ui

import `in`.nann.smashhockey.engine.Assets
import `in`.nann.smashhockey.engine.SpringToken

/** The springs the UI may ask for, by name. Every one must be in motion.json (checked at load). */
enum class SpringName(val key: String) { BOUNCY("bouncy"), SOFT("soft"), POP("pop"), SNAPPY("snappy"), WOBBLY("wobbly"), SWOOP("swoop") }

/** Named impulses (spring velocities) a component gives itself on an event. */
enum class KickName(val key: String) { NOPE("nope"), CELEBRATE("celebrate"), GRAB("grab") }

/**
 * The whole motion vocabulary the 3D UI kit reads (ADR 0005, `shared/data/motion.json`) — the twin
 * of iOS's `MotionTokens`, field for field. The engine's smaller `MotionTokens` serves the match
 * HUD; the kit needs every spring, the kicks, the stagger and the idle bob.
 */
class Motion private constructor(
    private val springs: Map<SpringName, SpringToken>,
    private val kicks: Map<KickName, Double>,
    val fadeSeconds: Double,
    val pressKick: Double,
    val pressSquash: Double,
    val pressBulge: Double,
    /** How far a held button stays squashed (0 = rest, 1 = full squash). */
    val pressHold: Double,
    /** The delay between siblings arriving or leaving one after another. */
    val staggerSeconds: Double,
    val idleBobMetres: Double,
    val idleBobSeconds: Double,
) {
    val bouncy: SpringToken get() = spring(SpringName.BOUNCY)

    fun spring(name: SpringName): SpringToken = springs.getValue(name)   // total by construction (load)
    fun kick(name: KickName): Double = kicks.getValue(name)

    companion object {
        /** Fails loud on a missing name: a token the kit asks for must exist. */
        fun load(assets: Assets): Motion {
            val json = assets.json("motion.json")
            val spring = json.getJSONObject("spring")
            val springs = SpringName.entries.associateWith { n ->
                check(spring.has(n.key)) { "motion.json has no spring '${n.key}'" }
                spring.getJSONObject(n.key).let { SpringToken(it.getDouble("stiffness"), it.getDouble("damping")) }
            }
            val kick = json.getJSONObject("kick")
            val kicks = KickName.entries.associateWith { n ->
                check(kick.has(n.key)) { "motion.json has no kick '${n.key}'" }
                kick.getDouble(n.key)
            }
            val press = json.getJSONObject("press")
            val idle = json.getJSONObject("idle")
            return Motion(
                springs = springs,
                kicks = kicks,
                fadeSeconds = json.getJSONObject("fade").getDouble("seconds"),
                pressKick = press.getDouble("kick"),
                pressSquash = press.getDouble("squash"),
                pressBulge = press.getDouble("bulge"),
                pressHold = press.getDouble("hold"),
                staggerSeconds = json.getJSONObject("stagger").getDouble("seconds"),
                idleBobMetres = idle.getDouble("bobMetres"),
                idleBobSeconds = idle.getDouble("bobSeconds"),
            )
        }
    }
}
