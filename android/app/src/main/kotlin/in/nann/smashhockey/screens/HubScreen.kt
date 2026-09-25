package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.Fixture
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.season.cupTies
import `in`.nann.smashhockey.core.season.cupWinner
import `in`.nann.smashhockey.core.season.homeWorld
import `in`.nann.smashhockey.core.season.isFinished
import `in`.nann.smashhockey.core.season.kit
import `in`.nann.smashhockey.core.season.playerFixture
import `in`.nann.smashhockey.core.season.short
import `in`.nann.smashhockey.core.season.startSeason
import `in`.nann.smashhockey.core.season.table
import `in`.nann.smashhockey.core.season.team
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.TableRow
import `in`.nann.smashhockey.ui.Tile
import `in`.nann.smashhockey.core.season.TableRow as Standing

/**
 * The season hub (spec §16.3) — the twin of iOS's HubScreen.swift: the next fixture in both kits
 * with its round and world, and Play — one tap to the face-off (A2); the league table with the
 * player's row marked, or the cup bracket with its results; and once the final is played, the
 * season's end — champion, cup winner, the player's place — and the next season. After a matchday
 * the table's rows land where they stood and hop to their new places.
 */
class HubScreen(game: Game) : Screen(Game.pose(Presentation.Screens.Hub.eye, Presentation.Screens.Hub.target), game) {
    private val tableParts = ArrayList<Presentable>()
    private val cupParts = ArrayList<Presentable>()
    private val tableTab: Tile
    private val cupTab: Tile
    private var showingCup = false
    private val card: Panel

    init {
        val career = checkNotNull(game.save.career) { "the hub is reached only with a career" }
        val season = checkNotNull(game.save.season) { "the hub is reached only with a season" }
        val over = season.isFinished
        // The season's number in the career heads the hub (§16.3, §15).
        val header = L(CopyKey.HUB_SEASON, season.number) + " · " +
            (if (over) L(CopyKey.HUB_OVER) else L(CopyKey.HUB_HEADER, season.matchday + 1, Season.plan.size))
        part(Label3D(kit, header, 0.1f, C.PAPER, maxWidth = 1.7f, entrance = Entrance.Drop), at(0f, top - 0.14f))
        card = part(Panel(kit, 1.72f, 0.74f, S.SLAB_DEPTH, C.PAPER, Entrance.Tumble), at(0f, top - 0.62f, tilt = -0.02f))
        val f = game.save.playerFixture
        if (over) seasonOver(career, season) else if (f != null) fixture(career, season, f)

        tableTab = part(tab(L(CopyKey.HUB_TABLE), "hub_table_button") { switchTo(false) }, at(-0.3f, top - 1.1f))
        cupTab = part(tab(L(CopyKey.HUB_CUP_TAB), "hub_cup_button") { switchTo(true) }, at(0.3f, top - 1.1f))
        tableTab.isSelected = true
        table(career, season, top - 1.32f)
        bracket(career, season, top - 1.38f)

        part(BlockButton(kit, L(CopyKey.COMMON_BACK), "hub_back_button", BlockButton.Style.QUIET, 0.5f, 0.3f, 0.09f) {
            game.go(Game.Place.Title)
        }, at(-0.62f, bottom + 0.34f))
        val go = if (over) {
            BlockButton(kit, L(CopyKey.HUB_NEXT_SEASON), "hub_nextseason_button", BlockButton.Style.PRIMARY, 1.1f, 0.36f, 0.1f) {
                val seed = MatchPlan.seed()
                if (game.commit { it.startSeason(seed) }) game.go(Game.Place.Hub)
            }
        } else {
            BlockButton(kit, L(CopyKey.HUB_PLAY), "hub_play_button", BlockButton.Style.PRIMARY, 1.25f, 0.36f, 0.13f) {
                game.play(MatchPlan.Season)
            }
        }
        go.bobs = true
        part(go, at(0.3f, bottom + 0.34f))
    }

    private fun tab(title: String, id: String, action: () -> Unit): Tile {
        val t = Tile(kit, 0.52f, 0.18f, C.PAPER, C.GREEN, id = id, label = title, action = action)
        letters(title, 0.06f, C.INK, maxWidth = 0.46f, parent = t.content)
        return t
    }

    // ---------------------------------------------------------------- the card

