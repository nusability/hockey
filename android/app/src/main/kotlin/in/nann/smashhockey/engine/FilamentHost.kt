package `in`.nann.smashhockey.engine

import android.view.Choreographer
import android.view.Surface
import android.view.SurfaceView
import com.google.android.filament.Camera
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.DisplayHelper
import com.google.android.filament.android.UiHelper

/**
 * Owns Filament and the one clock (ADR 0005): a single Choreographer callback hands the frame's
 * elapsed time to [onFrame] — which steps the simulation and the UI — and then renders once.
 * There is no second loop anywhere; everything that moves reads this frame.
 *
 * The surface is an opaque SurfaceView: the sky is drawn in the scene, so nothing needs to show
 * through it, and the cheaper surface can be used.
 */
class FilamentHost(
    private val surfaceView: SurfaceView,
    private val onFrame: (dtSeconds: Double, frameTimeNanos: Long) -> Unit,
) : Choreographer.FrameCallback {
    val engine: Engine = Engine.create()
    val renderer: Renderer = engine.createRenderer()
    val scene: Scene = engine.createScene()
    val view: View = engine.createView()
    val camera: Camera = engine.createCamera(EntityManager.get().create())

    var width = 1
        private set
    var height = 1
        private set
    var onResize: ((Int, Int) -> Unit)? = null

    private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
    private val displayHelper = DisplayHelper(surfaceView.context)
    private val choreographer = Choreographer.getInstance()
    private var swapChain: SwapChain? = null
    private var lastFrameNanos = 0L
    private var running = false

    init {
        view.scene = scene
        view.camera = camera
        renderer.clearOptions = renderer.clearOptions.apply {
            clear = true
            clearColor = doubleArrayOf(0.0, 0.0, 0.0, 1.0)
        }
        uiHelper.renderCallback = object : UiHelper.RendererCallback {
            override fun onNativeWindowChanged(surface: Surface) {
                swapChain?.let { engine.destroySwapChain(it) }
                swapChain = engine.createSwapChain(surface)
                displayHelper.attach(renderer, surfaceView.display)
                RefreshRate.request(surface, surfaceView.display)   // 90/120 Hz where the display has it
            }

            override fun onDetachedFromSurface() {
                displayHelper.detach()
                swapChain?.let {
                    engine.destroySwapChain(it)
                    engine.flushAndWait()
                    swapChain = null
                }
            }

            override fun onResized(width: Int, height: Int) {
                this@FilamentHost.width = width
                this@FilamentHost.height = height
                view.viewport = Viewport(0, 0, width, height)
                onResize?.invoke(width, height)
            }
        }
        uiHelper.attachTo(surfaceView)
    }

    fun start() {
        if (running) return
        running = true
        lastFrameNanos = 0L
        choreographer.postFrameCallback(this)
    }

    fun stop() {
        running = false
        choreographer.removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        choreographer.postFrameCallback(this)
        val dt = if (lastFrameNanos == 0L) 0.0 else (frameTimeNanos - lastFrameNanos) / 1e9
        lastFrameNanos = frameTimeNanos
        onFrame(dt, frameTimeNanos)
        val chain = swapChain ?: return
        if (!uiHelper.isReadyToRender) return
        if (renderer.beginFrame(chain, frameTimeNanos)) {
            renderer.render(view)
            renderer.endFrame()
        }
    }

    fun destroy() {
        stop()
        uiHelper.detach()
        engine.destroyRenderer(renderer)
        engine.destroyView(view)
        engine.destroyScene(scene)
        engine.destroyCameraComponent(camera.entity)
        EntityManager.get().destroy(camera.entity)
        engine.destroy()
    }
}
