import Foundation

/// A small builder for RealityKit shader graphs written as USD (MaterialX nodes, as Reality Composer Pro
/// saves them): each call adds one node and returns its output, so a graph reads like the GLSL it twins
/// (android/app/src/main/materials/fx_common.glsl). Only what the effect graphs need (ADR 0007).
final class FxGraph {
    enum Kind: String {
        case float, vector2, vector3, color3, token

        var usd: String {
            switch self {
            case .float: "float"
            case .vector2: "float2"
            case .vector3: "float3"
            case .color3: "color3f"
            case .token: "token"
            }
        }
    }

    struct Value {
        let ref: String
        let kind: Kind
    }

    enum Arg {
        case v(Value)
        case f(Float)
        case v3(Float, Float, Float)
        case s(String)
        case i(Int)
        case b(Bool)
    }

    let name: String
    private var path: String { "/Root/\(name)" }
    private var interface: [String] = []
    private var nodes: [String] = []
    private var count = 0
    private var surface: String?
    private var vertex: String?

    init(_ name: String) { self.name = name }

    // MARK: the material's own inputs

    func param(_ id: String, _ kind: Kind) -> Value {
        let initial = kind == .float ? "0" : kind == .vector2 ? "(0, 0)" : "(0, 0, 0)"
        interface.append("\(kind.usd) inputs:\(id) = \(initial)")
        return Value(ref: "\(path).inputs:\(id)", kind: kind)
    }

    /// The palette texture input (a white pixel until a world's palette is bound).
    func texture(_ id: String) -> String {
        interface.append("asset inputs:\(id) = @white.png@")
        return "\(path).inputs:\(id)"
    }

    // MARK: nodes

    @discardableResult
    func node(_ id: String, _ out: Kind, _ ins: [(String, Arg)], outputs: [String] = ["out"]) -> [Value] {
        count += 1
        let n = "N\(count)"
        var lines = ["def Shader \"\(n)\"", "{", "    uniform token info:id = \"\(id)\""]
        for (input, arg) in ins {
            switch arg {
            case .v(let v): lines.append("    \(v.kind.usd) inputs:\(input).connect = <\(v.ref)>")
            case .f(let f): lines.append("    float inputs:\(input) = \(f)")
            case .v3(let x, let y, let z): lines.append("    float3 inputs:\(input) = (\(x), \(y), \(z))")
            case .s(let s): lines.append("    string inputs:\(input) = \"\(s)\"")
            case .i(let i): lines.append("    int inputs:\(input) = \(i)")
            case .b(let b): lines.append("    bool inputs:\(input) = \(b ? 1 : 0)")
            }
        }
        for o in outputs { lines.append("    \(out.usd) outputs:\(o)") }
        lines.append("}")
        nodes.append(lines.joined(separator: "\n"))
        return outputs.map { Value(ref: "\(path)/\(n).outputs:\($0)", kind: out) }
    }

    func c(_ f: Float) -> Value { node("ND_constant_float", .float, [("value", .f(f))])[0] }
    func time() -> Value { node("ND_time_float", .float, [])[0] }
    func texcoord() -> Value { node("ND_texcoord_vector2", .vector2, [("index", .i(0))])[0] }
    func position() -> Value { node("ND_position_vector3", .vector3, [("space", .s("object"))])[0] }
    func cameraPosition() -> Value { node("ND_realitykit_cameraposition_vector3", .vector3, [("space", .s("object"))])[0] }
    func worldNormal() -> Value {
        normalize(node("ND_normal_vector3", .vector3, [("space", .s("world"))])[0])
    }

    func separate(_ v: Value) -> [Value] {
        v.kind == .vector2
            ? node("ND_separate2_vector2", .float, [("in", .v(v))], outputs: ["outx", "outy"])
            : node("ND_separate3_vector3", .float, [("in", .v(v))], outputs: ["outx", "outy", "outz"])
    }

    func vec(_ x: Value, _ y: Value, _ z: Value) -> Value {
        node("ND_combine3_vector3", .vector3, [("in1", .v(x)), ("in2", .v(y)), ("in3", .v(z))])[0]
    }

    private func binary(_ op: String, _ a: Value, _ b: Value) -> Value {
        let suffix: String
        switch (a.kind, b.kind) {
        case (.float, .float): suffix = "float"
        case (.vector3, .vector3): suffix = "vector3"
        case (.color3, .color3): suffix = "color3"
        case (.vector3, .float): suffix = "vector3FA"
        case (.color3, .float): suffix = "color3FA"
        default: preconditionFailure("\(op): \(a.kind) with \(b.kind)")
        }
        return node("ND_\(op)_\(suffix)", a.kind, [("in1", .v(a)), ("in2", .v(b))])[0]
    }

    func add(_ a: Value, _ b: Value) -> Value { binary("add", a, b) }
    func sub(_ a: Value, _ b: Value) -> Value { binary("subtract", a, b) }
    func mul(_ a: Value, _ b: Value) -> Value { binary("multiply", a, b) }
    func div(_ a: Value, _ b: Value) -> Value { binary("divide", a, b) }
    func add(_ a: Value, _ b: Float) -> Value { add(a, c(b)) }
    func mul(_ a: Value, _ b: Float) -> Value { mul(a, c(b)) }

