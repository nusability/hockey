import Foundation
import os
import SmashCore

/// A bench diagnostic behind `-policy trial`: puts a trained checkpoint in charge of the side the
/// player faces, so a match against it can be *felt* on a phone instead of read off six metrics.
///
/// **This is not the shipped path and is not spec'd.** ADR `0010` wants weights in
/// `shared/assets/policy/`, declared in `shared/data/policy.toml`, with a spec entry; none of that
/// exists yet. Until it does, `Match.installPolicies` is "the trainer's and the bench's hook, not
/// the app's", and this is the bench. Without the launch argument it costs one `UserDefaults` read
/// at startup and nothing else: §7's written rules play, which is the match
/// `shared/vectors/match/` pins.
///
/// The weights are one hex IEEE-754 double per line in `PolicyNet.parameters` order, exactly as
/// `TrainTeamAI` writes a checkpoint, so a file can be dropped in with `cp` and no conversion.
@MainActor
enum TrialPolicy {
    /// `-policy trial` on the launch arguments. Any non-empty value turns it on.
    static var wanted: Bool { !(UserDefaults.standard.string(forKey: "policy") ?? "").isEmpty }

    private static let log = Logger(subsystem: "in.nann.smashhockey", category: "policy")

    /// Hidden units per layer. The checkpoint's parameter count has to agree, and the only shape
    /// trained so far is 128 (ADR `0010` measured a pass at 3.73 µs on an M1).
    private static let hidden = 128

    private static let loaded: PolicyNet? = {
        guard wanted else { return nil }
        guard let url = Bundle.main.url(forResource: "trial-policy", withExtension: "txt") else {
            log.error("-policy asked for a trial policy but trial-policy.txt is not in the bundle")
            return nil
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            log.error("trial-policy.txt is in the bundle but could not be read")
            return nil
        }
        // Read it exactly as `TrainTeamAI.readCheckpoint` does: a `#` header is skipped, and a line
        // that is not a hex bit pattern is not a parameter.
        let p: [Double] = text.split(whereSeparator: \.isNewline).compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard !s.hasPrefix("#"), let bits = UInt64(s, radix: 16) else { return nil }
            return Double(bitPattern: bits)
        }
        let nIn = PolicyInputs.count, nOut = PolicyInputs.outputCount, h = hidden
        let want = nIn * h + h + h * h + h + h * nOut + nOut
        guard p.count == want else {
            log.error("""
                trial-policy.txt holds \(p.count) parameters; \
                \(nIn) → \(h) → \(h) → \(nOut) wants \(want). Not installing.
                """)
            return nil
        }
        log.info("trial policy loaded: \(p.count) parameters, \(nIn) → \(h) → \(h) → \(nOut)")
        return PolicyNet(nIn: nIn, nHidden: h, nOut: nOut, parameters: p)
    }()

    /// Puts the trial policy on **team 1**, the side the player faces, and leaves team 0 to §7 —
    /// the player drives their own carrier either way (§5), so team 0's policy would only change
    /// its off-ball play and muddle what is being judged.
    static func install(_ m: inout Match) {
        guard let net = loaded else { return }
        m.installPolicies([nil, net])
    }
}
