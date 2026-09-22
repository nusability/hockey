import Testing
@testable import SmashCore

/// The generated config (shared/data/ → Generated/): every declared double arrives with the exact
/// bits the declaration names, and the tables hold what the spec says they hold.
@Suite struct GeneratedDataTests {
    @Test func everyDeclaredDoubleHasItsExactBits() {
        #expect(GeneratedConstantBits.all.count > 300)
        for (name, value, bits) in GeneratedConstantBits.all {
            #expect(value.bitPattern == bits, "\(name) is \(value) (0x\(String(value.bitPattern, radix: 16))), declared bits 0x\(String(bits, radix: 16))")
        }
    }

    @Test func theTablesMatchTheSpec() {
        #expect(Club.allCases.count == 8)                                      // §2.1
        #expect(Set(Club.allCases.map(\.short)).count == 8)
        #expect(Club.glowowls.tactics.pressing == 0.65)
        #expect(Club.glowowls.tactics.passing == Tactics.defaults.passing)
        #expect(Club.wolves.world == .himalaya && World.himalaya.sport == .ice)
        #expect(Career.createdRating == 77 && Career.createdReplaces == .wolves) // §2.2
        #expect(Formation.allCases.count == 5 && Formation.allCases.allSatisfy { $0.players.count == 5 })
        #expect(Formation.goalie == Spot(x: 0, z: -25))                         // §3
        #expect(Drill.allCases.count == 8 && Drill.scrimmage.ballTo == 1)       // §10
        #expect(Drill.moving.away[2].patrol == Patrol(to: Spot(x: -8, z: 15), speed: 0.9, phase: 1.5))
        #expect(Drill.scrimmage.rule == .freePlay && Drill.pass.rule == .assist)
        #expect(Season.plan.count == 17)                                         // §11.1
        #expect(Season.plan[4] == .cup(.quarterFinal) && Season.plan.last == .cup(.final))
        #expect(Tuning.Time.stepSeconds == 1.0 / 240.0)                          // §4.1
        #expect(Tuning.Board.ballSpinSeconds.first == 1.4 && Tuning.Board.ballSpinSeconds.last == 3.2)
        #expect(Sport.ice.cornerRadius == 8.5)                                   // §1
    }

    @Test func everyCopyKeyIsDeclaredOnce() {
        #expect(Set(CopyKey.allCases.map(\.rawValue)).count == CopyKey.allCases.count)
        #expect(CopyKey.menuTrophies.arguments == ["league", "cup"])
        #expect(CopyKey(rawValue: "play.button") == .playButton)
        #expect(Club.nebula.nameKey == .clubNebulaName)
    }
}
