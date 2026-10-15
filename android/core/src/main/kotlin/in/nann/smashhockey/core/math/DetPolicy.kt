package `in`.nann.smashhockey.core.math

import kotlin.math.abs

/**
 * The learned policy's forward pass (spec §4.4, §7): the same result, to the bit, as iOS's
 * `SmashCore.DetPolicy`.
 *
 * Only `+`, `−` and `×`, in the order written here and in the Swift twin, never fused. The JVM
 * never fuses — since Java 17 every floating-point operation is strict (JEP 306), and ART forms no
 * floating-point multiply-accumulate at all: its `TryCombineMultiplyAccumulate` bails unless the
 * type is int or long, and its vectoriser sets `kNoReduction` for `kFloat32` and `kFloat64` on both
 * arm64 paths, so a `double` accumulator loop is never vectorised or reassociated. Only an explicit
 * `Math.fma` would be a fusion, and there is none here.
 *
 * The accumulation order is part of the contract, not an implementation detail:
 *
 *     for each layer, for output `o` ascending:
 *         s ← bias[o]
 *         for input `i` ascending:  s ← s + weight[o · nIn + i] · x[i]
 *
 * No accumulation tree, no pairwise summation, no `DoubleArray.sum()`, no SIMD by hand. The loop is
 * written the dull way deliberately — the toolchain guarantees are about *this* shape of loop — so
 * do not "optimise" it.
 *
 * Bit-exactness against iOS is pinned by the golden vectors in shared/vectors/policy/.
 */
object DetPolicy {

    /** `y = W · x + b`, accumulated in the declared order. `w` is output-major. */
    fun layer(x: DoubleArray, w: DoubleArray, b: DoubleArray, nIn: Int, nOut: Int): DoubleArray {
        val y = DoubleArray(nOut)
        for (o in 0 until nOut) {
            val row = o * nIn
            var s = b[o]
            for (i in 0 until nIn) {
                s = s + w[row + i] * x[i]
            }
            y[o] = s
        }
        return y
    }

    /** ReLU, in place, as a comparison — never `max`, so no signed zero has to be arbitrated. */
    fun relu(x: DoubleArray) {
        for (i in x.indices) {
            x[i] = if (x[i] > 0.0) x[i] else 0.0
        }
    }

    /**
     * `x / (1 + |x|)` — the algebraic sigmoid, exact under §4.4 where `tanh` would not be, and used
     * instead of a clamp because a clamp saturates and leaves the search nothing to climb.
     */
    fun squash(x: Double): Double = x / (1.0 + abs(x))
}

/**
 * A trained policy: two hidden ReLU layers and a linear output (spec §7).
 *
 * Shapes and weights come from shared/data/policy.toml and shared/assets/policy/ (ADR 0010).
 */
class PolicyNet(
    val nIn: Int,
    val nHidden: Int,
    val nOut: Int,
    parameters: DoubleArray,
) {
    private val w0: DoubleArray
    private val b0: DoubleArray
    private val w1: DoubleArray
    private val b1: DoubleArray
    private val w2: DoubleArray
    private val b2: DoubleArray

    init {
        require(parameters.size == parameterCount(nIn, nHidden, nOut)) {
            "PolicyNet: parameter vector is ${parameters.size}, expected ${parameterCount(nIn, nHidden, nOut)}"
        }
        var k = 0
        fun take(n: Int): DoubleArray {
            val a = parameters.copyOfRange(k, k + n)
            k += n
            return a
        }
        w0 = take(nHidden * nIn); b0 = take(nHidden)
        w1 = take(nHidden * nHidden); b1 = take(nHidden)
        w2 = take(nOut * nHidden); b2 = take(nOut)
    }

    /** One forward pass, keeping both hidden layers — what shared/vectors/policy/ pins. */
    fun trace(observation: DoubleArray): Triple<DoubleArray, DoubleArray, DoubleArray> {
        require(observation.size == nIn) { "PolicyNet: observation is ${observation.size}, expected $nIn" }
        val h = DetPolicy.layer(observation, w0, b0, nIn, nHidden)
        DetPolicy.relu(h)
        val g = DetPolicy.layer(h, w1, b1, nHidden, nHidden)
        DetPolicy.relu(g)
        return Triple(h, g, DetPolicy.layer(g, w2, b2, nHidden, nOut))
    }

    /** One forward pass, in the declared order (§4.4). */
    fun forward(observation: DoubleArray): DoubleArray {
        require(observation.size == nIn) { "PolicyNet: observation is ${observation.size}, expected $nIn" }
        val h = DetPolicy.layer(observation, w0, b0, nIn, nHidden)
        DetPolicy.relu(h)
        val g = DetPolicy.layer(h, w1, b1, nHidden, nHidden)
        DetPolicy.relu(g)
        return DetPolicy.layer(g, w2, b2, nHidden, nOut)
    }

    companion object {
        fun parameterCount(nIn: Int, nHidden: Int, nOut: Int): Int =
            nHidden * nIn + nHidden + nHidden * nHidden + nHidden + nOut * nHidden + nOut
    }
}
