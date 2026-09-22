import RealityKit
import simd

/// Where the camera stands for a screen, and what it looks at.
struct CameraPose: Equatable {
    var eye: SIMD3<Float>
    var target: SIMD3<Float>
}

/// The one camera, and how it gets between screens: a swoop along an arc on the `swoop` spring
/// — up and over, a little roll into the turn, a little overshoot on arrival. Interrupt it and
/// the next swoop starts from wherever the camera is. Under Reduce Motion it cuts.
@MainActor
final class CameraRig {
    let camera = PerspectiveCamera()
    let fovDegrees: Float = 50
    private var from: CameraPose
    private var to: CameraPose
    private var progress: Spring
    private var arc: Float = 0
    private var roll: Float = 0
    private(set) var pose: CameraPose

    init(_ pose: CameraPose, motion: MotionTokens) {
        from = pose
        to = pose
        self.pose = pose
        progress = Spring(motion.spring(.swoop), initial: 1)
        camera.camera.fieldOfViewInDegrees = fovDegrees
        camera.camera.fieldOfViewOrientation = .vertical
        camera.camera.near = 0.1
        camera.camera.far = 500
        place(pose, roll: 0)
    }

    /// Screens further apart swoop higher; `roll` tilts the horizon into the turn (radians).
    func swoop(to pose: CameraPose, arc: Float? = nil, roll: Float = 0.1) {
        from = self.pose
        to = pose
        self.arc = arc ?? min(8, simd_distance(from.eye, to.eye) * 0.25)
        let turning = simd_cross(from.target - from.eye, to.target - to.eye).y
        self.roll = turning >= 0 ? roll : -roll
        progress.snap(to: 0)
        progress.target = 1
    }

    var isMoving: Bool { !progress.isSettled }

    func update(_ dt: Double, reduceMotion: Bool) {
        if reduceMotion { progress.snap(to: 1) } else { progress.advance(dt) }
        let p = Float(progress.value)
        let bump = 4 * p * (1 - p)
        var eye = simd_mix(from.eye, to.eye, SIMD3(repeating: p))
        eye.y += arc * max(0, bump)
        let target = simd_mix(from.target, to.target, SIMD3(repeating: p))
        pose = CameraPose(eye: eye, target: target)
        place(pose, roll: roll * bump)
    }

    private func place(_ pose: CameraPose, roll: Float) {
        camera.look(at: pose.target, from: pose.eye, relativeTo: nil)
        if roll != 0 { camera.orientation = camera.orientation * simd_quatf(angle: roll, axis: [0, 0, 1]) }
    }

    /// Where the camera would be with `pose` — for building a screen's frame before it arrives.
    func transform(at pose: CameraPose) -> Transform {
        let probe = Entity()
        probe.look(at: pose.target, from: pose.eye, relativeTo: nil)
        return probe.transform
    }
}
