package `in`.nann.smashhockey.ui

import kotlin.math.tan

/**
 * A screen's layout plane — the twin of iOS's `ScreenFrame`: [DesignTokens.Size.FRAME_DEPTH] in
 * front of a camera pose, facing it, scaled so the design width spans the phone's visible width.
 * Children are laid out in design metres — x from −halfWidth to +halfWidth, y from −halfHeight to
 * +halfHeight — with the safe-area insets already measured in ([top], [bottom]).
 *
 * A frame parented to the camera is the HUD rig (ADR 0005); a frame standing in the world at a
 * screen's camera pose is that screen's menu, and getting there is a camera move.
 */
class ScreenFrame(val node: UiNode, fovDegrees: Double, viewW: Int, viewH: Int, insetTop: Int, insetBottom: Int) {
    val halfWidth: Float
    val halfHeight: Float
    /** The highest y clear of the status bar / cutout, and the lowest clear of the gesture bar, in design metres. */
    val top: Float
    val bottom: Float

    init {
        val depth = DesignTokens.Size.FRAME_DEPTH
        val aspect = viewW.toFloat() / maxOf(viewH, 1)
        val visibleHalfH = depth * tan(Math.toRadians(fovDegrees / 2)).toFloat()
        val visibleHalfW = visibleHalfH * aspect
        halfWidth = DesignTokens.Size.FRAME_WIDTH / 2
        val k = visibleHalfW / halfWidth
        halfHeight = visibleHalfH / k
        val perPixel = 2 * halfHeight / maxOf(viewH, 1)
        top = halfHeight - insetTop * perPixel
        bottom = -halfHeight + insetBottom * perPixel
        node.setScale(k)
        node.setPosition(0f, 0f, -depth)
    }

    /** Stands this frame in the world in front of [camera] (a world transform), facing it. */
    fun stand(camera: Xform) {
        val q = camera.rot
        // forward = rotate (0, 0, −1) by q
        val fx = -(2 * (q.x * q.z + q.w * q.y))
        val fy = -(2 * (q.y * q.z - q.w * q.x))
        val fz = -(1 - 2 * (q.x * q.x + q.y * q.y))
        val d = DesignTokens.Size.FRAME_DEPTH
        node.transform.tx = camera.tx + fx * d
        node.transform.ty = camera.ty + fy * d
        node.transform.tz = camera.tz + fz * d
        node.transform.rot.set(q)
        node.changed()
    }
}
