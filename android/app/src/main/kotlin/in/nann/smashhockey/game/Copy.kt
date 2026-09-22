package `in`.nann.smashhockey.game

import android.annotation.SuppressLint
import android.content.Context
import `in`.nann.smashhockey.core.generated.CareerRecord
import `in`.nann.smashhockey.core.generated.CopyKey
import `in`.nann.smashhockey.core.generated.CupRound
import `in`.nann.smashhockey.core.generated.MatchdayStep
import `in`.nann.smashhockey.core.generated.TeamKey
import `in`.nann.smashhockey.core.generated.World
import kotlin.math.ceil

/**
 * The declared copy (spec §14, shared/data/copy.toml → strings.xml): a key and its placeholders,
 * in the order the English names them. Every word on screen comes through here — the twin of
 * iOS's `L`. The resource is found by the key's generated name, once, and fails loud if missing.
 */
object Copy {
    private lateinit var context: Context
    private val ids = HashMap<CopyKey, Int>()

    fun init(context: Context) { this.context = context.applicationContext }

    @SuppressLint("DiscouragedApi")
    fun text(key: CopyKey, vararg args: Any): String {
        val id = ids.getOrPut(key) {
            context.resources.getIdentifier(key.resourceName, "string", context.packageName).also {
                check(it != 0) { "copy '${key.key}' has no string resource — run tools/generate-data.py" }
            }
        }
        return if (args.isEmpty()) context.getString(id) else context.getString(id, *args.map { it.toString() }.toTypedArray())
    }
}

fun L(key: CopyKey, vararg args: Any): String = Copy.text(key, *args)

/** Names the screens show, from the career or the declarations — the twin of iOS's `Names`. */
object Names {
    /** A team's name in capitals: a club's localized name, or the created team's own. */
    fun team(key: TeamKey, career: CareerRecord?): String =
        key.club?.let { L(it.nameKey).uppercase() } ?: career?.created?.name?.uppercase() ?: ""

    fun world(w: World): String = L(w.nameKey).uppercase()

    /** "1ST", "2ND", "3RD", "4TH"… (§16.3's place in the league). */
    fun ordinal(n: Int): String = when (n) {
        1 -> L(CopyKey.ORD_1)
        2 -> L(CopyKey.ORD_2)
        3 -> L(CopyKey.ORD_3)
        else -> L(CopyKey.ORD_N, n)
    }

    /** A matchday's label: league round or cup round (§11.1). */
    fun matchday(step: MatchdayStep): String = when (step) {
        is MatchdayStep.League -> L(CopyKey.HUB_LEAGUE, step.round)
        is MatchdayStep.Cup -> L(CopyKey.HUB_CUP, cupRound(step.round))
    }

    fun cupRound(r: CupRound): String = when (r) {
        CupRound.QUARTER_FINAL -> L(CopyKey.HUB_QUARTER_FINAL)
        CupRound.SEMI_FINAL -> L(CopyKey.HUB_SEMI_FINAL)
        CupRound.FINAL -> L(CopyKey.HUB_FINAL)
    }

    /** m:ss, rounded up — the HUD's clock (§8.3). */
    fun clock(seconds: Double): String {
        val s = maxOf(0, ceil(seconds).toInt())
        return "${s / 60}:${(s % 60).toString().padStart(2, '0')}"
    }
}
