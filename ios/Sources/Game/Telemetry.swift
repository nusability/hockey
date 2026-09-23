import Foundation
import SmashCore
import os

/// The sending half of spec §18 on iOS: the configuration, the queue's owner and the one place a
/// request exists. The Android twin is `game/Telemetry.kt`; everything both platforms must agree
/// about — the rows, the bound, the drop order, the routing, the test gate — is in SmashCore, not
/// here (`Telemetry/Outbox.swift`, `Telemetry/Ingest.swift`).
///
/// **With no configuration this object exists and does nothing** (`conventions.md`, Configuration):
/// no endpoint, no token or no commit stamp and `ingest` is nil, `record` returns immediately and
/// nothing is ever built or sent. That is the state of every build nobody has configured, every
/// checkout on a new machine, and — absolutely — every test run (§18.7).
@MainActor final class Telemetry {
    /// `ios/Telemetry.xcconfig` → `ios/project.yml` → the generated Info.plist. Untracked; the
    /// committed `Telemetry.xcconfig.example` says what goes in it.
    static let endpointKey = "SMASHTelemetryURL"
    static let tokenKey = "SMASHTelemetryToken"

    private let ingest: Ingest?
    private let env: Env
    private let language: String
    /// A developer's flight, not a player's: rows a launch shortcut produced are stamped
    /// `synthetic` so a query can leave them out (§18.1).
    private let synthetic: Bool
    /// The rows waiting. Main actor only — appending is the only thing the game does on this path,
    /// and it is an array append (§18.8, A0).
    private var outbox = Outbox()
    private let sender: Sender?
    private let log = Logger(subsystem: "in.nann.smashhockey", category: "telemetry")

    /// Everything resolved is an argument, so what this decides is visible in one place and none of
    /// it is read twice.
    init(info: [String: Any]? = Bundle.main.infoDictionary,
         commit: String? = Telemetry.commitStamp,
         debugBuild: Bool = Telemetry.isDebugBuild,
         storeInstall: Bool = Telemetry.isStoreInstall,
         testRun: Bool = Telemetry.isTestRun,
         language: String = Telemetry.language,
         synthetic: Bool = false) {
        let ingest = Ingest.resolve(endpoint: info?[Telemetry.endpointKey] as? String,
                                    token: info?[Telemetry.tokenKey] as? String,
                                    commit: commit, testRun: testRun)
        self.ingest = ingest
        self.env = TelemetryEnv.of(debugBuild: debugBuild, storeInstall: storeInstall)
        self.language = language
        self.synthetic = synthetic
        self.sender = ingest.map(Sender.init)
        if let ingest {
            log.info("telemetry on: \(ingest.endpoint, privacy: .public) as \(self.env.rawValue, privacy: .public), build \(ingest.commit, privacy: .public)")
        } else {
            log.info("telemetry is inert — nothing configured (ios/Telemetry.xcconfig), or a test run")
        }
    }

    /// Takes a row (§18.8). No I/O, no request, no JSON: the envelope and the bytes are the sending
    /// path's work, and this is called at the end of a match, one screen away from the next face-off.
    func record(_ row: TelemetryRow) {
        guard sender != nil else { return }
        outbox.append(row)
    }

    /// Sends everything waiting, under **one envelope built for this send** (§18.1).
    ///
    /// Called at exactly two moments (§18.8): going to the background, and arriving at the hub.
    /// **Never** on the result screen, never on an input path and never between a result and the
    /// next face-off (A0, A2) — which is why this is a method the two call sites name rather than
    /// something `record` does when the queue looks full.
    func flush(installId: String) {
        guard let sender, let ingest, !outbox.isEmpty else { return }
        let envelope = Envelope(installId: installId, commit: ingest.commit, at: Telemetry.now(),
                                platform: .ios, env: env, language: language, synthetic: synthetic)
        sender.send(outbox.drain(), envelope)
    }

    // MARK: - What the platform answers

    /// The device's own clock, in epoch milliseconds (§18.1) — the only clock on this path, and it
    /// is read here and nowhere in the core.
    static func now() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded()) }

    /// The commit this build came from, written into the bundle by the build phase in `project.yml`.
    /// Absent it, the client is inert: a build that cannot say which code it is has no business
    /// reporting what that code did, and a literal fallback would be a lie in a column (§18.1).
    static var commitStamp: String? {
        guard let url = Bundle.main.url(forResource: "commit", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// A real store install (§18.7): the App Store receipt is named `receipt`, and a **sandbox**
    /// receipt — TestFlight, App Review — is named something else. A missing receipt (an Xcode run)
    /// reads as not-a-store-install, which is the safe direction.
    ///
    /// `appStoreReceiptURL` rather than StoreKit 2's `AppTransaction` on purpose: the latter is async
    /// and can go to the network on a cold call, and nothing on this path may be able to wait (A0).
    @available(iOS, deprecated: 18.0, message: "Deliberate — see the note above.")
    static var isStoreInstall: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent == "receipt" }

    /// A test run reports **nothing at all** (§18.7). A hosted test bundle's `Bundle.main` is the
    /// app's, so a suite resolves the app's real endpoints — which is how `../flashybird` put 329
    /// events and 65 rows into production out of one `xcodebuild test`.
    static var isTestRun: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    /// The language actually shown (§14, §18.1) — the bundle's own choice, not the device's list.
    /// `und` when there is none to read: an explicit "could not tell", never a quiet "English".
    static var language: String { Bundle.main.preferredLocalizations.first ?? "und" }
}

/// The only place in the app that builds a request, on the only thread that may (§18.8).
///
/// Fire-and-forget: the task is started and never asked how it went. **A failed send is dropped,
/// never retried** — a retry is a stall waiting to happen, and a lost row changes no decision.
private struct Sender: Sendable {
    let ingest: Ingest
    let session: URLSession
    let queue = DispatchQueue(label: "in.nann.smashhockey.telemetry", qos: .utility)

    init(_ ingest: Ingest) {
        self.ingest = ingest
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Tuning.Telemetry.sendTimeoutSeconds
        configuration.waitsForConnectivity = false          // a send that cannot go now is dropped
        configuration.allowsExpensiveNetworkAccess = false  // never a player's metered link
        self.session = URLSession(configuration: configuration)
    }

    func send(_ rows: [TelemetryRow], _ envelope: Envelope) {
        queue.async {
            // One request per table, because the routes are the tables (§18.6) — and so one
            // malformed batch cannot take another table's rows down with it. A flush can never
            // exceed the collector's batch cap: the outbox's bound is that cap.
            for (_, group) in Dictionary(grouping: rows, by: \.table) {
                guard let first = group.first else { continue }
                let body = "[" + group.map { $0.encoded(envelope) }.joined(separator: ",") + "]"
                guard let url = URL(string: ingest.url(for: first)) else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(ingest.token)", forHTTPHeaderField: "Authorization")
                request.httpBody = Data(body.utf8)
                session.dataTask(with: request).resume()
            }
        }
    }
}
