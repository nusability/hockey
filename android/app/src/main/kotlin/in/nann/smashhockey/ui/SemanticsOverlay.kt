package `in`.nann.smashhockey.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntOffset
import kotlin.math.roundToInt

/**
 * The derived accessibility layer (ADR 0005) — the twin of iOS's `SemanticsOverlay`: one
 * invisible element per projected 3D node, generated from the nodes' own declarations every frame
 * — never hand-placed. It takes no touches (no pointer input anywhere in it); fingers reach the 3D
 * surface and the stage's hit-test. Ids are test tags, exposed as resource ids by the host.
 */
@Composable
fun SemanticsOverlay(stage: UIStage) {
    val nodes = stage.semanticsNodes.value
    val density = LocalDensity.current
    Box(Modifier.fillMaxSize()) {
        for (n in nodes) key(n.id) {
            val w = with(density) { (n.right - n.left).toDp() }
            val h = with(density) { (n.bottom - n.top).toDp() }
            Box(
                Modifier
                    .offset { IntOffset(n.left, n.top) }
                    .size(w, h)
                    .testTag(n.id)
                    .semantics {
                        contentDescription = n.label
                        when (n.trait) {
                            Semantics.Trait.BUTTON -> {
                                role = Role.Button
                                if (!n.isEnabled) disabled()
                                onClick { stage.activate(n.id); true }
                            }
                            Semantics.Trait.ADJUSTABLE -> {
                                // A 0–100 % value TalkBack nudges in the slider's own steps.
                                val v = n.value?.removeSuffix("%")?.toFloatOrNull()?.div(100f) ?: 0f
                                stateDescription = n.value ?: ""
                                progressBarRangeInfo = ProgressBarRangeInfo(v, 0f..1f, steps = 19)
                                setProgress { target ->
                                    val steps = ((target - v) / 0.05f).roundToInt()
                                    if (steps != 0) stage.adjust(n.id, steps)
                                    true
                                }
                            }
                            Semantics.Trait.HEADER -> heading()
                            Semantics.Trait.STATIC_TEXT -> n.value?.let { stateDescription = it }
                        }
                    },
            )
        }
    }
}
