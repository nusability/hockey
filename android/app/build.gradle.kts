plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "in.nann.slapshot"
    // COMPILE against the newest SDK the AndroidX libraries require; TARGET what Play asks of a
    // new submission. Confirm the live target figure in the Play Console before the first upload.
    compileSdk = 37
    compileSdkMinor = 2

    defaultConfig {
        // One-way door at registration (conventions.md): decided before the first Play Console
        // upload and never changed after it. Placeholder until then.
        applicationId = "in.nann.slapshot"
        // ADR 0003 (proposed): API 26.
        minSdk = 26
        targetSdk = 36
        // A store field, not an engineering contract; the release lane will pass versionCode.
        versionCode = 1
        versionName = "0.1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
    kotlin { jvmToolchain(21) }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.foundation)
    testImplementation(libs.junit)
}
