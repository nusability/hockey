package `in`.nann.smashhockey.game

import android.content.Context
import android.os.Build
import android.util.Log
import `in`.nann.smashhockey.BuildConfig
import `in`.nann.smashhockey.core.generated.Env
import `in`.nann.smashhockey.core.generated.Envelope
import `in`.nann.smashhockey.core.generated.Platform
import `in`.nann.smashhockey.core.generated.Tuning
import `in`.nann.smashhockey.core.telemetry.Ingest
import `in`.nann.smashhockey.core.telemetry.Outbox
import `in`.nann.smashhockey.core.telemetry.TelemetryEnv
import `in`.nann.smashhockey.core.telemetry.TelemetryRow
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * The sending half of spec §18 on Android: the configuration, the queue's owner and the one place a
 * request exists. The iOS twin is `Game/Telemetry.swift`; everything both platforms must agree about —
 * the rows, the bound, the drop order, the routing, the test gate — is in `:core`, not here
 * (`core/telemetry/Outbox.kt`, `core/telemetry/Ingest.kt`).
 *
 * **With no configuration this object exists and does nothing** (conventions.md, Configuration): no
 * endpoint, no token or no commit stamp and [ingest] is null, [record] returns immediately and nothing
 * is ever built or sent. That is the state of every build nobody has configured, every checkout on a
 * new machine, and — absolutely — every test run (§18.7).
 */
class Telemetry(
    endpoint: String? = BuildConfig.SMASH_TELEMETRY_URL,
    token: String? = BuildConfig.SMASH_TELEMETRY_TOKEN,
    commit: String? = BuildConfig.SMASH_COMMIT,
    debugBuild: Boolean = BuildConfig.DEBUG,
    storeInstall: Boolean = false,
    testRun: Boolean = isTestRun,
    private val language: String = "und",
    /**
     * A developer's flight, not a player's: rows a launch shortcut produced are stamped `synthetic`
     * so a query can leave them out (§18.1).
     */
    private val synthetic: Boolean = false,
) {
    private val ingest: Ingest? = Ingest.resolve(endpoint, token, commit, testRun)
    private val env: Env = TelemetryEnv.of(debugBuild, storeInstall)

    /**
     * The rows waiting. Main thread only — appending is the only thing the game does on this path,
     * and it is a list append (§18.8, A0).
     */
    private val outbox = Outbox()
    private val sender: Sender? = ingest?.let { Sender(it) }

    init {
        if (ingest != null) {
            Log.i(TAG, "telemetry on: ${ingest.endpoint} as ${env.key}, build ${ingest.commit}")
        } else {
            Log.i(TAG, "telemetry is inert — nothing configured (android/telemetry.properties), or a test run")
        }
    }

    /**
     * Takes a row (§18.8). No I/O, no request, no JSON: the envelope and the bytes are the sending
     * path's work, and this is called at the end of a match, one screen away from the next face-off.
     */
    fun record(row: TelemetryRow) {
        if (sender == null) return
        outbox.append(row)
    }

    /**
     * Sends everything waiting, under **one envelope built for this send** (§18.1).
     *
     * Called at exactly two moments (§18.8): going to the background, and arriving at the hub.
     * **Never** on the result screen, never on an input path and never between a result and the next
     * face-off (A0, A2) — which is why this is a method the two call sites name rather than something
     * [record] does when the queue looks full.
     */
    fun flush(installId: String) {
        val sender = sender ?: return
        val ingest = ingest ?: return
        if (outbox.isEmpty) return
        val envelope = Envelope(
            installId = installId,
            commit = ingest.commit,
            at = System.currentTimeMillis(),
            platform = Platform.ANDROID,
            env = env,
            language = language,
            synthetic = synthetic,
        )
        sender.send(outbox.drain(), envelope)
    }

    companion object {
        const val TAG = "SmashTelemetry"

        /**
         * A test run reports **nothing at all** (§18.7). ../flashybird put 329 events and 65 rows into
         * production out of one `xcodebuild test`, and a robot's row is indistinguishable from a
         * person's once it has arrived — so it is refused at the source, here and in `Ingest.resolve`.
         */
        val isTestRun: Boolean by lazy { runCatching { Class.forName("org.junit.Test") }.isSuccess }

        /**
         * The game's telemetry for this install: the two build-time values, what the phone can say
         * about itself, and the language actually shown (§14, §18.1).
         *
         * [synthetic] is a launch shortcut — a developer's flight, not a player's.
         */
        fun of(context: Context, synthetic: Boolean): Telemetry = Telemetry(
            storeInstall = isStoreInstall(context),
            language = context.resources.configuration.locales[0].language.ifEmpty { "und" },
            synthetic = synthetic,
        )

        /**
         * A real store install (§18.7) — as near as Android can say: the installing package is Play's.
         * That is **all** it can say, so a Play *test track* install reads as production where iOS's
         * receipt would call it a sandbox. A dated platform-delta row in the spec, not a licence.
         */
        private fun isStoreInstall(context: Context): Boolean = runCatching {
            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getInstallerPackageName(context.packageName)
            }
            installer == PLAY_STORE
        }.getOrDefault(false)

        private const val PLAY_STORE = "com.android.vending"
    }
}

/**
 * The only place in the app that builds a request, on the only thread that may (§18.8).
 *
 * Fire-and-forget: the connection is made, written to and asked once for its status — asking is what
 * actually sends it — and never looked at again. **A failed send is dropped, never retried**: a retry
 * is a stall waiting to happen, and a lost row changes no decision.
 *
 * `HttpURLConnection` rather than a client library: one POST with two headers, no dependency, and
 * nothing here is worth a version to keep up with.
 */
private class Sender(private val ingest: Ingest) {
    private val timeoutMs = (Tuning.Telemetry.sendTimeoutSeconds * 1000).toInt()
    private val threads = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "smash-telemetry").apply { isDaemon = true }
    }

    fun send(rows: List<TelemetryRow>, envelope: Envelope) {
        threads.execute {
            // One request per table, because the routes are the tables (§18.6) — and so one malformed
            // batch cannot take another table's rows down with it. A flush can never exceed the
            // collector's batch cap: the outbox's bound is that cap.
            for ((_, group) in rows.groupBy { it.table }) {
                val body = group.joinToString(",", "[", "]") { it.encoded(envelope) }
                runCatching {
                    val connection = URL(ingest.url(group.first())).openConnection() as HttpURLConnection
                    connection.requestMethod = "POST"
                    connection.connectTimeout = timeoutMs
                    connection.readTimeout = timeoutMs
                    connection.setRequestProperty("Content-Type", "application/json")
                    connection.setRequestProperty("Authorization", "Bearer ${ingest.token}")
                    connection.doOutput = true
                    connection.outputStream.use { it.write(body.toByteArray()) }
                    connection.responseCode
                    connection.disconnect()
                }
            }
        }
    }
}
