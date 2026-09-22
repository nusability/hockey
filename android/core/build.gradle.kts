// The game's platform-independent core on Android: the generated config (shared/data/), the
// deterministic math and, next, the simulation. Pure Kotlin/JVM — no Android dependency — so it
// tests on the JVM in seconds and :app links it.
plugins {
    alias(libs.plugins.kotlin.jvm)
}

kotlin { jvmToolchain(21) }

dependencies {
    testImplementation(libs.junit)
}

// The golden vectors live in shared/vectors/ and are read in place, never copied (ADR 0001).
val vectors = rootProject.layout.projectDirectory.dir("../shared/vectors")
tasks.test {
    inputs.dir(vectors).withPropertyName("vectors").withPathSensitivity(PathSensitivity.RELATIVE)
    systemProperty("smash.vectors", vectors.asFile.absolutePath)
    testLogging { showStandardStreams = true }
}
