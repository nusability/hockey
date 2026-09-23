package `in`.nann.smashhockey.core.telemetry

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Spec §18.8's claim, checked instead of measured: **the enqueue path cannot cost a frame, because
 * the types on it contain no network and no file at all.** That is a property of the source, so it is
 * read here rather than profiled — profiling a phone to learn what a screen of code already says
 * would be the wrong instrument, and on this machine it is a forbidden one (AGENTS: Verification).
 *
 * This is the one test in the repo that reads **both platforms'** sources, on purpose: the structure
 * it guards is the same structure on both, and iOS's app layer has no suite of its own that runs in
 * the routine checks (`xcodebuild test` is not run here). Written twice it would be one more thing to
 * keep in step for nothing.
 */
class TelemetrySourceTest {
    private val root: File by lazy {
        val vectors = System.getProperty("smash.vectors")
            ?: error("system property smash.vectors is not set — android/core/build.gradle.kts sets it for tests")
        File(vectors).parentFile.parentFile
    }

    private fun source(path: String): String = File(root, path).also {
        assertTrue("$path is missing — the sending path moved and this test was not told", it.exists())
    }.readText()

    /** Anything that can wait on the world. None of it may be named on the enqueue path. */
    private val waiting = listOf(
        "URLSession", "URLRequest", "HttpURLConnection", "OkHttp", "java.net", "Socket",
        "FileManager", "FileOutputStream", "FileInputStream", "openConnection",
        "Executors", "DispatchQueue", "Thread(", "Date(", "System.currentTimeMillis",
    )

    private val enqueuePath = listOf(
        "ios/SmashCore/Sources/SmashCore/Telemetry/Outbox.swift",
        "ios/SmashCore/Sources/SmashCore/Telemetry/Ingest.swift",
        "android/core/src/main/kotlin/in/nann/smashhockey/core/telemetry/Outbox.kt",
        "android/core/src/main/kotlin/in/nann/smashhockey/core/telemetry/Ingest.kt",
    )

    @Test
    fun theEnqueuePathNamesNothingThatCanWait() {
        for (path in enqueuePath) {
            // The prose *about* these symbols is allowed; a line of code naming one is not.
            val code = source(path).lines()
                .filterNot { it.trimStart().let { l -> l.startsWith("//") || l.startsWith("*") || l.startsWith("/*") } }
                .joinToString("\n")
            for (symbol in waiting) {
                assertTrue("$path names $symbol on the enqueue path (spec §18.8)", !code.contains(symbol))
            }
        }
    }

    /**
     * Both platforms' clients resolve through `Ingest.resolve` and hand it a test-run answer. Reach
     * the endpoint any other way and a build could be live under test — the failure ../flashybird
     * documented with 329 events and 65 rows in production (§18.7).
     */
    @Test
    fun bothClientsGoThroughTheOneGate() {
        for (path in listOf(
            "ios/Sources/Game/Telemetry.swift",
            "android/app/src/main/kotlin/in/nann/smashhockey/game/Telemetry.kt",
        )) {
            val code = source(path)
            assertTrue("$path does not resolve through Ingest.resolve", code.contains("Ingest.resolve("))
            assertTrue("$path does not answer whether this is a test run", code.contains("testRun"))
        }
    }

    /**
     * A flush happens at two moments and nowhere else (§18.8, A0, A2): going to the background, and
     * arriving at the hub. In particular the result screen — the one screen between a result and the
     * next face-off — never names telemetry at all.
     */
    @Test
    fun nothingIsSentFromTheResultScreenOrAnInputPath() {
        val allowed = setOf(
            "ios/Sources/Game/Game.swift", "ios/Sources/Game/GameView.swift",
            "android/app/src/main/kotlin/in/nann/smashhockey/game/Game.kt",
            "android/app/src/main/kotlin/in/nann/smashhockey/MainActivity.kt",
        )
        val apps = listOf(File(root, "ios/Sources"), File(root, "android/app/src/main/kotlin"))
        for (dir in apps) {
            dir.walkTopDown().filter { it.isFile && (it.extension == "swift" || it.extension == "kt") }.forEach { file ->
                val path = file.relativeTo(root).path
                val code = file.readText()
                if (code.contains("telemetry.flush(") || code.contains("telemetry.flush (")) {
                    assertTrue("$path flushes telemetry, which only $allowed may do (spec §18.8)", path in allowed)
                }
                if (path.contains("ResultScreen") || path.contains("Touches") || path.contains("MatchHud")) {
                    assertTrue("$path is between a result and the next face-off and may not mention telemetry",
                        !code.contains("telemetry"))
                }
            }
        }
    }
}
