// The Android half of a two-platform product. ADR 0001: a second native codebase, sharing no
// executable code of ours with ios/.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SmashHockey"
include(":app")
// The game's platform-independent core: generated config, deterministic math, the simulation.
include(":core")
