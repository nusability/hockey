import RealityKit
import UIKit

/// A screen's layout plane: `frameDepth` in front of a camera pose, facing it, scaled so the
/// design width (`frameWidth`) spans the phone's visible width. Children are laid out in design
/// metres — x from −frameWidth/2 to +frameWidth/2, y from −halfHeight to +halfHeight — with the
/// safe-area insets the host reports already measured in (`top`, `bottom`).
///
/// A frame parented to the camera is the HUD rig (ADR 0005); a frame standing in the world at a
/// screen's camera pose is that screen's menu, and getting there is a camera move.
@MainActor
struct ScreenFrame {
    let entity = Entity()
    let halfWidth: Float
    let halfHeight: Float
    /// The highest y clear of the status bar / Dynamic Island, and the lowest clear of the home
    /// indicator, in design metres.
    let top: Float
    let bottom: Float
    /// The scale that fits the design width at the layout's field of view.
    private let fit: Float
    private let layoutFov: Float

    init(fovDegrees: Float, viewSize: CGSize, insets: UIEdgeInsets) {
        let depth = DesignTokens.Size.frameDepth
        let aspect = Float(viewSize.width / max(viewSize.height, 1))
        let visibleHalfH = depth * tan(fovDegrees / 2 * .pi / 180)
        let visibleHalfW = visibleHalfH * aspect
        halfWidth = DesignTokens.Size.frameWidth / 2
        let k = visibleHalfW / halfWidth
        halfHeight = visibleHalfH / k
        let perPoint = 2 * halfHeight / Float(max(viewSize.height, 1))
        top = halfHeight - Float(insets.top) * perPoint
        bottom = -halfHeight + Float(insets.bottom) * perPoint
        fit = k
        layoutFov = fovDegrees
        entity.scale = SIMD3(repeating: k)
        entity.position.z = -depth
    }

    /// For the HUD rig: keeps the layout the same size on screen while the camera's field of view
    /// breathes (the match camera, §8.6) — the visible plane grows with tan(fov / 2).
    func zoom(fovDegrees: Float) {
        let z = tan(fovDegrees / 2 * .pi / 180) / tan(layoutFov / 2 * .pi / 180)
        let s = SIMD3<Float>(repeating: fit * z)
        if entity.scale != s { entity.scale = s }
    }

    /// Stands this frame in the world in front of `camera` (a world transform), facing it.
    func stand(before camera: Transform, in parent: Entity) {
        parent.addChild(entity)
        let forward = camera.rotation.act(SIMD3<Float>(0, 0, -1))
        entity.position = camera.translation + forward * DesignTokens.Size.frameDepth
        entity.orientation = camera.rotation
    }
}
