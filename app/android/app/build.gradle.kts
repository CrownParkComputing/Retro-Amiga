import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, resolved the same way Retro-Dosbox does it, so the same
// GitHub Actions secrets pattern serves every app:
//   1. ANDROID_KEYSTORE_PATH / ANDROID_KEYSTORE_PASSWORD / ANDROID_KEY_ALIAS /
//      ANDROID_KEY_PASSWORD env vars - CI decodes ANDROID_KEYSTORE_BASE64 to
//      a temp .jks and exports the path.
//   2. key.properties next to this file, for local signed builds.
// With neither, release falls back to the debug key with a warning, so
// `flutter run --release` still works on a fresh tree. No .jks is committed.
data class KeystoreConfig(
    val path: String,
    val storePassword: String,
    val keyAlias: String,
    val keyPassword: String,
)

fun resolveKeystore(): KeystoreConfig? {
    val envPath = System.getenv("ANDROID_KEYSTORE_PATH")
    val envStorePw = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val envAlias = System.getenv("ANDROID_KEY_ALIAS")
    val envKeyPw = System.getenv("ANDROID_KEY_PASSWORD")
    if (envPath != null && envStorePw != null && envAlias != null && envKeyPw != null) {
        logger.lifecycle("release: using keystore from ANDROID_KEYSTORE_PATH env var")
        return KeystoreConfig(envPath, envStorePw, envAlias, envKeyPw)
    }

    val propsFile = file("key.properties")
    if (propsFile.exists()) {
        val p = Properties().apply { load(propsFile.inputStream()) }
        val path = p["storeFile"] as String?
        val storePw = p["storePassword"] as String?
        val alias = p["keyAlias"] as String?
        val keyPw = p["keyPassword"] as String?
        if (path != null && storePw != null && alias != null && keyPw != null) {
            logger.lifecycle("release: using keystore from ${propsFile.absolutePath}")
            return KeystoreConfig(path, storePw, alias, keyPw)
        }
    }

    logger.warn(
        "release: no ANDROID_KEYSTORE_* env vars and no key.properties; " +
            "falling back to the debug keystore. This build will not be " +
            "accepted by Play Console."
    )
    return null
}

// Floor for the Android version code, chosen to clear the legacy Amiberry
// codes already on Play (highest: 404021019) with room to spare, while
// staying well inside the int32 ceiling Play enforces (2147483647).
val androidVersionCodeBase = 500_000_000

val keystoreConfig = resolveKeystore()

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
    compileSdk = 36
    // Same NDK as the rest of the Retro-* family. Gradle builds this app's
    // native code itself, so this is the compiler, not just a label.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.uae4arm2026"
        // 28, which is this app's real floor rather than a preference.
        // Amiberry calls posix_spawn (src/osdep/amiberry_update.cpp), and
        // Bionic did not have it until API 28 -- a build at 26 fails outright
        // with "use of undeclared identifier 'posix_spawn'". Gradle compiles
        // this app's native code, so minSdk IS the API the core is built
        // against; the two cannot drift apart.
        minSdk = 28
        targetSdk = 36
        // Play production holds 404021019: the legacy Amiberry app's code, from
        // the major*100M + minor*1M + patch*10k + minuteOfDay scheme still in
        // android/app/build.gradle (4.4.2, built at 16:59). The Flutter
        // launcher restarted numbering at 1, so a bundle numbered 16 is ~404
        // million BELOW production and Play refuses the rollout: no existing
        // user could upgrade to it.
        //
        // Android gets its own code above the legacy line. The pubspec build
        // number stays small because App Store Connect keeps a separate, much
        // shorter sequence, and a CFBundleVersion can never be walked back
        // down once raised.
        versionCode = androidVersionCodeBase + flutter.versionCode
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

    // The Flutter Gradle Plugin clears ndk.abiFilters on every build type and
    // refills it from its own hardcoded DEFAULT_PLATFORMS, which always
    // includes armeabi-v7a. AGP then UNIONS that with the defaultConfig filter
    // above, so defaultConfig alone can never subtract an ABI - every bundle
    // shipped 32-bit regardless of what androidAbiFilters said. This block runs
    // after the plugin's apply(), so clearing here is what actually decides the
    // packaged set. 32-bit must not ship: the core reserves a 4GB natmem region
    // at startup, which no armeabi-v7a process can map.
    buildTypes.configureEach {
        ndk {
            abiFilters.clear()
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

    signingConfigs {
        create("release") {
            if (keystoreConfig != null) {
                storeFile = file(keystoreConfig.path)
                storePassword = keystoreConfig.storePassword
                keyAlias = keystoreConfig.keyAlias
                keyPassword = keystoreConfig.keyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreConfig != null) {
                signingConfigs.getByName("release")
            } else {
                // Dev/CI without secrets: the debug key, so `flutter run
                // --release` works on a fresh tree. The warning above is the
                // signal that this build cannot go to Play.
                signingConfigs.getByName("debug")
            }
            // SDL registers its Java native methods by name at library load
            // time. Keep the release bridge unshrunk: removing an apparently
            // unused native declaration makes ART abort before the game starts.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
