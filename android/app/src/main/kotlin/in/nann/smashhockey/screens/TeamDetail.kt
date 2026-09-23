package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.Season
import `in`.nann.smashhockey.core.generated.SeasonRecord
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.season.FormKind
import `in`.nann.smashhockey.core.season.FormMatch
import `in`.nann.smashhockey.core.season.TeamDetail
import `in`.nann.smashhockey.core.season.detail
import `in`.nann.smashhockey.core.season.kit
import `in`.nann.smashhockey.core.season.short
import `in`.nann.smashhockey.core.season.team
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.UiNode

/**
 * A team's detail behind its row in the league table (spec §16.3a) — the twin of iOS's
 * TeamDetail.swift: the full name over its kit, where it stands, what it has played, won, drawn
 * and lost, its goals, its last three matches as a form strip and the fixture it plays next. The
 * player's own team also gets the way to change its name and kit (§16.1). It tips up in front of
 * the hub like the drills' intro card and is dismissed the same way.
 */
class TeamDetailPanel(
    private val screen: Screen,
    team: TeamKey,
    career: CareerRecord,
    season: SeasonRecord,
    onEdit: () -> Unit,
    onClose: () -> Unit,
) {
    val parts = ArrayList<Presentable>()
    private val panel: Panel
    private val kit = screen.kit

    init {
        val d = season.detail(team, career)
        val mine = team == career.team
        val colours = career.kit(team)
        panel = screen.child(Panel(kit, 1.66f, 1.62f, 0.14f, C.PAPER, Entrance.Tumble), at(0f, 0.02f, z = 0.5f), screen.layer)
        parts += panel
        val face = panel.content

        // The team: its kit, its code, and — the point of the screen — its full name (§16.3, "3").
        kit.slab(0.34f, 0.22f, 0.05f, colours.first, face, corner = 0.03f).setPosition(-0.61f, 0.66f, 0.02f)
        screen.letters(career.short(team), 0.09f, colours.second, maxWidth = 0.3f, x = -0.61f, y = 0.66f, z = 0.05f, parent = face)
        screen.letters(Names.team(team, career), 0.085f, if (mine) C.PINK_INK else C.INK, maxWidth = 1.0f,
            align = Label3D.Align.LEADING, x = -0.4f, y = 0.66f, z = 0.01f, parent = face)

        val r = d.row
        screen.letters(L(CopyKey.DETAIL_PLACE, Names.ordinal(d.position), r.points), 0.055f, C.GREEN_INK, maxWidth = 1.44f,
            align = Label3D.Align.LEADING, x = -0.76f, y = 0.48f, z = 0.01f, parent = face)
        screen.letters(L(CopyKey.DETAIL_PLAYED, r.played), 0.045f, C.INK, maxWidth = 0.5f,
            align = Label3D.Align.LEADING, x = -0.76f, y = 0.37f, z = 0.01f, parent = face)
        screen.letters(L(CopyKey.DETAIL_RECORD, r.won, r.drawn, r.lost), 0.045f, C.INK, maxWidth = 0.9f,
            align = Label3D.Align.TRAILING, x = 0.76f, y = 0.37f, z = 0.01f, parent = face)
        val gd = if (r.goalDifference > 0) "+${r.goalDifference}" else "${r.goalDifference}"
        screen.letters("${L(CopyKey.DETAIL_GOALS, r.goalsFor, r.goalsAgainst)} · ${L(CopyKey.TABLE_GD)} $gd", 0.045f, C.INK,
            maxWidth = 1.44f, align = Label3D.Align.LEADING, x = -0.76f, y = 0.26f, z = 0.01f, parent = face)

        // The form strip: the last three, most recent first, fewer early in a season (§16.3a).
        screen.letters(L(CopyKey.DETAIL_FORM), 0.045f, C.GREEN_INK, maxWidth = 0.9f, align = Label3D.Align.LEADING,
            x = -0.76f, y = 0.13f, z = 0.01f, parent = face)
        if (d.form.isEmpty()) {
            screen.letters(L(CopyKey.DETAIL_NONE), 0.05f, C.DISABLED_INK, maxWidth = 1.44f, y = -0.04f, z = 0.01f, parent = face)
        }
        for ((i, f) in d.form.withIndex()) row(f, career, 0.02f - i * 0.16f, face)

        screen.letters(L(CopyKey.DETAIL_NEXT), 0.045f, C.GREEN_INK, maxWidth = 0.9f, align = Label3D.Align.LEADING,
            x = -0.76f, y = -0.46f, z = 0.01f, parent = face)
        screen.letters(next(d, career, team), 0.05f, C.INK, maxWidth = 1.44f, align = Label3D.Align.LEADING,
            x = -0.76f, y = -0.57f, z = 0.01f, parent = face)

        parts += screen.child(
            BlockButton(kit, L(CopyKey.COMMON_BACK), "hub_detail_close_button", BlockButton.Style.QUIET, 0.56f, 0.28f, 0.08f,
                action = onClose),
            at(if (mine) -0.46f else 0f, -0.72f), face,
        )
        if (mine) {
            parts += screen.child(
                BlockButton(kit, L(CopyKey.TEAM_EDIT_BUTTON), "hub_detail_edit_button", BlockButton.Style.PRIMARY, 0.86f, 0.3f,
                    0.1f, action = onEdit),
                at(0.36f, -0.72f), face,
            )
        }
        for ((i, p) in parts.withIndex()) p.show(i * screen.motion.staggerSeconds * 3)
    }

    /**
     * One match of the form strip: won, drawn or lost as a coloured badge, where it was played,
     * the opponent's full name, and the score.
     */
    private fun row(f: FormMatch, career: CareerRecord, y: Float, face: UiNode) {
        val colour = when (f.kind) {
            FormKind.WON -> C.GREEN
            FormKind.DRAWN -> C.SUN
            FormKind.LOST -> C.PINK
        }
        kit.slab(0.13f, 0.13f, 0.04f, colour, face, corner = 0.03f).setPosition(-0.7f, y, 0.02f)
        screen.letters(L(kindKey(f.kind)), 0.06f, C.INK, maxWidth = 0.11f, x = -0.7f, y = y, z = 0.05f, parent = face)
        val venue = L(if (f.home) CopyKey.DETAIL_HOME else CopyKey.DETAIL_AWAY)
        val cup = if (f.cup) " · ${L(CopyKey.HUB_CUP_TAB)}" else ""
        screen.letters("$venue ${Names.team(f.opponent, career)}$cup", 0.05f, C.INK, maxWidth = 1.0f,
            align = Label3D.Align.LEADING, x = -0.58f, y = y, z = 0.01f, parent = face)
        val ot = if (f.overtime) " ${L(CopyKey.HUD_OT)}" else ""
        screen.letters("${f.goalsFor}:${f.goalsAgainst}$ot", 0.06f, C.INK, maxWidth = 0.34f,
            align = Label3D.Align.TRAILING, x = 0.76f, y = y, z = 0.01f, parent = face)
    }

    /** The fixture the team plays next, in words: where, against whom, in which round. */
    private fun next(d: TeamDetail, career: CareerRecord, team: TeamKey): String {
        val f = d.next ?: return L(CopyKey.DETAIL_NO_NEXT)
        val home = f.home == team
        val other = if (home) f.away else f.home
        val venue = L(if (home) CopyKey.DETAIL_HOME else CopyKey.DETAIL_AWAY)
        return "$venue ${Names.team(other, career)} · ${Names.matchday(Season.plan[f.matchday])}"
    }

    /** Hops away and takes its parts off the stage — the way the drills' intro card is dismissed. */
    fun leave() {
        for (p in parts.asReversed()) p.hide(0.0)
        val gone = panel.node
        screen.stage.after(0.9) { screen.stage.remove(gone) }
    }

    private companion object {
        fun kindKey(k: FormKind): CopyKey = when (k) {
            FormKind.WON -> CopyKey.DETAIL_WON
            FormKind.DRAWN -> CopyKey.DETAIL_DRAWN
            FormKind.LOST -> CopyKey.DETAIL_LOST
        }
    }
}
