package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.feel.CardLayout
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.season.FormKind
import `in`.nann.smashhockey.core.season.FormMatch
import `in`.nann.smashhockey.core.season.TeamDetail
import `in`.nann.smashhockey.core.season.detail
import `in`.nann.smashhockey.core.season.kit
import `in`.nann.smashhockey.core.season.short
import `in`.nann.smashhockey.core.season.team
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel

/**
 * A team's detail (spec §16.3a) — the twin of iOS's TeamDetail.swift, and **a screen of its own**,
 * reached by tapping its row in the league table: the hub's title, fixture card, table and buttons
 * leave, the camera swoops here, and Back swoops back. Nothing of the hub is left standing behind
 * it, so there is one screen's worth of controls on screen and the panel's edges are never in
 * doubt.
 *
 * It shows the full name over the kit, where the team stands, what it has played, won, drawn and
 * lost, its goals, its last three matches as a form strip and the fixture it plays next. The
 * player's own team also gets the way to change its name and kit (§16.1). The panel is built to its
 * content by [CardLayout]: its buttons sit inside its width, below the last line, and a club name
 * that wraps makes the panel taller rather than pushing the keys over the words.
 */
class DetailScreen(game: Game, team: TeamKey) :
    Screen(Game.pose(Presentation.Screens.Detail.eye, Presentation.Screens.Detail.target), game) {

    private class Form(val colour: Int, val badge: String, val line: String, val score: String)

    init {
        val career = checkNotNull(game.save.career) { "a team's detail is reached only from the season hub" }
        val season = checkNotNull(game.save.season) { "a team's detail is reached only from the season hub" }
        val d = season.detail(team, career)
        val mine = team == career.team
        val colours = career.kit(team)
        val room = CardLayout.inner(CARD_WIDTH)

        // What the panel says, in the order it says it — each line measured before anything is
        // built, so the panel can be made exactly tall enough to hold all of it (§16.3a).
        val r = d.row
        val name = Names.team(team, career)
        val nameRoom = room - 0.4
        val place = L(CopyKey.DETAIL_PLACE, Names.ordinal(d.position), r.points)
        val played = L(CopyKey.DETAIL_PLAYED, r.played)
        val record = L(CopyKey.DETAIL_RECORD, r.won, r.drawn, r.lost)
        val gd = if (r.goalDifference > 0) "+${r.goalDifference}" else "${r.goalDifference}"
        val goals = "${L(CopyKey.DETAIL_GOALS, r.goalsFor, r.goalsAgainst)} · ${L(CopyKey.TABLE_GD)} $gd"
        val formRoom = room - 0.55
        val forms = d.form.map { form(it, career) }
        val next = next(d, career, team)

        val heights = ArrayList<Double>()
        heights += maxOf(0.22, CardLayout.blockHeight(name, 0.085, nameRoom))
        heights += CardLayout.blockHeight(place, 0.055, room)
        heights += maxOf(CardLayout.blockHeight(played, 0.045, 0.5), CardLayout.blockHeight(record, 0.045, 0.9))
        heights += CardLayout.blockHeight(goals, 0.045, room)
        heights += CardLayout.blockHeight(L(CopyKey.DETAIL_FORM), 0.045, room)
        if (forms.isEmpty()) {
            heights += CardLayout.blockHeight(L(CopyKey.DETAIL_NONE), 0.05, room)
        } else {
            for (f in forms) heights += maxOf(0.15, CardLayout.blockHeight(f.line, 0.05, formRoom))
        }
        heights += CardLayout.blockHeight(L(CopyKey.DETAIL_NEXT), 0.045, room)
        heights += CardLayout.blockHeight(next, 0.05, room)

        val keys = ArrayList<CardLayout.Button>()
        keys += CardLayout.Button(L(CopyKey.COMMON_BACK), 0.08, 0.5, 0.3)
        if (mine) keys += CardLayout.Button(L(CopyKey.TEAM_EDIT_BUTTON), 0.1, 0.7, 0.34)
        val card = CardLayout(CARD_WIDTH, heights, keys)

        val panel = part(Panel(kit, card.width.toFloat(), card.height.toFloat(), 0.14f, C.PAPER, Entrance.Tumble),
            at(0f, (top + bottom) / 2))
        val face = panel.content
        val left = card.left.toFloat()
        val right = card.right.toFloat()
        var laid = 0
        fun nextY(): Float = card.blocks[laid++].centreY.toFloat()

        // The team: its kit, its code, and — the point of the screen — its full name (§16.3, "3").
        var y = nextY()
        kit.slab(0.34f, 0.22f, 0.05f, colours.first, face, corner = 0.03f).setPosition(left + 0.17f, y, 0.02f)
        letters(career.short(team), 0.09f, colours.second, maxWidth = 0.3f, x = left + 0.17f, y = y, z = 0.05f, parent = face)
        letters(name, 0.085f, if (mine) C.PINK_INK else C.INK, maxWidth = nameRoom.toFloat(),
            align = Label3D.Align.LEADING, x = left + 0.4f, y = y, z = 0.01f, parent = face)

        y = nextY()
        letters(place, 0.055f, C.GREEN_INK, maxWidth = room.toFloat(), align = Label3D.Align.LEADING,
            x = left, y = y, z = 0.01f, parent = face)
        y = nextY()
        letters(played, 0.045f, C.INK, maxWidth = 0.5f, align = Label3D.Align.LEADING, x = left, y = y, z = 0.01f, parent = face)
        letters(record, 0.045f, C.INK, maxWidth = 0.9f, align = Label3D.Align.TRAILING, x = right, y = y, z = 0.01f, parent = face)
        y = nextY()
        letters(goals, 0.045f, C.INK, maxWidth = room.toFloat(), align = Label3D.Align.LEADING,
            x = left, y = y, z = 0.01f, parent = face)

        // The form strip: the last three, most recent first, fewer early in a season (§16.3a).
        y = nextY()
        letters(L(CopyKey.DETAIL_FORM), 0.045f, C.GREEN_INK, maxWidth = room.toFloat(), align = Label3D.Align.LEADING,
            x = left, y = y, z = 0.01f, parent = face)
        if (forms.isEmpty()) {
            y = nextY()
            letters(L(CopyKey.DETAIL_NONE), 0.05f, C.DISABLED_INK, maxWidth = room.toFloat(), y = y, z = 0.01f, parent = face)
        }
        for (f in forms) {
            y = nextY()
            kit.slab(0.13f, 0.13f, 0.04f, f.colour, face, corner = 0.03f).setPosition(left + 0.065f, y, 0.02f)
            letters(f.badge, 0.06f, C.INK, maxWidth = 0.11f, x = left + 0.065f, y = y, z = 0.05f, parent = face)
            letters(f.line, 0.05f, C.INK, maxWidth = formRoom.toFloat(), align = Label3D.Align.LEADING,
                x = left + 0.15f, y = y, z = 0.01f, parent = face)
            letters(f.score, 0.06f, C.INK, maxWidth = 0.34f, align = Label3D.Align.TRAILING,
                x = right, y = y, z = 0.01f, parent = face)
        }

        y = nextY()
        letters(L(CopyKey.DETAIL_NEXT), 0.045f, C.GREEN_INK, maxWidth = room.toFloat(), align = Label3D.Align.LEADING,
            x = left, y = y, z = 0.01f, parent = face)
        y = nextY()
        letters(next, 0.05f, C.INK, maxWidth = room.toFloat(), align = Label3D.Align.LEADING,
            x = left, y = y, z = 0.01f, parent = face)

        // The screen's own two controls, inside the panel and below everything it says.
        val back = card.buttons[0]
        part(BlockButton(kit, L(CopyKey.COMMON_BACK), "detail_back_button", BlockButton.Style.QUIET,
            back.width.toFloat(), back.height.toFloat(), 0.08f, action = { game.go(Game.Place.Hub) }),
            at(back.centreX.toFloat(), back.centreY.toFloat()), face)
        if (mine && card.buttons.size > 1) {
            val box = card.buttons[1]
            val edit = BlockButton(kit, L(CopyKey.TEAM_EDIT_BUTTON), "detail_edit_button", BlockButton.Style.PRIMARY,
                box.width.toFloat(), box.height.toFloat(), 0.1f, action = { game.go(Game.Place.Team(editing = true)) })
            edit.bobs = true
            part(edit, at(box.centreX.toFloat(), box.centreY.toFloat()), face)
        }
    }

    /**
     * One match of the form strip: won, drawn or lost as a coloured badge, where it was played,
     * the opponent's full name, and the score.
     */
    private fun form(f: FormMatch, career: CareerRecord): Form {
        val colour = when (f.kind) {
            FormKind.WON -> C.GREEN
            FormKind.DRAWN -> C.SUN
            FormKind.LOST -> C.PINK
        }
        val venue = L(if (f.home) CopyKey.DETAIL_HOME else CopyKey.DETAIL_AWAY)
        val cup = if (f.cup) " · ${L(CopyKey.HUB_CUP_TAB)}" else ""
        val ot = if (f.overtime) " ${L(CopyKey.HUD_OT)}" else ""
        return Form(colour, L(kindKey(f.kind)), "$venue ${Names.team(f.opponent, career)}$cup",
            "${f.goalsFor}:${f.goalsAgainst}$ot")
    }

    /** The fixture the team plays next, in words: where, against whom, in which round. */
    private fun next(d: TeamDetail, career: CareerRecord, team: TeamKey): String {
        val f = d.next ?: return L(CopyKey.DETAIL_NO_NEXT)
        val home = f.home == team
        val other = if (home) f.away else f.home
        val venue = L(if (home) CopyKey.DETAIL_HOME else CopyKey.DETAIL_AWAY)
        return "$venue ${Names.team(other, career)} · ${Names.matchday(Season.plan[f.matchday])}"
    }

    companion object {
        /** The panel's width in the design frame; its height follows what it carries. */
        private const val CARD_WIDTH = 1.66

        fun kindKey(k: FormKind): CopyKey = when (k) {
            FormKind.WON -> CopyKey.DETAIL_WON
            FormKind.DRAWN -> CopyKey.DETAIL_DRAWN
            FormKind.LOST -> CopyKey.DETAIL_LOST
        }
    }
}
