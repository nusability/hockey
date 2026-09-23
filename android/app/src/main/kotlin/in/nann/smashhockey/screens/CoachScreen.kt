package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Formation
import `in`.nann.smashhockey.core.generated.Role
import `in`.nann.smashhockey.core.generated.Spot
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.season.resetBoard
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Quat
import `in`.nann.smashhockey.ui.Slider3D
import `in`.nann.smashhockey.ui.Tile
import `in`.nann.smashhockey.ui.WaveText
import java.util.Locale

/**
 * The coach's board (spec §16.7, §12) — the twin of iOS's CoachScreen.swift: pressing, covering,
 * push up and discipline on sliders, the five formations drawn as disks on little pitches, period
 * length and ball spin as stepped sliders, and Reset. Every change is the save's at once (§15).
 */
class CoachScreen(game: Game) : Screen(Game.pose(Presentation.Screens.Coach.eye, Presentation.Screens.Coach.target), game) {
    private val sliders = ArrayList<Slider3D>()
    private val period: Slider3D
    private val spin: Slider3D
    private val formations = LinkedHashMap<Formation, Tile>()
    private val board: Panel

    init {
        val b = game.save.board
        part(WaveText(kit, L(CopyKey.COACH_TITLE), 0.16f, C.PAPER, bob = 0.6f, id = "coach_title_header"), at(0f, top - 0.22f))
        board = part(Panel(kit, 1.76f, 1.4f, 0.12f, C.CHALK, Entrance.Tumble), at(0f, top - 1.05f))
        val tactics = listOf(Triple(CopyKey.COACH_PRESSING, "coach_pressing_field", b.pressing),
            Triple(CopyKey.COACH_COVERING, "coach_covering_field", b.covering),
            Triple(CopyKey.COACH_PUSH_UP, "coach_pushup_field", b.pushUp),
            Triple(CopyKey.COACH_DISCIPLINE, "coach_discipline_field", b.discipline))
        for ((i, t) in tactics.withIndex()) {
            val s = part(Slider3D(kit, L(t.first), t.second, t.third, 1.4f, entrance = Entrance.Slide(fromLeft = i % 2 == 0)),
                at(0f, 0.5f - i * 0.33f, z = 0.02f), board.content)
            s.onChange = { changed() }
            sliders += s
        }

        part(Label3D(kit, L(CopyKey.COACH_FORMATION), 0.045f, C.PAPER, Label3D.Align.LEADING), at(-0.86f, top - 1.88f))
        for ((i, f) in Formation.entries.withIndex()) {
            val t = part(pitch(f), at(-0.72f + i * 0.36f, top - 2.14f))
            t.isSelected = f == b.formation
            formations[f] = t
        }

        val periods = Tuning.Board.periodSeconds
        val spins = Tuning.Board.ballSpinSeconds
        period = part(Slider3D(kit, L(CopyKey.COACH_PERIOD), "coach_period_field", share(b.periodSeconds, periods), 1.4f,
            stops = periods.size, format = { L(CopyKey.COACH_SECONDS, pick(it, periods).toInt()) }), at(0f, top - 2.5f))
        spin = part(Slider3D(kit, L(CopyKey.COACH_SPIN), "coach_spin_field", share(b.ballSpinSeconds, spins), 1.4f,
            stops = spins.size, format = { L(CopyKey.COACH_SECONDS, String.format(Locale.ROOT, "%.1f", pick(it, spins))) },
            entrance = Entrance.Slide(fromLeft = false)), at(0f, top - 2.82f))
        period.onChange = { changed() }
        spin.onChange = { changed() }

        // The board is where the player tunes their own team, so it is also where they change its
        // name and kit (§16.1, §16.7) — one tap from the title.
        val team = game.save.career != null
        val wide = if (team) 0.56f else 0.78f
        part(BlockButton(kit, L(CopyKey.COACH_RESET), "coach_reset_button", BlockButton.Style.QUIET, wide, 0.32f, 0.1f) { reset() },
            at(if (team) -0.6f else -0.46f, bottom + 0.3f))
        if (team) {
            part(BlockButton(kit, L(CopyKey.TEAM_EDIT_BUTTON), "coach_team_button", BlockButton.Style.SECONDARY, wide, 0.32f, 0.09f) {
                game.go(Game.Place.Team(editing = true))
            }, at(0f, bottom + 0.3f))
        }
        part(BlockButton(kit, L(CopyKey.COMMON_BACK), "coach_back_button", BlockButton.Style.PRIMARY, wide, 0.32f, 0.1f) {
            game.go(game.home)
        }, at(if (team) 0.6f else 0.46f, bottom + 0.3f))
    }

    /** A formation as its six disks on a little pitch, attacking up (§3). */
    private fun pitch(f: Formation): Tile {
        val t = Tile(kit, 0.32f, 0.4f, C.RAIL, C.GREEN, id = "coach_formation_${f.key}_button", label = L(f.nameKey)) { choose(f) }
        kit.slab(0.28f, 0.006f, 0.01f, C.CHALK, t.content, corner = 0f).setPosition(0f, 0.03f, 0.005f)
        val upright = Quat().axisAngle((Math.PI / 2).toFloat(), 1f, 0f, 0f)
        fun disk(spot: Spot, rgb: Int) {
            val d = kit.cylinder(0.02f, 0.022f, rgb, t.content)
            d.setRotation(upright)
            d.setPosition((spot.x / 15).toFloat() * 0.13f, 0.03f + (spot.z / 28).toFloat() * 0.15f, 0.012f)
        }
        disk(Formation.goalie, C.INK)
        for (p in f.players) disk(p.spot, if (p.role == Role.DEFENDER) C.PAPER else C.SUN)
        val name = L(f.nameKey).split(' ').firstOrNull() ?: ""
        letters(name, 0.034f, C.PAPER, maxWidth = 0.28f, y = -0.16f, z = 0.01f, parent = t.content)
        return t
    }

    private fun choose(f: Formation) {
        for ((k, t) in formations) t.isSelected = k == f
        changed(f)
    }

    /** Everything on the board, as it stands, into the save (§12, §15). */
    private fun changed(formation: Formation? = null) {
        val b = game.save.board
        game.setBoard(b.copy(
            pressing = sliders[0].value, covering = sliders[1].value, pushUp = sliders[2].value, discipline = sliders[3].value,
            formation = formation ?: b.formation,
            periodSeconds = pick(period.value, Tuning.Board.periodSeconds),
            ballSpinSeconds = pick(spin.value, Tuning.Board.ballSpinSeconds),
        ))
    }

    /** "Reset" (§12): the defaults, or the picked club's tactics — and the board shows it. */
    private fun reset() {
        game.commit { it.resetBoard() }
        val b = game.save.board
        for ((s, v) in sliders.zip(listOf(b.pressing, b.covering, b.pushUp, b.discipline))) s.set(v, notify = false)
        period.set(share(b.periodSeconds, Tuning.Board.periodSeconds), notify = false)
        spin.set(share(b.ballSpinSeconds, Tuning.Board.ballSpinSeconds), notify = false)
        for ((k, t) in formations) t.isSelected = k == b.formation
        board.celebrate(0.4)
    }

    companion object {
        /** A choice's place along its stepped slider (0…1), and back. */
        fun share(v: Double, choices: List<Double>): Double = maxOf(0, choices.indexOf(v)).toDouble() / (choices.size - 1)

        fun pick(share: Double, choices: List<Double>): Double {
            val i = kotlin.math.floor(share * (choices.size - 1) + 0.5).toInt()
            return choices[i.coerceIn(0, choices.size - 1)]
        }
    }
}
