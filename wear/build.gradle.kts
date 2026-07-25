plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "dev.ungaaaabungaaa.relay"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "dev.ungaaaabungaaa.relay"
        minSdk = 30
        targetSdk = 36
        versionCode = providers.environmentVariable("RELAY_WATCH_VERSION_CODE")
            .orNull?.toIntOrNull() ?: 1
        versionName = providers.environmentVariable("RELAY_VERSION")
            .orNull ?: "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        manifestPlaceholders["usesCleartextTraffic"] = false
    }

    signingConfigs {
        val keyStorePath = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull
        if (keyStorePath != null) {
            create("release") {
                storeFile = file(keyStorePath)
                storePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.environmentVariable("ANDROID_KEY_ALIAS").orNull
                keyPassword = providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull
            }
        }
    }

    buildTypes {
        getByName("debug") {
            manifestPlaceholders["usesCleartextTraffic"] = true
        }
        getByName("release") {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

dependencies {
    val composeBom = platform(libs.compose.bom)
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.wear.material3)
    implementation(libs.wear.foundation)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.coroutines.android)
    implementation(libs.okhttp)
    implementation(libs.androidx.core)
    implementation(libs.work.runtime)
    implementation(libs.wear.ongoing)

    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.compose.ui.test.junit4)
}
