package `in`.nann.smashhockey.sketch

import `in`.nann.smashhockey.R
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.CameraPose
import `in`.nann.smashhockey.ui.DesignTokens.Colour
import `in`.nann.smashhockey.ui.DesignTokens.Size
import `in`.nann.smashhockey.ui.Entrance
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Panel
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.TableRow
import `in`.nann.smashhockey.ui.UIStage
import `in`.nann.smashhockey.ui.UiNode
import `in`.nann.smashhockey.ui.WaveText
import `in`.nann.smashhockey.ui.Xform

// THROWAWAY (SMASH-5): the motion sketch's screens, built only from the UI kit — the twin of
// iOS's SketchScreens.swift, same poses, layout numbers and choreography.

typealias Go = (SketchScreenId) -> Unit

/** Localized copy for the sketch (generated from shared/data/copy.toml). */
fun interface Copy { operator fun invoke(res: Int): String }

internal fun at(x: Float, y: Float, z: Float = 0f, tilt: Float = 0f) = Xform.at(x, y, z, tilt)

/** A screen of the sketch: where the camera stands for it and what arrives when it does. */
open class SketchScreen(val pose: CameraPose, val stage: UIStage) {
    /** Everything that arrives, in arrival order. */
    val parts = ArrayList<Presentable>()
    protected val kit = stage.kit

    fun <E : Presentable> part(e: E, on: UiNode): E {
        stage.add(e, on)
        parts += e
        return e
    }

    /** Arrivals, one after another on the stagger token. */
    open fun show(after: Double) {
        val stagger = stage.motion.staggerSeconds * 1.6
        for (i in parts.indices) parts[i].show(after + i * stagger)
    }

    /** Departures, quicker, last-in first-out. */
    open fun hide() {
        val stagger = stage.motion.staggerSeconds * 0.5
        for ((i, p) in parts.asReversed().withIndex()) p.hide(i * stagger)
    }

    open fun update(dt: Double) {}
}

/**
 * Title: the logo drops in letter by letter and keeps bobbing; Play bobs for the thumb; Training
 * is disabled (it shakes its head); Coach opens the board.
 */
class TitleScreen(stage: UIStage, L: Copy, go: Go) :
    SketchScreen(CameraPose(0f, 4.2f, -22f, 0f, 6.2f, 20f), stage) {
    val play: BlockButton
    val training: BlockButton
    val coach: BlockButton
    private val badge: Panel

    init {
        val f = stage.frame(pose)
        val smash = part(WaveText(kit, L(R.string.title_logo_top), 0.36f, Colour.SUN, id = "title_logo_header"), f.node)
        smash.rest.set(at(0f, f.top - 0.45f, tilt = 0.05f))
        val hockey = part(WaveText(kit, L(R.string.title_logo_bottom), 0.30f, Colour.CREAM, bob = 0.7f, id = "title_logo2_header"), f.node)
        hockey.rest.set(at(-0.05f, f.top - 0.90f, tilt = 0.05f))
        badge = part(Panel(kit, 0.42f, 0.30f, 0.12f, Colour.CORAL, Entrance.Pop), f.node)
        badge.rest.set(at(0.62f, f.top - 1.22f, z = 0.05f, tilt = -0.22f))
        stage.add(Label3D(kit, "3D", 0.16f, Colour.CREAM), badge.content).presence.show(0.0)

        val tagline = part(Label3D(kit, L(R.string.menu_tagline), Size.TEXT_SMALL, Colour.INK, maxWidth = 1.7f,
            entrance = Entrance.Tumble), f.node)
        tagline.rest.set(at(0f, f.top - 1.55f))

        val y0 = f.bottom + 1.25f
        play = part(BlockButton(kit, L(R.string.play_button), "title_play_button", BlockButton.Style.PRIMARY,
            1.3f, 0.38f, 0.15f) { go(SketchScreenId.HUB) }, f.node)
        play.rest.set(at(0f, y0))
        play.bobs = true
        training = part(BlockButton(kit, L(R.string.title_training), "title_training_button", BlockButton.Style.SECONDARY) {}, f.node)
        training.rest.set(at(0f, y0 - 0.46f))
        training.isEnabled = false
        coach = part(BlockButton(kit, L(R.string.title_coach), "title_coach_button", BlockButton.Style.SECONDARY) {
            go(SketchScreenId.COACH)
        }, f.node)
        coach.rest.set(at(0f, y0 - 0.88f))
    }

    override fun show(after: Double) {
        super.show(after)
        stage.after(after + 1.0) { badge.celebrate(0.8) }
    }
}

