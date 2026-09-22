import Foundation
import RealityKit
import UIKit

/// The four effect shaders (ADR 0007), added to ADR 0006's world / toon / flat / sky — RealityKit shader
/// graphs that are the twins of Android's fx_*.mat, formula for formula (fx_common.glsl):
///
/// - **FxLit** — the world shader's formula, the vertex moved by its motion (sway or orbit);
/// - **FxGlow** — palette colour × pulse, unlit, moved by its motion;
/// - **FxSoft** — palette colour × w² × opacity × pulse, premultiplied; `Additive` 1 adds it (opacity 0
///   over premultiplied colour), 0 blends it;
/// - **FxParticle** — sprites turned to the camera, travelling, wobbling, pulsing in size.
///
/// All run on RealityKit's own clock (`ND_time_float`): nothing is set per frame. The asset's meshes
/// are in Blender's frame under a root turned −90° about X (worldkit.export_usdz), so object space is
/// (x, −z, y) of the game's; the graphs turn positions into the game's frame, move them there — the
/// same numbers as on Android — and turn the offset back.
@MainActor
enum FxMaterials {
    struct Set {
        let lit: ShaderGraphMaterial
        let glow: ShaderGraphMaterial
        let soft: ShaderGraphMaterial
        let particle: ShaderGraphMaterial
    }

    private static var loaded: Set?

    static func load() async throws -> Set {
        if let loaded { return loaded }
        let url = try write()
        do {
            let set = Set(lit: try await ShaderGraphMaterial(named: "/Root/FxLit", from: url),
                          glow: try await ShaderGraphMaterial(named: "/Root/FxGlow", from: url),
                          soft: try await ShaderGraphMaterial(named: "/Root/FxSoft", from: url),
                          particle: try await ShaderGraphMaterial(named: "/Root/FxParticle", from: url))
            loaded = set
            return set
        } catch {
            throw AssetError.missing("the effect shaders (\(url.lastPathComponent)): \(error)")
        }
    }

