/// A golden vector of the simulation (spec §4.7): a setup, the player's input as (tick, finger)
/// events, and the match it produces — sampled state every `every` ticks and every event — as text
/// with every double written as the hex of its bits. Android's `MatchVector` reads and writes the
/// same format; both replay shared/vectors/match/ and compare line by line, never with a tolerance.
///
///     setup match seed <hex> sport <id> period <bits> orbit <bits> cup <0|1> control <player|automatic>
///           home <rating> <formation> <6 × tactic bits> away <rating> <formation> <6 × tactic bits>
///     setup drill <id> seed <hex> orbit <bits> tactics <6 × tactic bits>
///     every <N>
///     ticks <most ticks to run>
///     input <tick> down|up        — applied at the boundary once <tick> ticks have run
///     e <tick> <event…>           — what was emitted during the tick that brought the count to <tick>
///     s <tick> <state> <period> <overtime> <clock> <score0> <score1> <stream> <ball x z vx vz>
///       <carrier|-1> <orbit> <orbitDirection> then each player's <x z vx vz facing>, in roster order
public struct MatchVector: Sendable {
    public enum Setup: Sendable {
        case match(MatchSetup)
        case drill(DrillSetup)
    }

    public var setup: Setup
    public var every: Int
    public var maxTicks: Int
    public var inputs: [(tick: Int, down: Bool)]

    public init(setup: Setup, every: Int, maxTicks: Int, inputs: [(tick: Int, down: Bool)]) {
        self.setup = setup; self.every = every; self.maxTicks = maxTicks; self.inputs = inputs
    }

    public func makeMatch() -> Match {
        switch setup {
        case .match(let s): Match(s)
        case .drill(let s): Match(s)
        }
    }

    // MARK: Running

    /// The body lines this vector produces: events and samples, in order.
    public func run() -> [String] {
        var match = makeMatch()
        var lines = match.drainEvents().map { "e 0 " + MatchVector.format($0) }
        lines.append(MatchVector.sample(match))
        var next = 0
        while match.ticks < maxTicks && match.state != .ended {
            while next < inputs.count && inputs[next].tick == match.ticks {
                match.hold(inputs[next].down)
                next += 1
            }
            match.tick()
            for event in match.drainEvents() { lines.append("e \(match.ticks) " + MatchVector.format(event)) }
            if match.ticks % every == 0 || match.state == .ended { lines.append(MatchVector.sample(match)) }
        }
        return lines
    }

    public static func sample(_ m: Match) -> String {
        var t = ["s", String(m.ticks), m.state.rawValue, String(m.period), m.overtime ? "1" : "0", hex(m.clock),
                 String(m.score[0]), String(m.score[1]), hex(m.streamState),
                 hex(m.ball.pos.x), hex(m.ball.pos.z), hex(m.ball.vel.x), hex(m.ball.vel.z),
                 String(m.ball.carrier ?? -1), hex(m.ball.orbit), hex(m.ball.orbitDirection)]
        for p in m.players { t += [hex(p.pos.x), hex(p.pos.z), hex(p.vel.x), hex(p.vel.z), hex(p.facing)] }
        return t.joined(separator: " ")
    }

    public static func format(_ e: MatchEvent) -> String {
        func who(_ i: Int?) -> String { i.map(String.init) ?? "-" }
        switch e {
        case .faceOff(let spot): return "faceoff \(hex(spot.x)) \(hex(spot.z))"
        case .play: return "play"
        case .ready: return "ready"
        case .pickup(let p): return "pickup \(p)"
        case .pass(let from, let to): return "pass \(from) \(to)"
        case .shot(let by, let kind): return "shot \(by) \(kind.rawValue)"
        case .steal(let by, let from): return "steal \(by) \(from)"
        case .save(let by): return "save \(by)"
        case .block(let by): return "block \(by)"
        case .post: return "post"
        case .board(let speed): return "board \(hex(speed))"
        case .goal(let team, let scorer, let assist, let own): return "goal \(team) \(who(scorer)) \(who(assist)) \(own ? 1 : 0)"
        case .whistle: return "whistle"
        case .offside(let team, let player): return "offside \(team) \(player)"
        case .periodEnd(let n): return "periodEnd \(n)"
        case .drillInterrupted(let reason): return "interrupted \(reason.rawValue)"
        case .end(let result): return "end \(result.rawValue)"
        }
    }

    // MARK: The file

    /// The header lines (setup, sampling, input) that precede the body.
    public func headerLines() -> [String] {
        var lines: [String]
        switch setup {
        case .match(let s):
            lines = ["setup match seed \(MatchVector.hex(s.seed)) sport \(s.sport.rawValue) period \(MatchVector.hex(s.periodSeconds)) "
                     + "orbit \(MatchVector.hex(s.orbitPeriod)) cup \(s.cup ? 1 : 0) control \(s.control.rawValue) "
                     + "home \(MatchVector.side(s.home)) away \(MatchVector.side(s.away))"]
        case .drill(let s):
            lines = ["setup drill \(s.drill.rawValue) seed \(MatchVector.hex(s.seed)) orbit \(MatchVector.hex(s.orbitPeriod)) "
                     + "tactics \(MatchVector.tactics(s.tactics))"]
        }
        lines.append("every \(every)")
        lines.append("ticks \(maxTicks)")
        lines += inputs.map { "input \($0.tick) \($0.down ? "down" : "up")" }
        return lines
    }

