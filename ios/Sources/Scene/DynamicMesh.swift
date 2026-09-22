import Metal
import RealityKit

/// A mesh whose vertices move every frame — the ball's trail, the rippling net (spec §8.8) — on
/// RealityKit's `LowLevelMesh` (iOS 18): positions and one texture coordinate per vertex, written in
/// place; the triangles are fixed at creation. The twin of Android's dynamic vertex buffers.
@MainActor
final class DynamicMesh {
    struct Vertex {
        var position: SIMD3<Float>
        var uv: SIMD2<Float>
    }

    let resource: MeshResource
    private let mesh: LowLevelMesh
    let vertexCount: Int

    /// `triangles`: vertex indices, three per triangle. `bounds`: where the vertices will ever be.
    init(vertexCount: Int, triangles: [UInt16], bounds: BoundingBox) throws {
        var d = LowLevelMesh.Descriptor()
        d.vertexCapacity = vertexCount
        d.indexCapacity = triangles.count
        d.indexType = .uint16
        d.vertexAttributes = [
            .init(semantic: .position, format: .float3, offset: MemoryLayout<Vertex>.offset(of: \.position)!),
            .init(semantic: .uv0, format: .float2, offset: MemoryLayout<Vertex>.offset(of: \.uv)!),
        ]
        d.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)]
        mesh = try LowLevelMesh(descriptor: d)
        self.vertexCount = vertexCount
        mesh.withUnsafeMutableIndices { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for (i, t) in triangles.enumerated() { out[i] = t }
        }
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            let out = raw.bindMemory(to: Vertex.self)
            for i in 0..<vertexCount { out[i] = Vertex(position: .zero, uv: .zero) }
        }
        mesh.parts.replaceAll([LowLevelMesh.Part(indexCount: triangles.count, topology: .triangle, bounds: bounds)])
        resource = try MeshResource(from: mesh)
    }

    /// Rewrites every vertex.
    func write(_ body: (UnsafeMutableBufferPointer<Vertex>) -> Void) {
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in body(raw.bindMemory(to: Vertex.self)) }
    }

    /// Two triangles per cell of a grid `columns` × `rows` cells, its vertices row by row.
    static func grid(columns: Int, rows: Int) -> [UInt16] {
        var t: [UInt16] = []
        for r in 0..<rows {
            for c in 0..<columns {
                let a = UInt16(r * (columns + 1) + c), b = a + 1, d = a + UInt16(columns + 1), e = d + 1
                t += [a, d, b, b, d, e]
            }
        }
        return t
    }
}
