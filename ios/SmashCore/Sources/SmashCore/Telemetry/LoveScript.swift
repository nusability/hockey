/// The love-dialog golden vector (spec §4.7, §17, `shared/vectors/telemetry/love.txt`): a script of
/// steps carrying the clock, replayed against the policy and the device record.
///
/// `RecordTelemetryVectors` writes the file; `SmashCoreTests` and Android's `:core` tests recompute
/// every output line from the input lines and must reproduce them exactly. The Android twin is
/// `core/telemetry/LoveScript.kt`, in its test source set.
///
/// This is the whole bet of ADR 0009: a time-dependent policy that can be pinned headlessly. A clock
/// moved backwards, a cooldown straddling a clock change, a record we lost, an answer already
/// given — each is one line here instead of three months on a phone.
public struct LoveScript: Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// One input line. Everything else in the file is output.
    public enum Step: Sendable {
        /// `launch <now> <fresh|lost>` — the app started and read the device record, or failed to and
        /// replaced it (§17.1).
        case launch(now: Int64, lost: Bool)
        /// `match <now> <duration> <cup|league|-> <goal…>` — a finished player match; a goal is
        /// `f@<ms>` (the player's) or `a@<ms>` (the opponent's), in the order they were scored.
        case match(now: Int64, match: LoveMatch)
        /// `settle <now> <unread|on|off>` — the player reached a settled screen (§17.3) with the kill
        /// switch in that state. The panel goes up if and only if the verdict is `ask`.
        case settle(now: Int64, remote: LoveSwitch)
        /// `answer <now> <positive|negative|dismissed>` — the player answered the panel that is up.
        case answer(now: Int64, answer: LoveAnswer)
        /// `bytes <file>` — the record's canonical JSON is `shared/vectors/telemetry/<file>`, exactly.
        case bytes(file: String)
    }

    public var steps: [Step]

    public init(steps: [Step]) { self.steps = steps }

    /// Reads a vector's input lines; everything else in the file is output and is ignored here.
    public static func parse(_ text: String) throws(Failure) -> LoveScript {
        var steps: [Step] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) where !raw.hasPrefix("#") {
            let line = String(raw)
            let w = line.split(separator: " ").map(String.init)
            func now() throws(Failure) -> Int64 {
                guard w.count > 1, let n = Int64(w[1]) else { throw Failure(description: "bad instant: \(line)") }
                return n
            }
            switch w[0] {
            case "launch":
                guard w.count == 3, w[2] == "fresh" || w[2] == "lost" else {
                    throw Failure(description: "bad launch line: \(line)")
                }
                steps.append(.launch(now: try now(), lost: w[2] == "lost"))
            case "match":
                guard w.count >= 4, let duration = Int(w[2]) else {
                    throw Failure(description: "bad match line: \(line)")
                }
                var goals: [LoveMatch.Goal] = []
                for item in w[4...] {
                    let parts = item.split(separator: "@").map(String.init)
                    guard parts.count == 2, parts[0] == "f" || parts[0] == "a", let at = Int(parts[1]) else {
                        throw Failure(description: "bad goal \(item): \(line)")
                    }
                    goals.append(LoveMatch.Goal(mine: parts[0] == "f", atMillis: at))
                }
                guard ["cup", "league", "-"].contains(w[3]) else {
                    throw Failure(description: "bad trophy \(w[3]): \(line)")
                }
                steps.append(.match(now: try now(), match: LoveMatch(goals: goals, durationMillis: duration,
                                                                    wonCup: w[3] == "cup", wonLeague: w[3] == "league")))
            case "settle":
                guard w.count == 3, let remote = LoveSwitch(rawValue: w[2]) else {
                    throw Failure(description: "bad settle line: \(line)")
                }
                steps.append(.settle(now: try now(), remote: remote))
            case "answer":
                guard w.count == 3, let answer = LoveAnswer(rawValue: w[2]) else {
                    throw Failure(description: "bad answer line: \(line)")
                }
                steps.append(.answer(now: try now(), answer: answer))
            case "bytes":
                guard w.count == 2 else { throw Failure(description: "bad bytes line: \(line)") }
                steps.append(.bytes(file: w[1]))
            default:
                continue
            }
        }
        guard !steps.isEmpty else { throw Failure(description: "a vector needs at least one step") }
        return LoveScript(steps: steps)
    }

    /// Replays the script. Every step's input line is re-emitted followed by its outputs, so the
    /// returned lines are the whole file below its header. A `bytes` step calls `pinning` with the
    /// file's name and the record as it stands: the suites compare it against the file, the recorder
    /// writes it. Nothing here reads a file, so the core stays free of I/O.
    ///
    /// The runner is the platform layer's part of the dance, reduced to nothing: a record, and the
    /// trigger a moment armed, held until a settled screen shows it. Deliberately **not** durable —
    /// arming is a session fact, so a prompt earned and not reached is simply earned again.
    public func run(pinning: (String, DeviceRecord) throws -> Void) throws -> [String] {
        var record = DeviceRecord.fresh(at: 0)
        var armed: LoveTrigger?
        var up = false
        var lines: [String] = []

        func state() -> String {
            let asked = record.lastAskedAt.map(String.init) ?? "-"
            return "  state \(record.matchesPlayed) \(record.installedAt) \(asked) "
                + "\(record.answeredPositively ? "yes" : "no") \(armed?.rawValue ?? "-")"
        }

        for step in steps {
            switch step {
            case .launch(let now, let lost):
                lines.append("launch \(now) \(lost ? "lost" : "fresh")")
                record = lost ? .replacement(at: now) : .fresh(at: now)
                armed = nil
                up = false
                lines.append(state())
            case .match(let now, let match):
                let goals = match.goals.map { "\($0.mine ? "f" : "a")@\($0.atMillis)" }
                let trophy = match.wonCup ? "cup" : (match.wonLeague ? "league" : "-")
                lines.append(([String]() + ["match", "\(now)", "\(match.durationMillis)", trophy] + goals)
                    .joined(separator: " "))
                record = record.recordingPlayedMatch()
                let trigger = LovePolicy.trigger(match, matchesPlayed: record.matchesPlayed)
                // A moment that arms nothing leaves a moment that already did alone: the prompt is
                // earned once and waits for a settled screen (§17.3).
                if let trigger { armed = trigger }
                lines.append("  result \(match.goalsFor)-\(match.goalsAgainst)"
                    + " \(match.won ? "won" : (match.goalsFor == match.goalsAgainst ? "drew" : "lost"))"
                    + " \(match.trailed ? "trailed" : "-")"
                    + " \(match.winningGoalMillis.map(String.init) ?? "-")"
                    + " \(match.winningGoalWasLate ? "late" : "-")"
                    + " \(match.wasHardFought ? "hard" : "-")")
                lines.append("  trigger \(trigger?.rawValue ?? "-")")
                lines.append(state())
            case .settle(let now, let remote):
                lines.append("settle \(now) \(remote.rawValue)")
                let verdict = LovePolicy.decide(record.loveFacts(armed: armed, remote: remote), now: now)
                if verdict == .ask {
                    record = record.recordingPresentation(at: now)
                    armed = nil
                    up = true
                }
                lines.append("  verdict \(verdict.rawValue)")
                lines.append(state())
            case .answer(let now, let answer):
                lines.append("answer \(now) \(answer.rawValue)")
                guard up else { throw Failure(description: "answered at \(now) with no panel up") }
                record = record.recording(answer)
                up = false
                lines.append(state())
            case .bytes(let file):
                lines.append("bytes \(file)")
                try pinning(file, record)
            }
        }
        return lines
    }
}
