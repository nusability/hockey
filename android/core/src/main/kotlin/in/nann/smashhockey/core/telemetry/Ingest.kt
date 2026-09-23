package `in`.nann.smashhockey.core.telemetry

import `in`.nann.smashhockey.core.generated.Env

/**
 * Whether anything leaves at all, where it goes, and which dataset it lands in (spec §18.7). The iOS
 * twin is SmashCore's `Telemetry/Ingest.swift`.
 *
 * Both decisions are pure functions of values the platform layer resolves, so both branches of each
 * are reachable from a test — which matters more here than anywhere else in the app, because the
 * branch that must never run is the one a debug-compiled suite would otherwise never execute.
 */
data class Ingest(
    /** The collector, without a trailing slash: `POST <endpoint>/<table>` (§18.6). */
    val endpoint: String,
    /**
     * A doormat, not a lock — it ships inside the binary. It stops a scanner writing rows into the
     * dataset we make decisions from; real abuse means rotating it and shipping a build.
     */
    val token: String,
    /**
     * The commit this build came from (§18.1). A build that cannot say which code it is has no
     * business reporting what that code did.
     */
    val commit: String,
) {
    /** Where one row is posted (§18.6): the table is the route. */
    fun url(row: TelemetryRow): String = "$endpoint/${row.table}"

    companion object {
        /**
         * The configuration, or nothing — and nothing is the safe state: **with no configuration the
         * client is inert** (conventions.md, Configuration). No value here is ever defaulted, because
         * a `?: "https://…"` in this file would be a build quietly reporting into someone's dataset.
         *
         * [testRun] is the second gate and it is absolute. ../flashybird put 329 events and 65 rows
         * into **production** out of a single `xcodebuild test`, and there is no server-side fix for
         * that: once a row has arrived, a robot's is indistinguishable from a person's. So a test run
         * reports nothing at all — not a staging row, nothing — and it is refused here, where both
         * platforms' suites can see it, rather than at the call site where neither can.
         */
        fun resolve(endpoint: String?, token: String?, commit: String?, testRun: Boolean): Ingest? {
            if (testRun) return null
            val host = clean(endpoint) ?: return null
            val bearer = clean(token) ?: return null
            val build = clean(commit) ?: return null
            if (!host.startsWith("https://")) return null
            return Ingest(host, bearer, build)
        }

        /**
         * A configured value, or null for one that is absent or blank — an empty build setting is an
         * unset build setting, not an empty endpoint.
         */
        private fun clean(value: String?): String? =
            value?.trim()?.trimEnd('/')?.takeIf { it.isNotEmpty() }
    }
}

/** Which dataset a build writes into (spec §18.7). */
object TelemetryEnv {
    /**
     * **Production only when this is a release build of a real store install**; everything else is
     * staging. A pure function of two booleans, so a suite compiled for debug can still exercise the
     * production branch — the single most consequential line in the client would otherwise be the
     * only untestable one.
     *
     * How [storeInstall] is answered is each platform's own, and the two cannot answer it equally
     * well: iOS reads the App Store receipt, which names a sandbox (TestFlight, App Review) apart
     * from a real purchase; Android has only the installing package, which says Play or not-Play and
     * cannot tell a test track from production. That asymmetry is a dated platform-delta row in the
     * spec, not a licence.
     */
    fun of(debugBuild: Boolean, storeInstall: Boolean): Env =
        if (!debugBuild && storeInstall) Env.PRODUCTION else Env.STAGING
}
