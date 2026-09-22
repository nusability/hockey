package `in`.nann.smashhockey.screens

import `in`.nann.smashhockey.core.generated.Career
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.season.CreatedTeamRules
import `in`.nann.smashhockey.core.season.TeamDraft
import `in`.nann.smashhockey.core.season.TeamIssue
import `in`.nann.smashhockey.game.Keyboard
import `in`.nann.smashhockey.game.L
import `in`.nann.smashhockey.game.Names
import `in`.nann.smashhockey.ui.KitDisk
import `in`.nann.smashhockey.ui.Label3D
import `in`.nann.smashhockey.ui.Presentable
import `in`.nann.smashhockey.ui.Tile
import `in`.nann.smashhockey.ui.UiNode

/**
 * Creating a team (spec §16.1, §2.2) — the twin of iOS's TeamForm.swift: the name through the
 * system keyboard, the short code derived from it and editable, the kit's shirt and trim from the
 * twelve palette pairs, the home world, and a live preview disk wearing the kit. Every rule the
 * draft breaks is named under it. Part of the team screen, shown on its "create" tab.
 */
class TeamForm(private val screen: Screen, top: Float, private val changed: () -> Unit) {
    var draft: TeamDraft
        private set
    /** Everything of the form, in arrival order; the screen shows and hides it with its tab. */
    val parts = ArrayList<Presentable>()
    private val kit = screen.kit
    private val keyboard = screen.game.keyboard
    /** The code follows the name until the player types one of their own. */
    private var codeEdited = false
    private val nameField: Tile
    private val nameText: UiNode
    private val codeField: Tile
    private val codeText: UiNode
    private val disk: KitDisk
    private val shirts = ArrayList<Tile>()
    private val trims = ArrayList<Tile>()
    private val worlds = LinkedHashMap<World, Tile>()
    private val issues: Label3D

    init {
        val pair = Career.kitPalette[9]
        draft = TeamDraft("", "", pair.primary, pair.secondary, World.MAGICWOOD)
        var y = top - 0.13f

        nameField = add(Tile(kit, 1.72f, 0.24f, C.CREAM, C.CREAM, id = "team_name_field", label = L(CopyKey.TEAM_NAME)) { editName() }, y = y)
        screen.letters(L(CopyKey.TEAM_NAME), 0.034f, C.TEAL_SHADE, align = Label3D.Align.LEADING, x = -0.8f, y = 0.07f, parent = nameField.content)
        nameText = screen.letters(L(CopyKey.TEAM_NAME_EMPTY), 0.085f, C.DISABLED_INK, maxWidth = 1.5f, y = -0.02f, parent = nameField.content)
        y -= 0.33f

        codeField = add(Tile(kit, 0.66f, 0.26f, C.CREAM, C.CREAM, id = "team_code_field", label = L(CopyKey.TEAM_CODE)) { editCode() },
            x = -0.52f, y = y)
        screen.letters(L(CopyKey.TEAM_CODE), 0.034f, C.TEAL_SHADE, align = Label3D.Align.LEADING, x = -0.29f, y = 0.08f, parent = codeField.content)
        codeText = screen.letters("XXX", 0.11f, C.INK, y = -0.025f, parent = codeField.content)
        disk = add(KitDisk(kit, 0.13f, draft.primary, draft.secondary), x = 0.42f, y = y - 0.02f)
        y -= 0.25f

        add(Label3D(kit, L(CopyKey.TEAM_SHIRT), 0.04f, C.CREAM, Label3D.Align.LEADING), x = -0.86f, y = y)
        y -= 0.13f
        for ((i, p) in Career.kitPalette.withIndex()) {
            shirts += add(Tile(kit, 0.12f, 0.12f, p.primary, p.primary, halo = true, id = "team_shirt_${p.id}_button",
                label = L(p.primaryName)) { draft = draft.copy(primary = p.primary); refresh() }, x = -0.83f + i * 0.151f, y = y)
        }
        y -= 0.16f
        add(Label3D(kit, L(CopyKey.TEAM_TRIM), 0.04f, C.CREAM, Label3D.Align.LEADING), x = -0.86f, y = y)
        y -= 0.13f
        for ((i, p) in Career.kitPalette.withIndex()) {
            trims += add(Tile(kit, 0.12f, 0.12f, p.secondary, p.secondary, halo = true, id = "team_trim_${p.id}_button",
                label = L(p.secondaryName)) { draft = draft.copy(secondary = p.secondary); refresh() }, x = -0.83f + i * 0.151f, y = y)
        }
        y -= 0.16f
        add(Label3D(kit, L(CopyKey.TEAM_HOME), 0.04f, C.CREAM, Label3D.Align.LEADING), x = -0.86f, y = y)
        y -= 0.15f
        for ((i, w) in World.entries.withIndex()) {
            val t = add(Tile(kit, 0.33f, 0.2f, C.CREAM, C.SUN, id = "team_world_${w.key}_button", label = L(w.nameKey)) {
                draft = draft.copy(world = w); refresh()
            }, x = -0.72f + i * 0.36f, y = y)
            screen.letters(Names.world(w), 0.032f, C.INK, maxWidth = 0.29f, parent = t.content)
            worlds[w] = t
        }
        y -= 0.19f
        issues = add(Label3D(kit, " ", 0.042f, C.CORAL, maxWidth = 1.72f), y = y)
        refresh(notify = false)
    }