    /// Parses a vector file: the vector, and the body lines it recorded.
    public static func parse(_ text: String) throws -> (vector: MatchVector, recorded: [String]) {
        var setup: Setup?
        var every: Int?
        var maxTicks: Int?
        var inputs: [(tick: Int, down: Bool)] = []
        var body: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("#") { continue }
            var tokens = Tokens(line.split(separator: " ").map(String.init))
            switch try tokens.word() {
            case "setup": setup = try parseSetup(&tokens)
            case "every": every = try tokens.int()
            case "ticks": maxTicks = try tokens.int()
            case "input":
                let tick = try tokens.int()
                let edge = try tokens.word()
                guard edge == "down" || edge == "up" else { throw VectorFormatError("input edge \(edge) is not down|up") }
                inputs.append((tick, edge == "down"))
            case "s", "e": body.append(line)
            case let other: throw VectorFormatError("unknown line kind \(other)")
            }
        }
        guard let setup, let every, let maxTicks else { throw VectorFormatError("a vector needs setup, every and ticks lines") }
        return (MatchVector(setup: setup, every: every, maxTicks: maxTicks, inputs: inputs), body)
    }

    static func parseSetup(_ t: inout Tokens) throws -> Setup {
        switch try t.word() {
        case "match":
            try t.expect("seed"); let seed = try t.bits()
            try t.expect("sport"); let sportId = try t.word()
            guard let sport = Sport(rawValue: sportId) else { throw VectorFormatError("unknown sport \(sportId)") }
            try t.expect("period"); let period = try t.double()
            try t.expect("orbit"); let orbit = try t.double()
            try t.expect("cup"); let cup = try t.int() == 1
            try t.expect("control"); let controlId = try t.word()
            guard let control = Control(rawValue: controlId) else { throw VectorFormatError("unknown control \(controlId)") }
            try t.expect("home"); let home = try parseSide(&t)
            try t.expect("away"); let away = try parseSide(&t)
            return .match(MatchSetup(seed: seed, sport: sport, home: home, away: away, periodSeconds: period,
                                     orbitPeriod: orbit, cup: cup, control: control))
        case "drill":
            let id = try t.word()
            guard let drill = Drill(rawValue: id) else { throw VectorFormatError("unknown drill \(id)") }
            try t.expect("seed"); let seed = try t.bits()
            try t.expect("orbit"); let orbit = try t.double()
            try t.expect("tactics"); let tactics = try parseTactics(&t)
            return .drill(DrillSetup(drill: drill, seed: seed, tactics: tactics, orbitPeriod: orbit))
        case let other:
            throw VectorFormatError("unknown setup kind \(other)")
        }
    }

    static func parseSide(_ t: inout Tokens) throws -> SideSetup {
        let rating = try t.int()
        let id = try t.word()
        guard let formation = Formation(rawValue: id) else { throw VectorFormatError("unknown formation \(id)") }
        return SideSetup(rating: rating, tactics: try parseTactics(&t), formation: formation)
    }

    static func parseTactics(_ t: inout Tokens) throws -> Tactics {
        Tactics(pressing: try t.double(), covering: try t.double(), pushUp: try t.double(),
                passing: try t.double(), shooting: try t.double(), discipline: try t.double())
    }

    static func side(_ s: SideSetup) -> String { "\(s.rating) \(s.formation.rawValue) \(tactics(s.tactics))" }

    static func tactics(_ t: Tactics) -> String {
        [t.pressing, t.covering, t.pushUp, t.passing, t.shooting, t.discipline].map(hex).joined(separator: " ")
    }

    public static func hex(_ v: UInt64) -> String {
        let s = String(v, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - s.count) + s
    }

    public static func hex(_ d: Double) -> String { hex(d.bitPattern) }

    struct Tokens {
        var items: [String]
        var at = 0
        init(_ items: [String]) { self.items = items }

        mutating func word() throws -> String {
            guard at < items.count else { throw VectorFormatError("line ends early: \(items.joined(separator: " "))") }
            defer { at += 1 }
            return items[at]
        }

        mutating func expect(_ w: String) throws {
            let got = try word()
            guard got == w else { throw VectorFormatError("expected \(w), got \(got)") }
        }

        mutating func int() throws -> Int {
            let w = try word()
            guard let v = Int(w) else { throw VectorFormatError("\(w) is not an integer") }
            return v
        }

        mutating func bits() throws -> UInt64 {
            let w = try word()
            guard w.count == 16, let v = UInt64(w, radix: 16) else { throw VectorFormatError("\(w) is not 16 hex digits") }
            return v
        }

        mutating func double() throws -> Double { Double(bitPattern: try bits()) }
    }
}

public struct VectorFormatError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
