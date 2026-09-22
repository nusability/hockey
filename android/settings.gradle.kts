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

rootProject.name = "SlapshotLeague"
include(":app")
