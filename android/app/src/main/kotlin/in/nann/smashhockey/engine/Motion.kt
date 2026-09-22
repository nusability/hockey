package `in`.nann.smashhockey.engine

/**
 * The motion vocabulary (ADR 0005, `shared/data/motion.json`): named springs and fades that both
 * platforms read, integrated identically, so a bounce on Android is the bounce on iOS. The spring
 * itself and the presence it drives are the core's, so one test pins both apps' motion; this file is
 * the app's end of it — the tokens, read from the assets.
 */
typealias SpringToken = `in`.nann.smashhockey.core.feel.SpringToken
typealias Spring = `in`.nann.smashhockey.core.feel.Spring

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
