package `in`.nann.smashhockey.scene

import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import `in`.nann.smashhockey.core.generated.World
import `in`.nann.smashhockey.core.feel.GoalNet
import `in`.nann.smashhockey.engine.DynamicMesh
import `in`.nann.smashhockey.engine.Materials
import `in`.nann.smashhockey.generated.Presentation
import `in`.nann.smashhockey.generated.netColour

/**
 * The goals' nets (spec §8.8) — the whole net, cords and film, drawn and moved by the app, the twin
 * of iOS's NetRipple.swift.
 *
 * The world's asset carries the goal *frame* alone (ADR 0008): posts and crossbar. Everything laced
 * to it is here, so that everything the player reads as "the net" moves. Each goal is four sheets —
 * back, roof and two sides (core `GoalNet`) — and each sheet is a cord grid over a translucent film.
 * A net is cloth, so it always breathes: every node sways along its sheet's outward normal, and on a
 * goal a damped wave from where the ball struck rides on top of it. Reduce Motion keeps
 * `sway.reduce_motion` of the sway — applied once, in the core's formula.
 *
 * Both nets are two meshes — every film, and every cord — written in the pitch's frame on nodes that
 * never move, bounded by `GoalNet.extent`, which a test walks every vertex against.
 */
class NetRipple(
    private val engine: Engine,
    private val scene: Scene,
    private val parent: Int,
    private val materials: Materials,
) {
    private val n = Presentation.Net
    private val p = GoalNet.Params(
        height = n.height, columns = n.columns, rows = n.rows, depth = n.depth, cord = n.cord,
        cordLift = n.cordLift, sway = Presentation.Net.Sway.amplitude,
        swaySeconds = Presentation.Net.Sway.seconds, wave = Presentation.Net.Sway.wave,
        calm = Presentation.Net.Sway.reduceMotion, ripple = n.amplitude, decay = n.decay,
        frequency = n.frequency, k = n.k, reach = n.reach, seconds = n.seconds,
    )

    /** One vertex of a net: its rest, its normal, how freely it moves, its cord lift and its goal. */
    private class Vertex(
        val rx: Float, val ry: Float, val rz: Float,
        val nx: Double, val ny: Double, val nz: Double,
        val ox: Float, val oy: Float, val oz: Float,
        val bell: Double, val lift: Float, val goal: Int,
    )

    private val filmVerts = ArrayList<Vertex>()
    private val cordVerts = ArrayList<Vertex>()
    private val filmIdx = ArrayList<Int>()
    private val cordIdx = ArrayList<Int>()

    private val filmMaterial = materials.flatOwned(n.colour)
    private val cordMaterial = materials.flatOwned(n.colour)
    private val film: DynamicMesh
    private val cords: DynamicMesh
    private val filmXyz: FloatArray
    private val cordXyz: FloatArray

    /** Per goal (0: −z, the player's own end; 1: +z): where the ball struck and how long ago. */
    private val strikeX = DoubleArray(2)
    private val strikeY = DoubleArray(2)
    private val strikeZ = DoubleArray(2)
    private val age = DoubleArray(2) { -1.0 }
    private var clock = 0.0

    init {
        for ((goal, sign) in listOf(-1.0, 1.0).withIndex()) {
            for (sheet in GoalNet.sheets(sign, p)) {
                addFilm(sheet, goal)
                addCords(sheet, goal)
            }
        }
        val e = GoalNet.extent(p)
        val bounds = Box(
            0f, ((e.yLow + e.yHigh) / 2).toFloat(), 0f,
            e.x.toFloat(), ((e.yHigh - e.yLow) / 2).toFloat(), e.z.toFloat(),
        )
        filmXyz = FloatArray(filmVerts.size * 3)
        cordXyz = FloatArray(cordVerts.size * 3)
        materials.set(filmMaterial, n.colour, n.opacity)
        materials.set(cordMaterial, n.colour, 1.0)
        film = mesh(filmVerts.size, filmIdx, filmMaterial, bounds)
        cords = mesh(cordVerts.size, cordIdx, cordMaterial, bounds)
        advance(0.0, false)
    }

    private fun mesh(count: Int, idx: List<Int>, material: com.google.android.filament.MaterialInstance, bounds: Box): DynamicMesh {
        val m = DynamicMesh(engine, count, idx.toIntArray(), material, withUv = false, bounds = bounds, priority = 5)
        m.draw(idx.size)
        scene.addEntity(m.entity)
        val tm = engine.transformManager
        if (!tm.hasComponent(m.entity)) tm.create(m.entity)
        tm.setParent(tm.getInstance(m.entity), tm.getInstance(parent))
        return m
    }

    /** The cords take the world's own net colour (teams.toml `net`); the film keeps `[net] colour`. */
    fun paint(world: World) = materials.set(cordMaterial, world.netColour, 1.0)

    /** A goal into the net on goal line [goalZ]'s side, the ball across at [ballX]. */
    fun ripple(goalZ: Double, ballX: Double) {
        val i = if (goalZ > 0) 1 else 0
        val s = GoalNet.strike(goalZ, ballX)
        strikeX[i] = s.x; strikeY[i] = s.y; strikeZ[i] = s.z
        age[i] = 0.0
    }

    /** One frame of real time: the cloth sways always, a goal's ripple rides on top of it. */
    fun advance(dt: Double, reduceMotion: Boolean) {
        clock += dt
        for (i in age.indices) if (age[i] >= 0) age[i] += dt
        write(film, filmVerts, filmXyz, reduceMotion)
        write(cords, cordVerts, cordXyz, reduceMotion)
    }

    private fun write(mesh: DynamicMesh, verts: List<Vertex>, xyz: FloatArray, reduceMotion: Boolean) {
        for (i in verts.indices) {
            val q = verts[i]
            val g = q.goal
            val d = GoalNet.offset(
                q.nx, q.ny, q.nz, q.bell, clock, reduceMotion,
                strikeX[g], strikeY[g], strikeZ[g], age[g], p,
            ).toFloat() + q.lift
            xyz[i * 3] = q.rx + q.ox * d
            xyz[i * 3 + 1] = q.ry + q.oy * d
            xyz[i * 3 + 2] = q.rz + q.oz * d
        }
        mesh.update(xyz)
    }

    // ---- the two meshes

    /** A sheet's film: its grid of nodes, two triangles a cell. */
    private fun addFilm(sheet: GoalNet.Sheet, goal: Int) {
        val base = filmVerts.size
        for (j in 0..sheet.rows) for (i in 0..sheet.columns) {
            filmVerts += vertex(sheet, i, j, goal, 0.0, 0.0, 0.0, 0.0)
        }
        for (j in 0 until sheet.rows) for (i in 0 until sheet.columns) {
            val a = base + j * (sheet.columns + 1) + i
            val b = a + 1; val c = a + sheet.columns + 1; val d = c + 1
            filmIdx += listOf(a, b, d, a, d, c)
        }
    }

    /** A sheet's cords: a thin ribbon along every grid line, both ways, standing `cordLift` off the film. */
    private fun addCords(sheet: GoalNet.Sheet, goal: Int) {
        val half = p.cord / 2
        val a = sheet.acrossUnit
        val u = sheet.upUnit
        for (j in 0..sheet.rows) {
            strip(sheet, goal, sheet.columns, u.x * half, u.y * half, u.z * half) { k -> k to j }
        }
        for (i in 0..sheet.columns) {
            strip(sheet, goal, sheet.rows, a.x * half, a.y * half, a.z * half) { k -> i to k }
        }
    }

    /** One cord: [count] + 1 nodes, two vertices each (either side of the line), a quad per segment. */
    private fun strip(
        sheet: GoalNet.Sheet,
        goal: Int,
        count: Int,
        sx: Double,
        sy: Double,
        sz: Double,
        node: (Int) -> Pair<Int, Int>,
    ) {
        val base = cordVerts.size
        for (k in 0..count) {
            val (i, j) = node(k)
            cordVerts += vertex(sheet, i, j, goal, -sx, -sy, -sz, p.cordLift)
            cordVerts += vertex(sheet, i, j, goal, sx, sy, sz, p.cordLift)
        }
        for (k in 0 until count) {
            val q = base + 2 * k
            cordIdx += listOf(q, q + 2, q + 1, q + 1, q + 2, q + 3)
        }
    }

    @Suppress("LongParameterList")
    private fun vertex(
        sheet: GoalNet.Sheet,
        i: Int,
        j: Int,
        goal: Int,
        sx: Double,
        sy: Double,
        sz: Double,
        lift: Double,
    ): Vertex {
        val node = sheet.point(i, j)
        val n = sheet.normal
        return Vertex(
            (node.x + sx).toFloat(), (node.y + sy).toFloat(), (node.z + sz).toFloat(),
            node.x, node.y, node.z,
            n.x.toFloat(), n.y.toFloat(), n.z.toFloat(),
            sheet.bell(i, j), lift.toFloat(), goal,
        )
    }

    fun destroy() {
        for (m in listOf(film, cords)) { scene.removeEntity(m.entity); m.destroy() }
        materials.release(listOf(filmMaterial, cordMaterial))
    }
}