    private func unary(_ op: String, _ a: Value) -> Value {
        node("ND_\(op)_\(a.kind.rawValue)", a.kind, [("in", .v(a))])[0]
    }

    func sin(_ a: Value) -> Value { unary("sin", a) }
    func cos(_ a: Value) -> Value { unary("cos", a) }
    func normalize(_ a: Value) -> Value { unary("normalize", a) }
    func length(_ a: Value) -> Value { node("ND_magnitude_vector3", .float, [("in", .v(a))])[0] }
    /// GLSL's fract: x − floor(x), also for negative x.
    func fract(_ a: Value) -> Value { node("ND_modulo_float", .float, [("in1", .v(a)), ("in2", .f(1))])[0] }
    func max(_ a: Value, _ b: Float) -> Value { node("ND_max_float", .float, [("in1", .v(a)), ("in2", .f(b))])[0] }
    func clamp(_ a: Value, _ lo: Float, _ hi: Float) -> Value {
        node("ND_clamp_float", .float, [("in", .v(a)), ("low", .f(lo)), ("high", .f(hi))])[0]
    }
    func smoothstep(_ lo: Float, _ hi: Float, _ x: Value) -> Value {
        node("ND_smoothstep_float", .float, [("in", .v(x)), ("low", .f(lo)), ("high", .f(hi))])[0]
    }
    /// GLSL's mix(a, b, t) = a·(1 − t) + b·t.
    func mix(_ a: Value, _ b: Value, _ t: Value) -> Value {
        node("ND_mix_\(a.kind.rawValue)", a.kind, [("fg", .v(b)), ("bg", .v(a)), ("mix", .v(t))])[0]
    }
    /// x > edge ? a : b
    func ifGreater(_ x: Value, _ edge: Float, _ a: Value, _ b: Value) -> Value {
        node("ND_ifgreater_float", .float, [("value1", .v(x)), ("value2", .f(edge)), ("in1", .v(a)), ("in2", .v(b))])[0]
    }
    func dot(_ a: Value, _ b: Value) -> Value {
        node("ND_dotproduct_vector3", .float, [("in1", .v(a)), ("in2", .v(b))])[0]
    }
    func cross(_ a: Value, _ b: Value) -> Value {
        node("ND_crossproduct_vector3", .vector3, [("in1", .v(a)), ("in2", .v(b))])[0]
    }
    func constant3(_ x: Float, _ y: Float, _ z: Float) -> Value {
        node("ND_constant_vector3", .vector3, [("value", .v3(x, y, z))])[0]
    }

    /// The palette's colour at `uv`, nearest-sampled like the world's.
    func palette(_ file: String, _ uv: Value) -> Value {
        count += 1
        let n = "N\(count)"
        nodes.append("""
            def Shader "\(n)"
            {
                uniform token info:id = "ND_image_color3"
                asset inputs:file.connect = <\(file)>
                string inputs:filtertype = "closest"
                float2 inputs:texcoord.connect = <\(uv.ref)>
                string inputs:uaddressmode = "clamp"
                string inputs:vaddressmode = "clamp"
                color3f outputs:out
            }
            """)
        return Value(ref: "\(path)/\(n).outputs:out", kind: .color3)
    }

    // MARK: the two stages

    /// The unlit surface, tone mapping off (ADR 0006); `premultiplied` for the blended effects.
    func surface(colour: Value, opacity: Value?, premultiplied: Bool) {
        var ins: [(String, Arg)] = [("applyPostProcessToneMap", .b(false)), ("color", .v(colour)), ("hasPremultipliedAlpha", .b(premultiplied))]
        ins.append(("opacity", opacity.map { .v($0) } ?? .f(1)))
        let out = node("ND_realitykit_unlit_surfaceshader", .token, ins)[0]
        surface = out.ref
    }

    /// The geometry modifier: this offset (object space) added to every vertex.
    func vertexOffset(_ offset: Value) {
        count += 1
        let n = "N\(count)"
        nodes.append("""
            def Shader "\(n)"
            {
                uniform token info:id = "ND_realitykit_geometrymodifier_vertexshader"
                float3 inputs:modelPositionOffset.connect = <\(offset.ref)>
                token outputs:out
            }
            """)
        vertex = "\(path)/\(n).outputs:out"
    }

    var usda: String {
        guard let surfaceRef = surface else { preconditionFailure("\(name) has no surface") }
        var lines = ["def Material \"\(name)\"", "{"]
        lines += interface.map { "    " + $0 }
        lines.append("    token outputs:mtlx:surface.connect = <\(surfaceRef)>")
        lines.append(vertex.map { "    token outputs:realitykit:vertex.connect = <\($0)>" } ?? "    token outputs:realitykit:vertex")
        for n in nodes {
            lines += n.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
