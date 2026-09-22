package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.Club
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.season.CreatedTeamRules
import `in`.nann.smashhockey.core.season.chooseClub
import `in`.nann.smashhockey.core.season.createTeam
import `in`.nann.smashhockey.core.season.startSeason
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.MatchPlan
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.ui.BlockButton
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.Tile
import `in`.nann.smashhockey.ui.WaveText

/**
 * First launch (spec §16.1, §2.2) — the twin of iOS's TeamScreen.swift: the game opens here, once,
 * until a career exists. Two ways — pick one of the eight clubs from its card (name, kit, home
 * world, strength), or create a team ([TeamForm]). Confirming starts the career and its first
 * season, saved before the hub appears. Training and quick match are a tap away without choosing.
 */
class TeamScreen(game: Game) : Screen(Game.pose(Presentation.Screens.Team.eye, Presentation.Screens.Team.target), game) {
    private val pickTab: Tile
    private val createTab: Tile
    private val confirm: BlockButton
    private val cards = LinkedHashMap<Club, Tile>()
    private val pickParts = ArrayList<Presentable>()
    private val form: TeamForm
    private var creating = false
    private var picked: Club? = null

    init {
        part(WaveText(kit, L(CopyKey.TEAM_TITLE), 0.17f, C.CREAM, bob = 0.6f, id = "team_title_header"), at(0f, top - 0.2f))
        pickTab = part(tab(L(CopyKey.TEAM_PICK), "team_pick_button") { switchTo(false) }, at(-0.45f, top - 0.52f))
        createTab = part(tab(L(CopyKey.TEAM_CREATE), "team_create_button") { switchTo(true) }, at(0.45f, top - 0.52f))
        pickTab.isSelected = true

        // The content fills what the tabs and the buttons leave.
        val contentTop = top - 0.72f
        val contentBottom = bottom + 0.98f
        val pitch = minOf(0.46f, (contentTop - contentBottom) / 4)
        for ((i, club) in Club.entries.withIndex()) {
            val x = if (i % 2 == 0) -0.45f else 0.45f
            val y = contentTop - pitch * (i / 2 + 0.5f)
            val card = child(clubCard(club, pitch - 0.05f), at(x, y), layer)
            cards[club] = card
            pickParts += card
        }
        form = TeamForm(this, contentTop) { refresh() }
        confirm = part(BlockButton(kit, L(CopyKey.TEAM_CHOOSE), "team_confirm_button", BlockButton.Style.PRIMARY, 1.5f, 0.36f, 0.13f) {
            confirmed()
        }, at(0f, bottom + 0.72f))
        part(BlockButton(kit, L(CopyKey.TITLE_TRAINING), "team_training_button", BlockButton.Style.QUIET, 0.84f, 0.28f, 0.09f) {
            game.go(Game.Place.Training(null))
        }, at(-0.45f, bottom + 0.3f))
        part(BlockButton(kit, L(CopyKey.TITLE_QUICK), "team_quick_button", BlockButton.Style.QUIET, 0.84f, 0.28f, 0.09f) {
            playQuick(game)
        }, at(0.45f, bottom + 0.3f))
        refresh()
    }

    private fun tab(title: String, id: String, action: () -> Unit): Tile {
        val t = Tile(kit, 0.86f, 0.26f, C.CREAM, C.TEAL, id = id, label = title, action = action)
        letters(title, 0.075f, C.INK, maxWidth = 0.76f, parent = t.content)
        return t
    }

    /** A club's card: its kit with the short code, its name, its home world and its strength. */
    private fun clubCard(club: Club, h: Float): Tile {
        val label = "${L(club.nameKey)}, ${L(club.world.nameKey)}, ${L(CopyKey.TEAM_STRENGTH, club.rating)}"
        val card = Tile(kit, 0.86f, h, C.CREAM, id = "team_club_${club.key}_button", label = label) { pick(club) }
        val chipH = minOf(0.3f, h * 0.72f)
        kit.slab(0.24f, chipH, 0.05f, club.primary, card.content, corner = 0.03f).setPosition(-0.28f, 0f, 0.02f)
        kit.slab(0.05f, chipH + 0.005f, 0.055f, club.secondary, card.content, corner = 0.005f).setPosition(-0.36f, 0f, 0.022f)
        letters(club.short, 0.07f, club.secondary, maxWidth = 0.16f, x = -0.26f, z = 0.05f, parent = card.content)
        letters(Names.team(TeamKey.of(club), null), 0.05f, C.INK, maxWidth = 0.5f, align = Label3D.Align.LEADING,
            x = -0.13f, y = h * 0.2f, parent = card.content)
        letters(Names.world(club.world), 0.034f, C.TEAL_SHADE, maxWidth = 0.5f, align = Label3D.Align.LEADING,
            x = -0.13f, parent = card.content)
        // Strength: the rating across the clubs' range (§2.1's skill, 60…90).
        kit.slab(0.5f, 0.035f, 0.02f, C.CREAM_SHADE, card.content, corner = 0.012f).setPosition(0.12f, -h * 0.24f, 0.01f)
        val share = ((club.rating - 60) / 30.0).coerceIn(0.05, 1.0).toFloat()
        kit.slab(0.5f * share, 0.045f, 0.03f, C.CORAL, card.content, corner = 0.015f).setPosition(-0.13f + 0.25f * share, -h * 0.24f, 0.015f)
        return card
    }

    override fun show(after: Double) {
        super.show(after)
        val stagger = motion.staggerSeconds * 1.6
        for ((i, p) in (if (creating) form.parts else pickParts).withIndex()) p.show(after + 0.2 + i * stagger * 0.5)
    }

    override fun leave() {
        for (p in pickParts + form.parts) p.hide(0.0)
        super.leave()
    }

    private fun switchTo(c: Boolean) {
        if (c == creating) return
        creating = c
        pickTab.isSelected = !c
        createTab.isSelected = c
        game.keyboard.end()
        val stagger = motion.staggerSeconds
        for ((i, p) in (if (c) pickParts else form.parts).withIndex()) p.hide(i * stagger * 0.3)
        for ((i, p) in (if (c) form.parts else pickParts).withIndex()) p.show(0.25 + i * stagger * 0.6)
        refresh()
    }

    private fun pick(club: Club) {
        picked = club
        for ((c, card) in cards) card.isSelected = c == club
        refresh()
    }

    /** The confirm button says what it would do, and can only do it when the choice is valid. */
    private fun refresh() {
        val p = picked
        if (creating) {
            val issues = CreatedTeamRules.issues(form.draft)
            val name = CreatedTeamRules.trimmedName(form.draft.name).uppercase()
            confirm.retitle(L(CopyKey.TEAM_CONFIRM, name.ifEmpty { form.draft.short }))
            confirm.isEnabled = issues.isEmpty()
        } else if (p != null) {
            confirm.retitle(L(CopyKey.TEAM_CONFIRM, Names.team(TeamKey.of(p), null)))
            confirm.isEnabled = true
        } else {
            confirm.retitle(L(CopyKey.TEAM_CHOOSE))
            confirm.isEnabled = false
        }
        confirm.bobs = confirm.isEnabled
    }

    /** Starts the career and its first season (§2.2), saved before the hub appears (§15). */
    private fun confirmed() {
        val seed = MatchPlan.seed()
        val club = picked
        val ok = when {
            creating -> { val draft = form.draft; game.commit { it.createTeam(draft).startSeason(seed) } }
            club != null -> game.commit { it.chooseClub(club).startSeason(seed) }
            else -> false
        }
        if (ok) game.go(Game.Place.Hub)
    }
}
