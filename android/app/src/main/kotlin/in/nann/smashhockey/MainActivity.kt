package `in`.nann.smashhockey

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.MotionEvent
import android.view.SurfaceView
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.viewinterop.AndroidView
import com.google.android.filament.utils.Utils
import `in`.nann.smashhockey.spike.ScreenRect
import `in`.nann.smashhockey.spike.SpikeScene
import `in`.nann.smashhockey.scene.MatchPlan
import `in`.nann.smashhockey.scene.MatchScene
import `in`.nann.smashhockey.sketch.SketchScene
import `in`.nann.smashhockey.ui.SemanticsOverlay
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat

/**
 * One opaque 3D surface with everything drawn in it (ADR 0005), and above it a transparent
 * semantics overlay: invisible accessibility elements projected from the 3D UI every frame. The
 * overlay takes no touches — they reach the surface and our own hit-test.
 *
 * Until the menus exist the intent picks the scene: `--es scene match` (with `quick`, `drill` or
 * `demo`, see [MatchPlan]) shows the match; `--es scene spike` the renderer spike (SMASH-2); no
 * extras open the SMASH-5 motion sketch, like iOS (`--ez sketchAutoplay true` walks it by itself,
 * `--ez sketchReduceMotion true` shows its calm path).
 */
class MainActivity : ComponentActivity() {
    private var spike: SpikeScene? = null
    private var match: MatchScene? = null
    private var sketch: SketchScene? = null
    private val buttonRect = mutableStateOf<ScreenRect?>(null)
    private val pausedState = mutableStateOf(false)

    @OptIn(ExperimentalComposeUiApi::class)
    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // A game in front holds the screen on; the system still sleeps it when the app leaves.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        Utils.init()
        val surface = SurfaceView(this)
        val plan = MatchPlan.fromIntent(intent)
        val label: String
        val tag: String
        val action: () -> Unit
        if (plan != null) {
            val m = MatchScene(this, surface, plan, MatchPlan.seed(intent)) { r, p -> buttonRect.value = r; pausedState.value = p }
            match = m
            surface.setOnTouchListener { _, e -> m.onTouch(e) }
            ViewCompat.setOnApplyWindowInsetsListener(surface) { _, insets ->
                m.setSafeTop(insets.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout()).top)
                insets
            }
            label = getString(R.string.pause_title)
            tag = "match_pause_button"
            action = { m.togglePause() }
        } else if (intent.getStringExtra("scene") != "spike") {
            val s = SketchScene(this, surface, intent.getBooleanExtra("sketchAutoplay", false),
                intent.getBooleanExtra("sketchReduceMotion", false))
            sketch = s
            surface.setOnTouchListener { _, e -> s.onTouch(e) }
            setContent {
                Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                    AndroidView(factory = { surface }, modifier = Modifier.fillMaxSize())
                    s.stage.value?.let { SemanticsOverlay(it) }
                }
            }
            return
        } else {
            val s = SpikeScene(this, surface) { buttonRect.value = it }
            spike = s
            surface.setOnTouchListener { _, e ->
                if (e.actionMasked == MotionEvent.ACTION_DOWN) s.tap(e.x, e.y)
                true
            }
            label = s.buttonLabelText
            tag = "menu_play_button"
            action = { s.press() }
        }
        setContent {
            Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                AndroidView(factory = { surface }, modifier = Modifier.fillMaxSize())
                buttonRect.value?.let { r ->
                    val density = LocalDensity.current
                    val text = if (plan != null && pausedState.value) getString(R.string.pause_resume) else label
                    Box(
                        Modifier
                            .offset { IntOffset(r.left, r.top) }
                            .size(with(density) { (r.right - r.left).toDp() }, with(density) { (r.bottom - r.top).toDp() })
                            .testTag(tag)
                            .semantics {
                                contentDescription = text
                                role = Role.Button
                                onClick { action(); true }
                            },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        spike?.start()
        match?.start()
        sketch?.start()
    }

    override fun onPause() {
        match?.setPaused(true)          // §8.7: leaving the foreground pauses the match
        match?.stop()
        spike?.stop()
        sketch?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        spike?.destroy()
        match?.destroy()
        sketch?.destroy()
        sketch = null
        spike = null
        match = null
        super.onDestroy()
    }
}
