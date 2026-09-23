// swift-tools-version: 6.0
// SmashCore: the game's platform-independent core on iOS — the generated config (shared/data/),
// the deterministic math and the match simulation (Match/). No UIKit, no RealityKit: it builds and tests
// on the Mac with `swift test`, and the app links it (ios/project.yml `packages:`).
import PackageDescription

let package = Package(
    name: "SmashCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SmashCore", targets: ["SmashCore"]),
    ],
    targets: [
        .target(name: "SmashCore"),
        // Records shared/vectors/math/ (spec §4.7). Not linked by the app.
        .executableTarget(name: "RecordVectors", dependencies: ["SmashCore"]),
        // Records shared/vectors/season/ (spec §2.2, §11, §15). Not linked by the app.
        .executableTarget(name: "RecordSeasonVectors", dependencies: ["SmashCore"]),
        // Records shared/vectors/match/ (spec §4.7) with scripted and bot-played input tapes.
        .executableTarget(name: "RecordMatchVectors", dependencies: ["SmashCore"]),
        // Records shared/vectors/telemetry/ (spec §17). Not linked by the app.
        .executableTarget(name: "RecordTelemetryVectors", dependencies: ["SmashCore"]),
        // Measures automatic play over a sweep of seeded matches (spec §7). Not linked by the app.
        .executableTarget(name: "MeasureMatches", dependencies: ["SmashCore"]),
        .testTarget(name: "SmashCoreTests", dependencies: ["SmashCore"]),
    ],
    swiftLanguageModes: [.v6]
)