    private fun fixture(career: CareerRecord, season: SeasonRecord, f: Fixture) {
        for ((team, x) in listOf(f.home to -0.5f, f.away to 0.5f)) {
            val k = career.kit(team)
            val chip = child(Panel(kit, 0.56f, 0.36f, 0.08f, k.first, Entrance.Pop), at(x, 0.11f), card.content)
            chip.presence.show(0.0)
            kit.slab(0.1f, 0.37f, 0.085f, k.second, chip.body, corner = 0.01f).setPosition(-0.2f, 0f, 0f)
            child(Label3D(kit, career.short(team), 0.13f, k.second, maxWidth = 0.36f), at(0.05f, 0f), chip.content).show(0.0)
            // Both clubs by their full names, not only their codes (§16.3).
            letters(Names.team(team, career), 0.048f, if (team == career.team) C.PINK_INK else C.INK, maxWidth = 0.78f,
                x = x, y = -0.12f, z = 0.01f, parent = card.content)
        }
        child(Label3D(kit, L(CopyKey.HUB_VS), 0.12f, C.PINK_INK, maxWidth = 0.36f), at(0f, 0.11f), card.content).show(0.0)
        val line = "${Names.matchday(Season.plan[season.matchday])} · ${Names.world(career.homeWorld(f.home))}"
        child(Label3D(kit, line, S.TEXT_SMALL, C.INK, maxWidth = 1.6f), at(0f, -0.28f), card.content).show(0.0)
    }

    private fun seasonOver(career: CareerRecord, season: SeasonRecord) {
        val standings = season.table(career)
        val champion = standings[0].team
        val cupWinner = season.cupWinner ?: champion
        for ((i, pair) in listOf(L(CopyKey.HUB_CHAMPION) to champion, L(CopyKey.HUB_CUP_WINNER) to cupWinner).withIndex()) {
            val (label, team) = pair
            val y = 0.18f - i * 0.19f
            letters(label, 0.045f, C.GREEN_INK, maxWidth = 0.5f, align = Label3D.Align.LEADING, x = -0.8f, y = y, z = 0.01f, parent = card.content)
            val k = career.kit(team)
            kit.slab(0.2f, 0.13f, 0.04f, k.first, card.content, corner = 0.02f).setPosition(-0.2f, y, 0.02f)
            letters(career.short(team), 0.05f, k.second, maxWidth = 0.16f, x = -0.2f, y = y, z = 0.04f, parent = card.content)
            letters(Names.team(team, career), 0.055f, if (team == career.team) C.PINK_INK else C.INK, maxWidth = 0.66f,
                align = Label3D.Align.LEADING, x = -0.06f, y = y, z = 0.01f, parent = card.content)
        }
        val place = standings.indexOfFirst { it.team == career.team } + 1
        letters(L(CopyKey.HUB_PLACE, Names.ordinal(place)), 0.06f, C.INK, maxWidth = 1.6f, y = -0.2f, z = 0.01f, parent = card.content)
        if (place == 1 || cupWinner == career.team) stage.after(1.2) { card.celebrate(1.2) }
    }

    // ---------------------------------------------------------------- the table (§11.4)