    private fun <E : Presentable> add(e: E, x: Float = 0f, y: Float): E {
        screen.child(e, at(x, y), screen.layer)
        parts += e
        return e
    }

    // ---------------------------------------------------------------- editing

    private fun editName() {
        keyboard.begin(Keyboard.Field.NAME, draft.name, { text ->
            draft = draft.copy(name = text.take(Career.nameMaxLength + 8))
            if (!codeEdited) draft = draft.copy(short = CreatedTeamRules.suggestedShortCode(draft.name))
            refresh()
        }) { refresh() }
        refresh()
    }

    private fun editCode() {
        keyboard.begin(Keyboard.Field.CODE, draft.short, { text ->
            val code = text.uppercase().filter { it in 'A'..'Z' }.take(Career.shortCodeLength)
            codeEdited = true
            draft = draft.copy(short = code)
            if (code != text) keyboard.text.value = code
            refresh()
        }) { refresh() }
        refresh()
    }

    /** Everything the draft shows: the fields, the chosen swatches and world, the disk, the issues. */
    private fun refresh(notify: Boolean = true) {
        val editing = keyboard.field.value
        nameField.isSelected = editing == Keyboard.Field.NAME
        codeField.isSelected = editing == Keyboard.Field.CODE
        val name = draft.name
        screen.reletter(nameText, if (name.isEmpty()) L(CopyKey.TEAM_NAME_EMPTY) else name.uppercase(), 0.085f, maxWidth = 1.5f, y = -0.02f)
        nameText.childNodes.first().recolour(if (name.isEmpty()) C.DISABLED_INK else C.INK)
        nameField.relabel("${L(CopyKey.TEAM_NAME)}, $name")
        screen.reletter(codeText, draft.short.ifEmpty { "–" }, 0.11f, y = -0.025f)
        codeField.relabel("${L(CopyKey.TEAM_CODE)}, ${draft.short}")
        for ((t, p) in shirts.zip(Career.kitPalette)) t.isSelected = p.primary == draft.primary
        for ((t, p) in trims.zip(Career.kitPalette)) t.isSelected = p.secondary == draft.secondary
        for ((w, t) in worlds) t.isSelected = w == draft.world
        disk.recolour(draft.primary, draft.secondary)
        val problems = CreatedTeamRules.issues(draft).map(::text)
        issues.set(if (problems.isEmpty()) " " else problems.joinToString(" · "))
        if (notify) changed()
    }

    companion object {
        fun text(issue: TeamIssue): String = when (issue) {
            TeamIssue.NAME_TOO_SHORT -> L(CopyKey.TEAM_ISSUE_NAME_TOO_SHORT)
            TeamIssue.NAME_TOO_LONG -> L(CopyKey.TEAM_ISSUE_NAME_TOO_LONG)
            TeamIssue.SHORT_CODE_NOT_THREE_LETTERS -> L(CopyKey.TEAM_ISSUE_SHORT_CODE_NOT_THREE_LETTERS)
            TeamIssue.SHORT_CODE_IS_A_CLUBS -> L(CopyKey.TEAM_ISSUE_SHORT_CODE_IS_ACLUBS)
            TeamIssue.PRIMARY_NOT_IN_PALETTE -> L(CopyKey.TEAM_ISSUE_PRIMARY_NOT_IN_PALETTE)
            TeamIssue.SECONDARY_NOT_IN_PALETTE -> L(CopyKey.TEAM_ISSUE_SECONDARY_NOT_IN_PALETTE)
        }
    }
}
