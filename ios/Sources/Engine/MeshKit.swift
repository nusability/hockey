import RealityKit
import simd

/// Flat-shaded low-poly geometry built from primitives — the twin of Android's MeshKit, same shapes
/// and facet counts, so a figure is the same figure on both platforms. Each triangle carries its
/// face normal (the worlds are faceted too). Parts are grouped by material slot: one mesh part per
/// slot, drawn with the slot's material.
struct MeshKit {
    private var slots: [Int: (positions: [SIMD3<Float>], normals: [SIMD3<Float>])] = [:]
    /// Applied to everything added until it changes.
    var transform = matrix_identity_float4x4
    var slot = 0

    /// A triangle, counter-clockwise seen from its front; its normal follows the winding.
    mutating func triangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
        let pa = point(a), pb = point(b), pc = point(c)
        let n = simd_cross(pb - pa, pc - pa)
        let len = simd_length(n)
        guard len > 1e-9 else { return }
        var entry = slots[slot] ?? ([], [])
        entry.positions += [pa, pb, pc]
        let unit = n / len
        entry.normals += [unit, unit, unit]
        slots[slot] = entry
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>) {
        triangle(a, b, c)
        triangle(a, c, d)
    }

    private func point(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let v = transform * SIMD4(p, 1)
        return SIMD3(v.x, v.y, v.z)
    }

    // MARK: primitives (counter-clockwise seen from outside)

    /// A box centred on `c`.
    mutating func box(_ c: SIMD3<Float>, _ size: SIMD3<Float>) {
        let h = size / 2
        func v(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { c + SIMD3(x * h.x, y * h.y, z * h.z) }
        quad(v(-1, -1, 1), v(1, -1, 1), v(1, 1, 1), v(-1, 1, 1))       // +z
        quad(v(1, -1, -1), v(-1, -1, -1), v(-1, 1, -1), v(1, 1, -1))   // −z
        quad(v(-1, 1, 1), v(1, 1, 1), v(1, 1, -1), v(-1, 1, -1))       // +y
        quad(v(-1, -1, -1), v(1, -1, -1), v(1, -1, 1), v(-1, -1, 1))   // −y
        quad(v(1, -1, 1), v(1, -1, -1), v(1, 1, -1), v(1, 1, 1))       // +x
        quad(v(-1, -1, -1), v(-1, -1, 1), v(-1, 1, 1), v(-1, 1, -1))   // −x
    }

    /// A frustum along +y from `y0` (radius `r0`) to `y1` (radius `r1`), centred on x, z; capped.
    /// A cone has `r1 = 0`, a cylinder `r0 = r1`.
    mutating func frustum(x: Float = 0, z: Float = 0, y0: Float, y1: Float, r0: Float, r1: Float, segments: Int) {
        func ring(_ i: Int, _ r: Float, _ y: Float) -> SIMD3<Float> {
            let a = Float(i) / Float(segments) * 2 * .pi
            return SIMD3(x + r * sin(a), y, z + r * cos(a))
        }
        let top = SIMD3<Float>(x, y1, z), bottom = SIMD3<Float>(x, y0, z)
        for i in 0..<segments {
            let a0 = ring(i, r0, y0), b0 = ring(i + 1, r0, y0), a1 = ring(i, r1, y1), b1 = ring(i + 1, r1, y1)
            if r1 > 0 { quad(a0, b0, b1, a1) } else { triangle(a0, b0, top) }
            if r1 > 0 { triangle(top, a1, b1) }
            triangle(bottom, b0, a0)
        }
    }

    /// A faceted sphere; `upper` keeps only the top half (a dome), capped flat.
    mutating func sphere(_ c: SIMD3<Float>, radius r: Float, rings: Int, segments: Int, upper: Bool = false) {
        func p(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let theta = Float(i) / Float(rings) * .pi           // 0 at the top
            let phi = Float(j) / Float(segments) * 2 * .pi
            return c + r * SIMD3(sin(theta) * sin(phi), cos(theta), sin(theta) * cos(phi))
        }
        let last = upper ? rings / 2 : rings
        for i in 0..<last {
            for j in 0..<segments {
                let a = p(i, j), b = p(i + 1, j), cc = p(i + 1, j + 1), d = p(i, j + 1)
                if i == 0 { triangle(a, b, cc) } else if i == rings - 1 { triangle(a, b, d) } else { quad(a, b, cc, d) }
            }
        }
        if upper {
            for j in 0..<segments { triangle(c, p(last, j + 1), p(last, j)) }
        }
    }

    /// A flat ring on the ground plane (y = `y`), facing up.
    mutating func annulus(inner: Float, outer: Float, y: Float, segments: Int) {
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi, a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p = { (r: Float, a: Float) in SIMD3<Float>(r * sin(a), y, r * cos(a)) }
            quad(p(inner, a0), p(outer, a0), p(outer, a1), p(inner, a1))
        }
    }

    // MARK: output

    var usedSlots: [Int] { slots.keys.sorted() }

    /// One mesh part per slot, in slot order; part `k` uses material index `k` of `usedSlots`.
    @MainActor
    func resource() throws -> MeshResource {
        var parts: [MeshDescriptor] = []
        for (k, s) in usedSlots.enumerated() {
            let e = slots[s]!
            var d = MeshDescriptor(name: "slot\(s)")
            d.positions = MeshBuffers.Positions(e.positions)
            d.normals = MeshBuffers.Normals(e.normals)
            d.primitives = .triangles(Array(0..<UInt32(e.positions.count)))
            d.materials = .allFaces(UInt32(k))
            parts.append(d)
        }
        return try MeshResource.generate(from: parts)
    }
}

extension simd_float4x4 {
    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    static func rotation(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis)))
    }

    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s, 1))
    }
}