    private fun table(career: CareerRecord, season: SeasonRecord, top: Float) {
        val cols = listOf(TableRow.Column(0.05f, Label3D.Align.CENTRE), TableRow.Column(0.20f, Label3D.Align.LEADING),
            TableRow.Column(0.62f, Label3D.Align.CENTRE), TableRow.Column(0.76f, Label3D.Align.CENTRE),
            TableRow.Column(0.91f, Label3D.Align.CENTRE))
        val width = 1.72f
        tableParts += child(TableRow(kit, listOf("#", L(CopyKey.TABLE_TEAM), L(CopyKey.TABLE_PLAYED), L(CopyKey.TABLE_GD),
            L(CopyKey.TABLE_POINTS)), cols, width, 0.09f, "hub_table_header", C.BOARD, ink = C.PAPER, textHeight = S.TEXT_SMALL,
            y = top, entrance = Entrance.Tumble), at(0f, top), layer)
        val step = S.ROW_HEIGHT + S.ROW_GAP + 0.02f
        val rowY = FloatArray(8) { top - 0.12f - it * step }
        val now = season.table(career)
        val before = game.tableBefore?.takeIf { it.size == now.size }
        game.tableBefore = null
        fun texts(i: Int, r: Standing) = listOf("${i + 1}", career.short(r.team), "${r.played}",
            if (r.goalDifference > 0) "+${r.goalDifference}" else "${r.goalDifference}", "${r.points}")
        for ((i, r) in now.withIndex()) {
            val mine = r.team == career.team
            val k = career.kit(r.team)
            val start = before?.indexOfFirst { it.team == r.team }?.takeIf { it >= 0 } ?: i
            val shown = before?.get(start) ?: r
            val row = child(TableRow(kit, texts(start, shown), cols, width, S.ROW_HEIGHT + 0.02f, "hub_table_row_${r.team.key}",
                if (mine) C.ROW_HIGHLIGHT else if (start % 2 == 0) C.ROW_LIGHT else C.ROW_DARK,
                chip = TableRow.KitColours(k.first, k.second), y = rowY[start], entrance = Entrance.Slide(fromLeft = i % 2 == 0),
                hint = "${Names.team(r.team, career)}, ${L(CopyKey.DETAIL_OPEN)}", action = { game.go(Game.Place.Detail(r.team)) }),
                at(0f, rowY[start]), layer)
            tableParts += row
            if (before == null) continue
            // Land in the old place with the old numbers, then take the new ones and hop over.
            stage.after(2.2) {
                row.set(texts(i, r))
                row.move(rowY[i])
                if (!mine) row.recolour(if (i % 2 == 0) C.ROW_LIGHT else C.ROW_DARK)
            }
        }
    }

    // ---------------------------------------------------------------- the cup (§11.1)

    private fun bracket(career: CareerRecord, season: SeasonRecord, top: Float) {
        val pitch = 0.38f
        for ((c, round) in CupRound.entries.withIndex()) {
            val count = 4 shr c
            val ties = season.cupTies(round)
            val x = -0.58f + c * 0.58f
            cupParts += child(Label3D(kit, Names.cupRound(round), 0.04f, C.PAPER, maxWidth = 0.54f, entrance = Entrance.Drop),
                at(x, top + 0.02f), layer)
            for (i in 0 until count) {
                val span = (1 shl c).toFloat()
                val y = top - 0.2f - pitch * (i * span + (span - 1) / 2)
                val tie = child(Panel(kit, 0.54f, 0.3f, 0.06f, C.PAPER, Entrance.Pop), at(x, y), layer)
                cupParts += tie
                val f = ties.getOrNull(i)
                val winner = f?.let(::winnerOf)
                for ((line, team) in listOf(f?.home, f?.away).withIndex()) {
                    val ly = if (line == 0) 0.065f else -0.065f
                    val won = team != null && winner == team
                    val ink = if (team == career.team) C.PINK_INK else if (f?.score == null || won) C.INK else C.DISABLED_INK
                    letters(team?.let { career.short(it) } ?: "–", 0.05f, ink, align = Label3D.Align.LEADING, x = -0.23f, y = ly,
                        z = 0.01f, parent = tie.content)
                    val s = f?.score ?: continue
                    val goals = if (line == 0) s.home else s.away
                    letters(if (won && s.overtime) "$goals ${L(CopyKey.HUD_OT)}" else "$goals", 0.05f, ink,
                        align = Label3D.Align.TRAILING, x = 0.23f, y = ly, z = 0.01f, parent = tie.content)
                }
            }
        }
    }

    private fun switchTo(cup: Boolean) {
        if (cup == showingCup) return
        showingCup = cup
        tableTab.isSelected = !cup
        cupTab.isSelected = cup
        val stagger = motion.staggerSeconds
        for ((i, p) in (if (cup) tableParts else cupParts).withIndex()) p.hide(i * stagger * 0.3)
        for ((i, p) in (if (cup) cupParts else tableParts).withIndex()) p.show(0.25 + i * stagger * 0.6)
    }

    override fun show(after: Double) {
        super.show(after)
        val stagger = motion.staggerSeconds * 1.6
        for ((i, p) in (if (showingCup) cupParts else tableParts).withIndex()) p.show(after + 0.3 + i * stagger)
    }

    override fun leave() {
        for (p in tableParts + cupParts) p.hide(0.0)
        super.leave()
    }

    private companion object {
        /** A played fixture's winner; null when it is unplayed or level. */
        fun winnerOf(f: Fixture): TeamKey? {
            val s = f.score ?: return null
            if (s.home == s.away) return null
            return if (s.home > s.away) f.home else f.away
        }
    }
}
