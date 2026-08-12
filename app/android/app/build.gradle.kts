plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ABIs to build, as -PandroidAbiFilters=arm64-v8a,armeabi-v7a,x86_64. Defaults to
// arm64-v8a for fast local builds; CI passes the full set for release.
val androidAbiFilters: List<String> =
    (project.findProperty("androidAbiFilters") as String? ?: "arm64-v8a")
        .split(',')
        .map { it.trim() }
        .filter { it.isNotEmpty() }

android {
    // Must stay com.uae4arm2026: the emulator's JNI entry points are named after
    // the Java package of Uae4ArmEmulatorActivity.
    namespace = "com.uae4arm2026"
    compileSdk = 37
    ndkVersion = "28.0.13004108"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.uae4arm2026"
        minSdk = 29
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += "-DANDROID_STL=c++_shared"
            }
        }

        ndk {
            abiFilters += androidAbiFilters
        }
    }

    externalNativeBuild {
        cmake {
            // Repo root: app/android/app -> app/android -> app -> repo root.
            path = file("../../../CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