/** Season hub: the next fixture in both kits, the league table, Play Match. */
class HubScreen(stage: UIStage, L: Copy, go: Go) :
    SketchScreen(CameraPose(-19f, 10f, -14f, 2f, 3f, 8f), stage) {
    val playMatch: BlockButton
    val back: BlockButton
    private val rows = HashMap<String, TableRow>()
    private val rowY: FloatArray
    private var standings = SketchData.before
    private val fixture: Panel
    private var reshuffle = false

    init {
        val f = stage.frame(pose)
        val header = part(Label3D(kit, L(R.string.hub_header), 0.105f, Colour.CREAM, maxWidth = 1.7f, entrance = Entrance.Drop), f.node)
        header.rest.set(at(0f, f.top - 0.14f))

        // The fixture card: both clubs in their kits.
        val card = part(Panel(kit, 1.72f, 0.62f, Size.SLAB_DEPTH, Colour.CREAM, Entrance.Tumble), f.node)
        card.rest.set(at(0f, f.top - 0.62f, tilt = -0.02f))
        fixture = card
        val home = SketchData.clubs.getValue(SketchData.PLAYER)
        val away = SketchData.clubs.getValue(SketchData.OPPONENT)
        for ((club, x) in listOf(home to -0.5f, away to 0.5f)) {
            val kitPanel = stage.add(Panel(kit, 0.56f, 0.36f, 0.08f, club.primary, Entrance.Pop), card.content)
            kitPanel.rest.set(at(x, 0.05f))
            kitPanel.presence.show(0.0)
            kit.slab(0.1f, 0.37f, 0.085f, club.secondary, kitPanel.body, corner = 0.01f).setPosition(-0.2f, 0f, 0f)
            val code = stage.add(Label3D(kit, club.code, 0.13f, club.secondary, maxWidth = 0.36f), kitPanel.content)
            code.rest.set(at(0.05f, 0f))
            code.show(0.0)
        }
        stage.add(Label3D(kit, L(R.string.hub_vs), 0.12f, Colour.CORAL, maxWidth = 0.36f), card.content).show(0.0)
        val sub = stage.add(Label3D(kit, L(R.string.hub_fixture), Size.TEXT_SMALL, Colour.INK, maxWidth = 1.6f), card.content)
        sub.rest.set(at(0f, -0.225f))
        sub.show(0.0)

        // The table: a header line and eight rows that know how to re-rank.
        val cols = listOf(TableRow.Column(0.05f, Label3D.Align.CENTRE), TableRow.Column(0.20f, Label3D.Align.LEADING),
            TableRow.Column(0.62f, Label3D.Align.CENTRE), TableRow.Column(0.76f, Label3D.Align.CENTRE),
            TableRow.Column(0.91f, Label3D.Align.CENTRE))
        val width = 1.72f
        val top = f.top - 1.12f
        part(TableRow(kit, listOf("#", L(R.string.table_team), L(R.string.table_played), L(R.string.table_gd), L(R.string.table_points)),
            cols, width, 0.09f, "hub_table_header", Colour.BOARD, ink = Colour.CREAM, textHeight = Size.TEXT_SMALL, y = top,
            entrance = Entrance.Tumble), f.node)
        val step = Size.ROW_HEIGHT + Size.ROW_GAP + 0.02f
        rowY = FloatArray(8) { top - 0.12f - it * step }
        for ((i, s) in standings.withIndex()) {
            val club = SketchData.clubs.getValue(s.code)
            val mine = s.code == SketchData.PLAYER
            rows[s.code] = part(TableRow(kit, texts(i, s), cols, width, Size.ROW_HEIGHT + 0.02f,
                "hub_table_row_${s.code.lowercase()}",
                if (mine) Colour.ROW_HIGHLIGHT else if (i % 2 == 0) Colour.ROW_LIGHT else Colour.ROW_DARK,
                chip = TableRow.KitColours(club.primary, club.secondary),
                y = rowY[i], entrance = Entrance.Slide(fromLeft = i % 2 == 0)), f.node)
        }

        back = part(BlockButton(kit, L(R.string.hub_back), "hub_back_button", BlockButton.Style.QUIET, 0.5f, 0.3f, 0.09f) {
            go(SketchScreenId.TITLE)
        }, f.node)
        back.rest.set(at(-0.62f, f.bottom + 0.34f))
        playMatch = part(BlockButton(kit, L(R.string.hub_play), "hub_play_button", BlockButton.Style.PRIMARY, 1.1f, 0.36f, 0.13f) {
            go(SketchScreenId.MATCH)
        }, f.node)
        playMatch.rest.set(at(0.3f, f.bottom + 0.34f))
        playMatch.bobs = true
    }

    private fun texts(i: Int, s: SketchStanding) =
        listOf("${i + 1}", s.code, "${s.played}", if (s.goalDiff > 0) "+${s.goalDiff}" else "${s.goalDiff}", "${s.points}")

    /**
     * After the match: the next time the hub arrives, the rows land in their old places, take
     * their new numbers and spring to their new ranks.
     */
    fun applyMatchday() { reshuffle = true }

    override fun show(after: Double) {
        super.show(after)
        if (!reshuffle) return
        reshuffle = false
        stage.after(after + 2.2) {
            standings = SketchData.after
            for ((i, s) in standings.withIndex()) {
                val row = rows[s.code] ?: continue
                row.set(texts(i, s))
                row.move(rowY[i])
                if (s.code != SketchData.PLAYER) row.recolour(if (i % 2 == 0) Colour.ROW_LIGHT else Colour.ROW_DARK)
            }
            fixture.celebrate(0.5)
        }
    }
}
