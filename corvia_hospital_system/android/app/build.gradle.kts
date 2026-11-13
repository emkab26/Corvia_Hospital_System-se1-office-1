plugins {
    id("com.android.application")
    kotlin("android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mycorvia"

    compileSdk = flutter.compileSdkVersion

    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11

        // flutter_local_notifications schedules against java.time, which only
        // exists from API 26 up. Desugaring is required for the plugin to build.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget =
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
        }
    }

    defaultConfig {
        applicationId = "com.example.mycorvia"

        minSdk = 26

        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig =
                signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.4"
    )

    implementation(
        "com.google.android.gms:play-services-wearable:20.0.1"
    )
}

flutter {
    source = "../.."
}