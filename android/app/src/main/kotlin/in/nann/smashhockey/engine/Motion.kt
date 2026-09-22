package `in`.nann.smashhockey.engine

/**
 * The motion vocabulary (ADR 0005, `shared/data/motion.json`): named springs and fades that both
 * platforms read, integrated identically, so a bounce on Android is the bounce on iOS.
 */
data class SpringToken(val stiffness: Double, val damping: Double)

data class MotionTokens(
    val bouncy: SpringToken,
    val soft: SpringToken,
    val fadeSeconds: Double,
    val pressKick: Double,
    val pressSquash: Double,
    val pressBulge: Double,
) {
    companion object {
        fun load(assets: Assets): MotionTokens {
            val json = assets.json("motion.json")
            val spring = json.getJSONObject("spring")
            fun token(name: String) = spring.getJSONObject(name).let {
                SpringToken(it.getDouble("stiffness"), it.getDouble("damping"))
            }
            val press = json.getJSONObject("press")
            return MotionTokens(
                bouncy = token("bouncy"),
                soft = token("soft"),
                fadeSeconds = json.getJSONObject("fade").getDouble("seconds"),
                pressKick = press.getDouble("kick"),
                pressSquash = press.getDouble("squash"),
                pressBulge = press.getDouble("bulge"),
            )
        }
    }
}

/**
 * A damped spring toward [target], integrated with semi-implicit Euler in fixed 1/240 s substeps —
 * the same equations, step and API as iOS's `Spring` (snap, settle), so a curve can be pinned by
 * a golden vector. The one spring of the app: the match's HUD and the UI kit both run on it.
 */
class Spring(val token: SpringToken, initial: Double = 0.0) {
    var value = initial
        private set
    var velocity = 0.0
    var target = initial
    private var carry = 0.0

    fun kick(impulse: Double) { velocity += impulse }

    /** Jumps to [v] and stops there — Reduce Motion, or restarting a one-shot move. */
    fun snap(v: Double) {
        value = v
        target = v
        velocity = 0.0
        carry = 0.0
    }

    /** At rest on its target (to well below anything visible). */
    val isSettled: Boolean get() = kotlin.math.abs(value - target) < 1e-3 && kotlin.math.abs(velocity) < 1e-2

    fun advance(dt: Double) {
        carry += dt
        while (carry >= STEP) {
            val a = -token.stiffness * (value - target) - token.damping * velocity
            velocity += a * STEP
            value += velocity * STEP
            carry -= STEP
        }
    }

    companion object { const val STEP = 1.0 / 240.0 }
}
