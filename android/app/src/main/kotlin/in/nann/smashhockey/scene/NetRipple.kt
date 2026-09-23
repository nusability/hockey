package `in`.nann.smashhockey.scene

import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.engine.DynamicMesh
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.generated.Presentation
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * The nets' light sheets, their cloth sway and their ripple (spec §8.8) — the twin of iOS's
 * NetRipple.swift. Each goal has a back sheet (the net's depth behind the line, the mouth's width,
 * `net.height` tall) and a roof, a grid of `net.columns` × `net.rows` cells at `net.opacity`.
 *
 * A net is cloth, so it always breathes: every point sways along its sheet's outward normal by
 * `sway.amplitude × bell × sin(2π·t / sway.seconds + sway.wave·(x + z))`, `bell` being
 * `sin(π·u)·sin(π·v)` over the sheet's grid — nothing at the edges it is laced to, most in the
 * middle. Reduce Motion keeps `sway.reduce_motion` of it: calmer, never frozen.
 *
 * On a goal the scored-in net's sheets additionally bulge outward (back: away from the pitch, roof:
 * up) in a damped wave from where the ball struck, for `net.seconds` of real time.
 */
class NetRipple(private val engine: Engine, private val scene: Scene, private val parent: Int, private val materials: Materials) {
    private val n = Presentation.Net
    private val sway = Presentation.Net.Sway
    private val cols = n.columns; private val rows = n.rows
    private val perSheet = (cols + 1) * (rows + 1)
    private val material = materials.flatOwned(n.colour)
    private val half = Tuning.Pitch.goalMouthWidth / 2
    private val line = Tuning.Pitch.goalLineZ
    private val depth = Tuning.Pitch.goalDepth

    private inner class Net(val sign: Double) {
        val rest = FloatArray(perSheet * 2 * 3)
        val normal = FloatArray(perSheet * 2 * 3)
        val xyz = FloatArray(rest.size)
        /** How freely each point may sway: 0 where the net is laced to its frame, 1 in the middle. */
        val bell = DoubleArray(perSheet * 2)
        /** Where each point sits in the travelling wave, radians. */
        val phase = DoubleArray(perSheet * 2)
        val mesh: DynamicMesh
        var age = Double.POSITIVE_INFINITY
        var strikeX = 0.0

        init {
            var k = 0
            fun put(x: Double, y: Double, z: Double, nx: Double, ny: Double, nz: Double, u: Double, v: Double) {
                rest[k] = x.toFloat(); rest[k + 1] = y.toFloat(); rest[k + 2] = z.toFloat()
                normal[k] = nx.toFloat(); normal[k + 1] = ny.toFloat(); normal[k + 2] = nz.toFloat()
                bell[k / 3] = sin(PI * u) * sin(PI * v)
                phase[k / 3] = sway.wave * (x + z)
                k += 3
            }
            val back = sign * (line + depth)
            for (j in 0..rows) for (i in 0..cols) {          // the back: x across, y up
                put(-half + 2 * half * i / cols, n.height * j / rows, back, 0.0, 0.0, sign,
                    i.toDouble() / cols, j.toDouble() / rows)
            }
            for (j in 0..rows) for (i in 0..cols) {          // the roof: x across, z from the line out
                put(-half + 2 * half * i / cols, n.height, sign * (line + depth * j / rows), 0.0, 1.0, 0.0,
                    i.toDouble() / cols, j.toDouble() / rows)
            }
            rest.copyInto(xyz)
            val idx = ArrayList<Int>()
            for (s in 0..1) for (j in 0 until rows) for (i in 0 until cols) {
                val a = s * perSheet + j * (cols + 1) + i
                val b = a + 1; val c = a + cols + 1; val d = c + 1
                idx += listOf(a, b, d, a, d, c)
            }
            mesh = DynamicMesh(engine, perSheet * 2, idx.toIntArray(), material, withUv = false,
                bounds = Box(0f, 1f, sign.toFloat() * 27f, 4f, 2f, 2f), priority = 5)
            mesh.update(xyz)
            mesh.draw(idx.size)
            scene.addEntity(mesh.entity)
            val tm = engine.transformManager
            if (!tm.hasComponent(mesh.entity)) tm.create(mesh.entity)
            tm.setParent(tm.getInstance(mesh.entity), tm.getInstance(parent))
        }

        /** One frame of real time: the cloth sways always, a goal's ripple rides on top of it. */
        fun advance(swayAmplitude: Double, swayPhase: Double, dt: Double) {
            val rippling = age < n.seconds
            if (rippling) age += dt
            val t = age
            val sx = strikeX; val sy = 0.36; val sz = sign * (line + depth)
            val env = if (!rippling || t >= n.seconds) 0.0 else n.amplitude * exp(-n.decay * t)
            for (v in 0 until perSheet * 2) {
                val k = v * 3
                var d = swayAmplitude * bell[v] * sin(swayPhase + phase[v])
                if (env != 0.0) {
                    val dx = rest[k] - sx; val dy = rest[k + 1] - sy; val dz = rest[k + 2] - sz
                    val r = sqrt(dx * dx + dy * dy + dz * dz)
                    d += env * sin(n.frequency * t - n.k * r) * exp(-r / n.reach)
                }
                for (a in 0..2) xyz[k + a] = (rest[k + a] + normal[k + a] * d).toFloat()
            }
            mesh.update(xyz)
        }
    }

    private val nets = listOf(Net(1.0), Net(-1.0))

    init { materials.set(material, n.colour, n.opacity) }

    /** A goal into the net on goal line [goalZ]'s side, the ball across at [ballX]. */
    fun ripple(goalZ: Double, ballX: Double) {
        val net = if (goalZ > 0) nets[0] else nets[1]
        net.age = 0.0
        net.strikeX = ballX.coerceIn(-half, half)
    }

    private var clock = 0.0

    /** One frame of real time: the cloth sways always, a goal's ripple rides on top of it. */
    fun advance(dt: Double, reduceMotion: Boolean) {
        clock += dt
        val amplitude = sway.amplitude * if (reduceMotion) sway.reduceMotion else 1.0
        nets.forEach { it.advance(amplitude, 2 * PI * clock / sway.seconds, dt) }
    }

    fun destroy() {
        nets.forEach { scene.removeEntity(it.mesh.entity); it.mesh.destroy() }
        materials.release(listOf(material))
    }
}
