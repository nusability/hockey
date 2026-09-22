import CoreGraphics
import Foundation
import RealityKit

/// The match feedback's three shaders (spec §5.2, §8.8), RealityKit shader graphs built with the
/// effects' graph builder and ending in the unlit surface with tone mapping off (ADR 0006) — the
/// twins of Android's aim.mat, glow.mat and trail.mat, formula for formula:
///
/// - **Chevron** — the aim ribbon: chevrons printed along it from its own texture coordinates (u
///   metres from its start, v 0…1 across it — the mesh carries the taper), one every `chevron`
///   metres, scrolling outward on RealityKit's clock: `c = fract(u/chevron − scroll·t)`,
///   `s = 1 − |2v − 1|`, inside while `0.72 + 0.233·s − 0.281 < c < 0.72 + 0.233·s` (edges smoothed
///   by 0.02) and `s > 0.062`; colour at its opacity × that;
/// - **Glow** — a flat colour added to what is behind it (premultiplied, zero coverage);
/// - **Trail** — a flat colour at `Opacity` × the vertex's first texture coordinate;
/// - **Flat** — a flat colour at its opacity, the twin of Android's `flat.mat`: the arrowhead, the
///   lock-on's ring and its dots.
///
/// **Nothing here is written per frame.** Every graph but Trail computes its own beat —
/// `Opacity · (1 + Pulse · sin(t · Rate))` on RealityKit's clock — so a part that pulses or breathes
/// needs no material handed to it on a frame that changes neither its colour nor what it says.
/// That matters more on RealityKit than it reads: a material assigned into a `ModelComponent` is a
/// resource the renderer takes ownership of and does not give back, so a per-frame write is an
/// unbounded leak that ends with the part no longer drawn (SMASH-24). Android has the same rule for
/// a different reason — one `MaterialInstance` mutated in place (`Materials.flatOwned`).
@MainActor
enum FeelMaterials {
    struct Set {
        let chevron: ShaderGraphMaterial
        let glow: ShaderGraphMaterial
        let trail: ShaderGraphMaterial
        let flat: ShaderGraphMaterial
    }

    private static var loaded: Set?

    static func load() async throws -> Set {
        if let loaded { return loaded }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("feel", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("feel.usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        do {
            func graph(_ name: String) async throws -> ShaderGraphMaterial {
                var m = try await ShaderGraphMaterial(named: "/Root/\(name)", from: url)
                m.faceCulling = .none
                m.writesDepth = false
                return m
            }
            let set = Set(chevron: try await graph("Chevron"), glow: try await graph("Glow"),
                          trail: try await graph("Trail"), flat: try await graph("Flat"))
            loaded = set
            return set
        } catch {
            throw AssetError.missing("the feedback shaders (\(url.lastPathComponent)): \(error)")
        }
    }

    /// Sets a graph's `Colour` (sRGB 0xRRGGBB, handed over as the linear value the Android twin uses).
    static func colour(_ m: inout ShaderGraphMaterial, _ rgb: UInt32) {
        let c = Materials.linear(rgb)
        let cg = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                         components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), 1])!
        try? m.setParameter(name: "Colour", value: .color(cg))
    }

    static func set(_ m: inout ShaderGraphMaterial, _ name: String, _ v: Double) {
        try? m.setParameter(name: name, value: .float(Float(v)))
    }

    /// What a graph shows: `o · (1 + pulse · sin(t · rate))`, the beat run by the shader's own clock
    /// so the caller writes the material only when `o`, `pulse` or `rate` changes.
    static func opacity(_ m: inout ShaderGraphMaterial, _ o: Double, pulse: Double = 0, rate: Double = 0) {
        set(&m, "Opacity", o)
        set(&m, "Pulse", pulse)
        set(&m, "Rate", rate)
    }

    /// `Opacity · (1 + Pulse · sin(time · Rate))`.
    private static func beat(_ g: FxGraph) -> FxGraph.Value {
        let opacity = g.param("Opacity", .float), pulse = g.param("Pulse", .float), rate = g.param("Rate", .float)
        return g.mul(opacity, g.add(g.c(1), g.mul(pulse, g.sin(g.mul(g.time(), rate)))))
    }

    static var usda: String {
        let graphs = [chevron(), glow(), trail(), flat()].map(\.usda).joined(separator: "\n\n")
        return """
            #usda 1.0
            (
                defaultPrim = "Root"
                metersPerUnit = 1
                upAxis = "Y"
            )

            def Xform "Root"
            {
            \(graphs.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n"))
            }

            """
    }

    private static func chevron() -> FxGraph {
        let g = FxGraph("Chevron")
        let colour = g.param("Colour", .color3)
        let opacity = beat(g)
        let uv = g.separate(g.texcoord())
        let c = g.fract(g.sub(g.mul(uv[0], Float(1 / Presentation.Aim.chevron)),
                              g.mul(g.time(), Float(Presentation.Aim.scroll))))
        let centred = g.node("ND_absval_float", .float, [("in", .v(g.add(g.mul(uv[1], 2), -1)))])[0]
        let s = g.sub(g.c(1), centred)
        let top = g.add(g.mul(s, 0.233), 0.72)
        let bottom = g.add(top, -0.281)
        func step(_ edge: FxGraph.Value) -> FxGraph.Value {
            g.node("ND_smoothstep_float", .float, [("in", .v(c)), ("low", .v(g.add(edge, -0.02))), ("high", .v(g.add(edge, 0.02)))])[0]
        }
        let band = g.mul(step(bottom), g.sub(g.c(1), step(top)))
        let inside = g.ifGreater(s, 0.062, g.c(1), g.c(0))
        g.surface(colour: colour, opacity: g.mul(g.mul(band, inside), opacity), premultiplied: false)
        return g
    }

    private static func glow() -> FxGraph {
        let g = FxGraph("Glow")
        let colour = g.param("Colour", .color3)
        g.surface(colour: g.mul(colour, beat(g)), opacity: g.c(0), premultiplied: true)
        return g
    }

    private static func flat() -> FxGraph {
        let g = FxGraph("Flat")
        let colour = g.param("Colour", .color3)
        g.surface(colour: colour, opacity: beat(g), premultiplied: false)
        return g
    }

    private static func trail() -> FxGraph {
        let g = FxGraph("Trail")
        let colour = g.param("Colour", .color3), opacity = g.param("Opacity", .float)
        let uv = g.separate(g.texcoord())
        g.surface(colour: colour, opacity: g.mul(opacity, uv[0]), premultiplied: false)
        return g
    }
}
