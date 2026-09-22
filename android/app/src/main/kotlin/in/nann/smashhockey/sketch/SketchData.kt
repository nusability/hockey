package `in`.nann.smashhockey.sketch

// THROWAWAY (SMASH-5): the motion sketch's fake data — the twin of iOS's SketchData.swift, a
// click-dummy for judging the 3D UI's feel on a phone, not the season (§11). Kit colours are
// invented here; the spec gives each club a primary and a secondary kit colour but does not yet
// name them.

enum class SketchScreenId { TITLE, HUB, MATCH, RESULT, COACH }

class SketchClub(val code: String, val primary: Int, val secondary: Int)

class SketchStanding(val code: String, val played: Int, val goalDiff: Int, val points: Int)

class SketchGoal(val at: Double, val home: Boolean)

object SketchData {
    val clubs: Map<String, SketchClub> = listOf(
        SketchClub("MOS", 0x4F8A3C, 0xF2E6C9),
        SketchClub("GLO", 0x6C4AB6, 0xFFD84D),
        SketchClub("NEB", 0x1F3B73, 0x7FD1F5),
        SketchClub("ROC", 0xE4572E, 0x2B2D42),
        SketchClub("DUN", 0xE8A33D, 0x5A2E0E),
        SketchClub("MIR", 0xC1476B, 0xF6E7D8),
        SketchClub("GLW", 0x9CC7E0, 0x1D3557),
        SketchClub("COR", 0xFF7F66, 0x0F6E7A),
    ).associateBy { it.code }
    const val PLAYER = "DUN"
    const val OPPONENT = "NEB"

    /** The table after matchday 4. */
    val before = listOf(
        SketchStanding("ROC", 4, 6, 10),
        SketchStanding("NEB", 4, 4, 9),
        SketchStanding("GLO", 4, 2, 7),
        SketchStanding("DUN", 4, 1, 6),
        SketchStanding("MOS", 4, 0, 5),
        SketchStanding("COR", 4, -2, 4),
        SketchStanding("MIR", 4, -4, 3),
        SketchStanding("GLW", 4, -7, 1),
    )

    /** The table after matchday 5: DUN 3–1 NEB, ROC 1–1 GLO, MOS 2–1 COR, MIR 1–0 GLW. */
    val after = ranked(listOf(
        SketchStanding("ROC", 5, 6, 11),
        SketchStanding("NEB", 5, 2, 9),
        SketchStanding("GLO", 5, 2, 8),
        SketchStanding("DUN", 5, 3, 9),
        SketchStanding("MOS", 5, 1, 8),
        SketchStanding("COR", 5, -3, 4),
        SketchStanding("MIR", 5, -3, 6),
        SketchStanding("GLW", 5, -8, 1),
    ))

    /** §11.4's order: points, goal difference, then code (goals for is not faked here). */
    fun ranked(s: List<SketchStanding>): List<SketchStanding> =
        s.sortedWith(compareByDescending<SketchStanding> { it.points }.thenByDescending { it.goalDiff }.thenBy { it.code })

    /** The fake match: 30 s on the clock, goals at these clock seconds elapsed (home = ours). */
    const val MATCH_SECONDS = 30.0
    val goals = listOf(SketchGoal(5.0, true), SketchGoal(11.0, false), SketchGoal(17.5, true), SketchGoal(24.0, true))
}