    private static func write() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("effects", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let white = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        guard let png = white.pngData() else { throw AssetError.missing("a white pixel") }
        try png.write(to: dir.appendingPathComponent("white.png"))
        let url = dir.appendingPathComponent("effects.usda")
        try usda.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static var usda: String {
        let graphs = [lit(), glow(), soft(), particle()].map(\.usda).joined(separator: "\n\n")
        let body = graphs.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
        return """
            #usda 1.0
            (
                defaultPrim = "Root"
                metersPerUnit = 1
                upAxis = "Y"
            )

            def Xform "Root"
            {
            \(body)
            }

            """
    }

    // MARK: shared pieces (fx_common.glsl)

    /// (w, p) from the swatch the UV sits in: fract(u·32), fract((1 − v)·32), each over 0.05…0.95.
    private static func data(_ g: FxGraph) -> (w: FxGraph.Value, p: FxGraph.Value) {
        let uv = g.separate(g.texcoord())
        let fu = g.fract(g.mul(uv[0], 32))
        let fv = g.fract(g.mul(g.sub(g.c(1), uv[1]), 32))
        return (g.mul(g.add(fu, -0.05), 1 / 0.9), g.mul(g.add(fv, -0.05), 1 / 0.9))
    }

    /// Object space (Blender's frame) → the game's frame, and an offset back.
    private static func toGame(_ g: FxGraph, _ v: FxGraph.Value) -> FxGraph.Value {
        let c = g.separate(v)
        return g.vec(c[0], c[2], g.mul(c[1], -1))
    }

    private static func toObject(_ g: FxGraph, _ v: FxGraph.Value) -> FxGraph.Value {
        let c = g.separate(v)
        return g.vec(c[0], g.mul(c[2], -1), c[1])
    }

    private static func pulse(_ g: FxGraph, _ t: FxGraph.Value, _ p: FxGraph.Value) -> FxGraph.Value {
        let amp = g.separate(g.param("PulseAmp", .vector3))
        let rate = g.separate(g.param("PulseRate", .vector3))
        let ph = g.mul(p, 2 * .pi)
        let s1 = g.sin(g.add(g.mul(rate[0], t), ph))
        let s2 = g.sin(g.add(g.mul(rate[1], t), g.mul(ph, 1.7)))
        return g.add(amp[0], g.add(g.mul(amp[1], s1), g.mul(amp[2], s2)))
    }

    /// fxMotion: the orbit, then the sway; `soft` — the weight is 1 (w is the falloff there).
    private static func motion(_ g: FxGraph, _ t: FxGraph.Value, _ w: FxGraph.Value, _ p: FxGraph.Value) {
        let pos = toGame(g, g.position())
        let swayAmp = g.param("SwayAmp", .vector3), swayRate = g.param("SwayRate", .float)
        let orbit = g.param("Orbit", .float), spin = g.param("Spin", .float)
        let pivot = g.separate(g.param("Pivot", .vector3)), ellipse = g.param("Ellipse", .float)
        let k = g.mix(g.c(1), g.add(g.mul(w, 2), -1), orbit)
        let s = g.mix(w, g.c(1), orbit)
        let theta = g.mul(g.mul(spin, k), t)
        let q = g.separate(pos)
        let dx = g.sub(q[0], pivot[0]), dz = g.sub(q[2], pivot[2])
        let qz = g.div(dz, ellipse)
        let c = g.cos(theta), sn = g.sin(theta)
        let ox = g.sub(g.sub(g.mul(dx, c), g.mul(qz, sn)), dx)
        let oz = g.sub(g.mul(g.add(g.mul(dx, sn), g.mul(qz, c)), ellipse), dz)
        let wt = g.mul(swayRate, t), ph = g.mul(p, 2 * .pi)
        let s1 = g.sin(g.add(wt, ph))
        let s2 = g.sin(g.add(g.mul(wt, 2.45), g.mul(ph, 1.9)))
        let c1 = g.cos(g.add(g.mul(wt, 0.82), g.mul(ph, 1.3)))
        let a = g.add(g.mul(s1, 0.77), g.mul(s2, 0.23))
        let b = g.add(g.mul(c1, 0.77), g.mul(s2, 0.23))
        let sway = g.mul(g.mul(swayAmp, g.vec(a, a, b)), s)
        let offset = g.add(g.vec(ox, g.c(0), oz), sway)
        g.vertexOffset(toObject(g, offset))
    }

    // MARK: the four graphs

    private static func lit() -> FxGraph {
        let g = FxGraph("FxLit")
        let file = g.texture("Palette")
        let v = data(g)
        motion(g, g.time(), v.w, v.p)                 // the vertex stage's own nodes
        let t = g.time(), d = data(g)                  // the surface's
        let n = g.worldNormal()
        let sky = g.param("Sky", .color3), ground = g.param("Ground", .color3), sun = g.param("Sun", .color3)
        let dir = g.param("SunDirection", .vector3)
        let hemi = g.mix(ground, sky, g.add(g.mul(g.separate(n)[1], 0.5), 0.5))
        let light = g.add(hemi, g.mul(sun, g.max(g.dot(n, dir), 0)))
        let albedo = g.palette(file, g.texcoord())
        g.surface(colour: g.mul(g.mul(albedo, light), pulse(g, t, d.p)), opacity: nil, premultiplied: false)
        return g
    }

    private static func glow() -> FxGraph {
        let g = FxGraph("FxGlow")
        let file = g.texture("Palette")
        let v = data(g)
        motion(g, g.time(), v.w, v.p)                 // the vertex stage's own nodes
        let t = g.time(), d = data(g)                  // the surface's
        g.surface(colour: g.mul(g.palette(file, g.texcoord()), pulse(g, t, d.p)), opacity: nil, premultiplied: false)
        return g
    }

    private static func soft() -> FxGraph {
        let g = FxGraph("FxSoft")
        let file = g.texture("Palette")
        motion(g, g.time(), g.c(1), data(g).p)
        let t = g.time(), d = data(g)
        let w = g.clamp(d.w, 0, 1)
        let a = g.mul(g.mul(g.mul(w, w), g.param("Opacity", .float)), g.max(pulse(g, t, d.p), 0))
        let cover = g.sub(g.c(1), g.param("Additive", .float))
        g.surface(colour: g.mul(g.palette(file, g.texcoord()), a), opacity: g.mul(a, cover), premultiplied: true)
        return g
    }

    private static func particle() -> FxGraph {
        let g = FxGraph("FxParticle")
        let file = g.texture("Palette")
        let t = g.time(), d = data(g)                  // the vertex stage's
        let size = g.param("Size", .float), spread = g.param("SizeSpread", .float)
        let travel = g.param("Travel", .vector3), wrap = g.param("Wrap", .float)
        let wobble = g.param("Wobble", .vector3), wobbleRate = g.param("WobbleRate", .float)
        // fxParticle: corner, spawn point, its hashes
        let qx = g.ifGreater(d.w, 0.5, g.c(1), g.c(-1)), qy = g.ifGreater(d.p, 0.5, g.c(1), g.c(-1))
        let pos = toGame(g, g.position())
        let c = g.sub(pos, g.vec(g.mul(qx, size), g.c(0), g.mul(qy, size)))
        let r0 = g.fract(g.dot(c, g.constant3(12.9898, 78.233, 37.719)))
        let r1 = g.fract(g.dot(c, g.constant3(39.346, 11.135, 83.155)))
        let r2 = g.fract(g.dot(c, g.constant3(71.37, 27.91, 53.17)))
        let sp = g.add(g.mul(r1, 0.8), 0.6)
        let len = g.length(travel)
        let f = g.fract(g.add(g.div(g.mul(g.mul(len, sp), t), g.max(wrap, 0.001)), r0))
        let off = g.mul(g.mul(travel, g.div(g.c(1), g.max(len, 0.0001))), g.mul(f, wrap))
        let ends = g.mul(g.smoothstep(0, 0.1, f), g.sub(g.c(1), g.smoothstep(0.8, 1, f)))
        let fade = g.ifGreater(wrap, 0, ends, g.c(1))
        let ph = g.mul(r0, 2 * .pi)
        let tt = g.add(g.mul(g.mul(t, wobbleRate), sp), ph)
        let wob = g.mul(wobble, g.vec(
            g.add(g.mul(g.sin(tt), 0.56), g.mul(g.sin(g.add(g.mul(tt, 0.37), ph)), 0.44)),
            g.sin(g.add(g.mul(tt, 0.8), ph)),
            g.add(g.mul(g.cos(g.mul(tt, 0.9)), 0.56), g.mul(g.cos(g.add(g.mul(tt, 0.29), ph)), 0.44))))
        let b = g.clamp(pulse(g, t, r2), 0, 2)
        let s = g.mul(g.mul(g.mul(size, g.add(g.mul(spread, g.add(g.mul(r1, 2), -1)), 1)), b), fade)
        let cc = g.add(g.add(c, off), wob)
        let fwd = g.normalize(g.sub(toGame(g, g.cameraPosition()), cc))
        let right = g.normalize(g.cross(g.constant3(0, 1, 0), fwd))
        let up = g.cross(fwd, right)
        let corner = g.mul(g.add(g.mul(right, qx), g.mul(up, qy)), s)
        g.vertexOffset(toObject(g, g.sub(g.add(cc, corner), pos)))
        // fxDisc, on the surface's own nodes
        let ds = data(g)
        let e = g.sub(g.vec(g.mul(ds.w, 2), g.mul(ds.p, 2), g.c(0)), g.constant3(1, 1, 0))
        let disc = g.sub(g.c(1), g.smoothstep(0.1, 1, g.length(e)))
        let a = g.mul(g.mul(disc, disc), g.param("Opacity", .float))
        let cover = g.sub(g.c(1), g.param("Additive", .float))
        g.surface(colour: g.mul(g.palette(file, g.texcoord()), a), opacity: g.mul(a, cover), premultiplied: true)
        return g
    }
}
