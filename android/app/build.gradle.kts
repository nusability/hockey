import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// Telemetry configuration (spec §18.7): android/telemetry.properties — untracked, with
// telemetry.properties.example committed beside it — or the same two names from the environment, for
// a machine that would rather not keep a file. **Nothing is ever defaulted** (conventions.md,
// Configuration): an absent or empty value compiles a real `null` into BuildConfig and the client is
// inert, which is the safe state and how a test run stays silent.
val telemetryKeys = listOf("SMASH_TELEMETRY_URL", "SMASH_TELEMETRY_TOKEN")

val telemetryProperties = rootProject.file("telemetry.properties").takeIf { it.exists() }
    ?.let { file -> Properties().apply { file.inputStream().use { load(it) } } }

/** A Java string literal, or the bare token `null` — which is what "send nothing" looks like. */
fun telemetryValue(key: String): String {
    val value = telemetryProperties?.getProperty(key) ?: System.getenv(key)
    return if (value.isNullOrEmpty()) "null" else "\"$value\""
}

// Which code this build is (§18.1). There is no safe default for it: a row that lies about its
// commit is worse than no row, so a build that cannot read git fails here rather than shipping a
// stamp nobody can trace. A dirty tree says so.
val commitStamp: String = run {
    val head = providers.exec { commandLine("git", "rev-parse", "--short=10", "HEAD") }
        .standardOutput.asText.get().trim()
    if (head.isEmpty()) throw GradleException("the commit stamp could not be read — `git rev-parse HEAD` said nothing (spec §18.1)")
    val dirty = providers.exec { commandLine("git", "status", "--porcelain") }
        .standardOutput.asText.get().isNotBlank()
    if (dirty) "$head-dirty" else head
}

android {
    namespace = "in.nann.smashhockey"
    // COMPILE against the newest SDK the AndroidX libraries require; TARGET what Play asks of a
    // new submission. Confirm the live target figure in the Play Console before the first upload.
    compileSdk = 37
    compileSdkMinor = 2

    defaultConfig {
        // One-way door at registration (conventions.md): decided 2026-09-22, never changed after
        // the first Play Console upload.
        applicationId = "in.nann.smashhockey"
        // ADR 0005 (proposed): API 26.
        minSdk = 26
        targetSdk = 36
        // A store field, not an engineering contract; the release lane will pass versionCode.
        versionCode = 1
        versionName = "0.1"

        telemetryKeys.forEach { key -> buildConfigField("String", key, telemetryValue(key)) }
        buildConfigField("String", "SMASH_COMMIT", "\"$commitStamp\"")
    }

    buildTypes {
        // Release code paths (no debuggable ART, R8) signed with the local debug key, so a device
        // soak measures what players would run without needing the upload key (SMASH-2).
        create("soak") {
            initWith(getByName("release"))
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            matchingFallbacks += listOf("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    kotlin { jvmToolchain(21) }

    buildFeatures {
        compose = true
        buildConfig = true      // the telemetry endpoint, the token and the commit stamp (§18.7)
    }

    // Shared assets (worlds, fonts) and shared data (motion tokens) are read from shared/ directly, never copied (ADR 0001).
    // Only what Android loads is packaged: the .usdz twins and the build scripts are iOS's and the
    // pipeline's, not the app's.
    sourceSets["main"].assets.srcDirs("src/main/assets", "../../shared/assets", "../../shared/data")
    androidResources {
        ignoreAssetsPattern = "!*.usdz:!*.m4a:!*.py:!*.txt:!.*"      // .m4a: the sound bank's iOS twins
        noCompress += listOf("glb", "filamat", "ogg")      // SoundPool opens the .ogg files by descriptor
    }
}

dependencies {
    implementation(project(":core"))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    implementation(libs.filament.android)
    implementation(libs.filament.gltfio)
    implementation(libs.filament.utils)
    implementation(libs.earcut4j)
    testImplementation(libs.junit)
}
