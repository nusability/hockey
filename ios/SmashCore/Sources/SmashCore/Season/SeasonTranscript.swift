/// The season golden vector (spec §4.7, shared/vectors/season/): a whole season played from a
/// fixed seed through the save's own API, the player's matches fed a scripted score, written as
/// text — every fixture, every result, the table after every matchday, the cup draws, the stream
/// position after every call, the champion, the cup winner and the trophies. RecordSeasonVectors
/// writes it; SmashCoreTests and Android's core tests recompute it from its input lines and must
/// reproduce every line.
public struct SeasonScript: Sendable {
    public enum Mode: String, Sendable {
        case played = "-", overtime = "ot", forfeit
    }

    public struct Entry: Sendable {
        public let goalsFor: Int
        public let goalsAgainst: Int
        public let mode: Mode

        public init(goalsFor: Int, goalsAgainst: Int, mode: Mode) {
            self.goalsFor = goalsFor
            self.goalsAgainst = goalsAgainst
            self.mode = mode
        }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    public var seed: UInt64
    /// `created <short> <#primary> <#secondary> <world> <name…>` — the team the player created (§2.2).
    public var career: String
    public var entries: [Entry]

    public init(seed: UInt64, career: String, entries: [Entry]) {
        self.seed = seed
        self.career = career
        self.entries = entries
    }

    /// Reads the input lines (`seed`, `career`, `script`) of a vector; everything else is output.
    public static func parse(_ text: String) throws(Failure) -> SeasonScript {
        var seed: UInt64?
        var career: String?
        var entries: [Entry] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") {
            let words = line.split(separator: " ").map(String.init)
            switch words[0] {
            case "seed":
                seed = UInt64(words[1].dropFirst(2), radix: 16)
            case "career":
                career = String(line.dropFirst("career ".count))
            case "script":
                guard words.count == 4, let f = Int(words[1]), let a = Int(words[2]), let m = Mode(rawValue: words[3]) else {
                    throw Failure(description: "bad script line: \(line)")
                }
                entries.append(Entry(goalsFor: f, goalsAgainst: a, mode: m))
            default:
                continue
            }
        }
        guard let seed, let career else { throw Failure(description: "a vector needs a seed and a career line") }
        return SeasonScript(seed: seed, career: career, entries: entries)
    }

    /// The save at the season's start: the team created through the save's API (§2.2).
    public func startingSave() throws(Failure) -> SaveRecord {
        var save = SaveRecord.fresh
        let w = career.split(separator: " ", maxSplits: 5).map(String.init)
        do {
            guard w.first == "created", w.count == 6, let p = UInt32(w[2].dropFirst(), radix: 16),
                  let s = UInt32(w[3].dropFirst(), radix: 16), let world = World(rawValue: w[4]) else {
                throw Failure(description: "bad career: \(career)")
            }
            try save.createTeam(TeamDraft(name: w[5], short: w[1], primary: p, secondary: s, world: world))
            try save.startSeason(seed: seed)
        } catch let e as GameError {
            throw Failure(description: "\(e)")
        } catch {
            throw Failure(description: "\(error)")
        }
        return save
    }

    /// Plays the script. With `reloadAfter`, the save is written and read back after that many
    /// player matches — the rest must go on exactly as without. With `stopAfter`, it returns the
    /// save after that many. Returns the transcript (input lines first) and the last save.
    public func run(reloadAfter: Int? = nil, stopAfter: Int? = nil) throws(Failure) -> (lines: [String], save: SaveRecord) {
        var save = try startingSave()
        let career = save.career!
        var lines = ["seed 0x" + SaveJSON.hex(seed, digits: 16), "career " + self.career]
        lines += entries.map { "script \($0.goalsFor) \($0.goalsAgainst) \($0.mode.rawValue)" }
        let first = save.season!
        lines.append("league " + first.teams.map { career.short(of: $0) }.joined(separator: " "))
        lines += first.fixtures.map { "fixture \($0.matchday) \(Self.label($0.matchday)) \(career.short(of: $0.home)) \(career.short(of: $0.away))" }
        lines.append("stream 0x" + SaveJSON.hex(first.stream, digits: 16))
        var printed = 0
        lines += days(save.season!, career, from: &printed)
        var played = 0
        while !save.season!.isFinished {
            guard played < entries.count else { throw Failure(description: "the script ran out at matchday \(save.season!.matchday)") }
            let entry = entries[played]
            played += 1
            let f = save.playerFixture!
            lines.append("play \(f.matchday) \(Self.label(f.matchday)) \(career.short(of: f.home)) \(career.short(of: f.away))")
            do {
                switch entry.mode {
                case .forfeit: try save.forfeit()
                case .played, .overtime:
                    try save.recordPlayed(goalsFor: entry.goalsFor, goalsAgainst: entry.goalsAgainst, overtime: entry.mode == .overtime)
                }
            } catch {
                throw Failure(description: "\(error) at matchday \(f.matchday)")
            }
            if played == reloadAfter {
                do { save = try SaveRecord.decode(save.encoded()) } catch { throw Failure(description: "reload: \(error)") }
            }
            lines += days(save.season!, save.career!, from: &printed)
            lines.append("stream 0x" + SaveJSON.hex(save.season!.stream, digits: 16))
            if played == stopAfter { return (lines, save) }
        }
        guard played == entries.count else { throw Failure(description: "the script has \(entries.count - played) lines too many") }
        let end = save.season!
        let c = save.career!
        lines.append("champion " + c.short(of: end.table(c)[0].team))
        lines.append("cupwinner " + c.short(of: end.cupWinner!))
        lines.append("trophies \(c.leagueTitles) \(c.cups)")
        return (lines, save)
    }

    /// The blocks of the matchdays closed since `printed`.
    private func days(_ season: SeasonRecord, _ career: CareerRecord, from printed: inout Int) -> [String] {
        var lines: [String] = []
        while printed < season.matchday {
            let md = printed
            lines.append("day \(md) \(Self.label(md))")
            for f in season.fixtures(on: md) {
                let s = f.score!
                let who = f.home == career.team || f.away == career.team ? "player" : "sim"
                lines.append("result \(career.short(of: f.home)) \(career.short(of: f.away)) \(s.home) \(s.away) "
                             + "\(s.overtime ? "ot" : "-") \(who)")
            }
            if case .cup(let round) = Season.plan[md], round != CupRound.allCases.last! {
                let next = CupRound.allCases[CupRound.allCases.firstIndex(of: round)! + 1]
                for f in season.cupTies(next) {
                    lines.append("cupdraw \(f.matchday) \(Self.label(f.matchday)) \(career.short(of: f.home)) \(career.short(of: f.away))")
                }
            }
            for (i, r) in season.table(career, through: md).enumerated() {
                lines.append("table \(i + 1) \(career.short(of: r.team)) \(r.played) \(r.won) \(r.drawn) \(r.lost) "
                             + "\(r.goalsFor) \(r.goalsAgainst) \(r.points)")
            }
            printed += 1
        }
        return lines
    }

    static func label(_ md: Int) -> String {
        switch Season.plan[md] {
        case .league(let round): "L\(round)"
        case .cup(let round): round.rawValue
        }
    }
}
