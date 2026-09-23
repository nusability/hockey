package `in`.nann.smashhockey

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.SurfaceView
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.filament.utils.Utils
import `in`.nann.smashhockey.engine.RefreshRate
import `in`.nann.smashhockey.game.Game
import `in`.nann.smashhockey.game.Keyboard
import `in`.nann.smashhockey.game.Launch
import `in`.nann.smashhockey.ui.SemanticsOverlay

/**
 * One opaque 3D surface with everything drawn in it (ADR 0005), and above it a transparent
 * semantics overlay — invisible accessibility elements projected from the 3D UI every frame — and
 * a hidden text field that brings up the system keyboard for the create screen (§16.1). The overlay
 * takes no touches: they reach the surface, the stage's own hit-test, and the match's finger.
 *
 * A player's launch opens on the save. The developer shortcuts are intent extras — see [Launch]
 * (`--es scene match --es quick …` or `--ei drill N`).
 */
class MainActivity : ComponentActivity() {
    private var game: Game? = null

    @OptIn(ExperimentalComposeUiApi::class)
    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A game in front holds the screen on; the system still sleeps it when the app leaves.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        RefreshRate.prefer(this)       // the display's highest refresh; the simulation keeps its fixed ticks (§4)
        Utils.init()
        val surface = SurfaceView(this)
        val g = Game(this, surface, Launch.plan(intent))
        game = g
        surface.setOnTouchListener { _, e -> g.onTouch(e) }
        setContent {
            Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                AndroidView(factory = { surface }, modifier = Modifier.fillMaxSize())
                g.stageRef.value?.let { SemanticsOverlay(it) }
                KeyboardField(g.keyboard)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        game?.start()
    }

    override fun onPause() {
        game?.pause(true)          // §8.7: leaving the foreground pauses the match
        // The other of the two moments anything is sent (§18.8): the app is leaving.
        game?.let { it.telemetry.flush(it.device.installId) }
        game?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        game?.destroy()
        game = null
        super.onDestroy()
    }
}

/** The hidden field the system keyboard types into: focused while a field is edited; done or losing focus ends it. */
@Composable
private fun KeyboardField(keyboard: Keyboard) {
    val field = keyboard.field.value
    val focus = remember { FocusRequester() }
    val ime = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    BasicTextField(
        value = keyboard.text.value,
        onValueChange = { keyboard.typed(it) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            capitalization = if (field == Keyboard.Field.CODE) KeyboardCapitalization.Characters else KeyboardCapitalization.Words,
            autoCorrectEnabled = false,
            imeAction = ImeAction.Done,
        ),
        keyboardActions = KeyboardActions(onDone = { keyboard.end() }),
        modifier = Modifier
            .size(1.dp)
            .alpha(0f)
            .focusRequester(focus)
            .onFocusChanged { if (!it.isFocused) keyboard.end() }
            .clearAndSetSemantics {},
    )
    LaunchedEffect(field) {
        if (field != null) {
            focus.requestFocus()
            ime?.show()
        } else {
            focusManager.clearFocus()
            ime?.hide()
        }
    }
}
