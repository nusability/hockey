package `in`.nann.smashhockey

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.MotionEvent
import android.view.SurfaceView
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

/**
 * One opaque 3D surface with everything drawn in it (ADR 0005), and above it a transparent
 * semantics overlay: invisible accessibility elements projected from the 3D UI every frame. The
 * overlay takes no touches — taps reach the surface and our own hit-test.
 */
class MainActivity : ComponentActivity() {
    private var scene: SpikeScene? = null
    private val buttonRect = mutableStateOf<ScreenRect?>(null)

    @OptIn(ExperimentalComposeUiApi::class)
    @SuppressLint("ClickableViewAccessibility")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        Utils.init()
        val surface = SurfaceView(this)
        val spike = SpikeScene(this, surface) { buttonRect.value = it }
        scene = spike
        surface.setOnTouchListener { _, e ->
            if (e.actionMasked == MotionEvent.ACTION_DOWN) spike.tap(e.x, e.y)
            true
        }
        setContent {
            Box(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                AndroidView(factory = { surface }, modifier = Modifier.fillMaxSize())
                buttonRect.value?.let { r ->
                    val density = LocalDensity.current
                    Box(
                        Modifier
                            .offset { IntOffset(r.left, r.top) }
                            .size(with(density) { (r.right - r.left).toDp() }, with(density) { (r.bottom - r.top).toDp() })
                            .testTag("menu_play_button")
                            .semantics {
                                contentDescription = spike.buttonLabelText
                                role = Role.Button
                                onClick { spike.press(); true }
                            },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        scene?.start()
    }

    override fun onPause() {
        scene?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        scene?.destroy()
        scene = null
        super.onDestroy()
    }
}
