/// What the save says every match the player starts looks like (spec §2.2, §9, §10, §11, §12): the
/// player's side from the career and the coach's board, the opponent, the world, the rules. The
/// screens ask here instead of assembling a match themselves, so a season match, a quick match, a
/// drill and the demo can never disagree about whose tactics apply. The Android twin is
/// `core/season/Kickoff.kt`.
extension SaveRecord {
    /// The team the player plays as: the career's, or the demo's club before there is one (§9, §11.5).
    public var sideTeam: TeamKey { career?.team ?? TeamKey(Career.demoClub) }

    /// The player's side in every match they play (§12): the team's rating (§2.1, §2.2), the board's
    /// pressing, covering, push up, discipline and formation. Passing and shooting are not the
    /// board's (§12) — they stay the team's own.
    public var playerSide: SideSetup {
        let own = career?.startingTactics ?? Career.demoClub.tactics
        let tactics = Tactics(pressing: board.pressing, covering: board.covering, pushUp: board.pushUp,
                              passing: own.passing, shooting: own.shooting, discipline: board.discipline)
        let rating = career.map { $0.rating(of: $0.team) } ?? Career.demoClub.rating
        return SideSetup(rating: rating, tactics: tactics, formation: board.formation)
    }

    /// The player's fixture of the current matchday as a match (§11.1, §11.2): in the home team's
    /// world, sudden death when it is a cup tie, the board's period length and ball spin. Nil when
    /// there is no fixture to play.
    public func seasonMatch(seed: UInt64) -> MatchSetup? {
        guard let career, let season, let fixture = playerFixture else { return nil }
        let opponent = fixture.home == career.team ? fixture.away : fixture.home
        let cup: Bool
        if case .cup = Season.plan[season.matchday] { cup = true } else { cup = false }
        let world = career.homeWorld(of: fixture.home)
        return MatchSetup(seed: seed, sport: world.sport, home: playerSide, away: career.side(of: opponent),
                          periodSeconds: board.periodSeconds, orbitPeriod: board.ballSpinSeconds, cup: cup,
                          control: .player)
    }

    /// A quick match (§11.5): the friendly `quick` drew, league rules, the board's settings.
    public func quickMatch(_ quick: QuickMatch, seed: UInt64) -> MatchSetup {
        MatchSetup(seed: seed, sport: quick.world.sport, home: playerSide, away: .club(quick.opponent),
                   periodSeconds: board.periodSeconds, orbitPeriod: board.ballSpinSeconds, cup: false, control: .player)
    }

    /// A drill (§10): the drill's own lineups and ratings, the coach's tactics and ball spin.
    public func drill(_ drill: Drill, seed: UInt64) -> DrillSetup {
        DrillSetup(drill: drill, seed: seed, tactics: playerSide.tactics, orbitPeriod: board.ballSpinSeconds)
    }

    /// The demo behind the menus (§9): the player's team against `opponent`, both automatic.
    public func demo(world: World, opponent: Club, seed: UInt64) -> MatchSetup {
        MatchSetup.demo(seed: seed, world: world, home: playerSide, away: .club(opponent),
                        periodSeconds: board.periodSeconds)
    }

    /// A drill is open once the one before it has been won (§10); the first always is.
    public func isOpen(_ drill: Drill) -> Bool {
        guard let i = Drill.allCases.firstIndex(of: drill), i > 0 else { return true }
        return training.won.contains(Drill.allCases[i - 1])
    }

    /// Whether `drill` has been won.
    public func isWon(_ drill: Drill) -> Bool { training.won.contains(drill) }

    /// Replaces the board, clamped to nothing: the board's own values are the caller's to choose
    /// from §12's ranges; a value outside them is a programming error, refused.
    public mutating func setBoard(_ next: BoardRecord) throws(GameError) {
        for v in [next.pressing, next.covering, next.pushUp, next.discipline]
        where !(v >= Tuning.Board.tacticMin && v <= Tuning.Board.tacticMax) { throw .notABoardValue }
        guard Tuning.Board.periodSeconds.contains(next.periodSeconds),
              Tuning.Board.ballSpinSeconds.contains(next.ballSpinSeconds) else { throw .notABoardValue }
        board = next
    }

    /// "Reset" on the coach's board (§12): the defaults, or the picked club's tactics.
    public mutating func resetBoard() { board = .reset(for: career) }
}

extension CareerRecord {
    /// A team's kit, sRGB 0xRRGGBB: a club's, or the created team's.
    public func kit(of key: TeamKey) -> (primary: UInt32, secondary: UInt32) {
        if let club = key.club { return (club.primary, club.secondary) }
        return (created!.primary, created!.secondary)
    }

    /// A team's home world (§2.1, §2.2): where its home fixtures are played (§11.1).
    public func homeWorld(of key: TeamKey) -> World { key.club?.world ?? created!.world }

    /// An opponent as an AI side: a club's rating and tactics, the balanced formation (§3). The
    /// created team is never the opponent — it is always the player's.
    func side(of key: TeamKey) -> SideSetup {
        guard let club = key.club else { preconditionFailure("the created team is the player's, never the opponent") }
        return .club(club)
    }
}
