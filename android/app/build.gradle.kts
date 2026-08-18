import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload-keystore credentials, kept out of git in android/key.properties (see
// RELEASE_PLAN.md). Absent on dev machines, so we fall back to debug signing
// below — a Play-store build REQUIRES this file to exist.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.aknsoftware.debatly"
    // Some plugins (package_info_plus, …) require API 36; raise above the
    // Flutter default if it is lower.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time APIs that require core
        // library desugaring to run on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aknsoftware.debatly"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk 24 was raised for RevenueCat's paywall UI and stays put:
        // lowering it now would re-offer the app to devices we already
        // dropped. Raise the Flutter default if it is lower.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Google Play requires a strictly-increasing integer versionCode on
        // every upload. Instead of hand-maintaining a "+buildNumber" in
        // pubspec.yaml, derive it from the semantic versionName so you only
        // ever bump "x.y.z" (e.g. 1.0.1 -> 1.0.2). Scheme leaves room for
        // .999 minor/patch: MAJOR*1_000_000 + MINOR*1_000 + PATCH.
        versionName = flutter.versionName
        versionCode = flutter.versionName.split(".").let { parts ->
            val major = parts.getOrNull(0)?.toIntOrNull() ?: 0
            val minor = parts.getOrNull(1)?.toIntOrNull() ?: 0
            val patch = parts.getOrNull(2)?.toIntOrNull() ?: 0
            major * 1_000_000 + minor * 1_000 + patch
        }
    }

    signingConfigs {
        // Only wired up when android/key.properties exists. The values come from
        // the upload keystore generated with keytool (see KEYS_AND_SERVICES_MAP.md).
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile in key.properties is relative to android/ (the
                // keystore lives at android/keys/upload-keystore.jks), so
                // resolve against the root project, not this app module.
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sign with the real upload keystore when key.properties is present;
            // otherwise fall back to debug keys so `flutter run --release` still
            // works on dev machines. A debug-signed build is REJECTED by Play —
            // create the keystore before submitting (RELEASE_PLAN.md, Krok 1).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 shrinking/obfuscation/optimisation, explicit so Play Console's
            // R8 health checks are satisfied deliberately rather than by the
            // Flutter default. Keep rules (proguard-rules.pro) are minimal on
            // purpose — every wholesale keep lowers the optimisation rate.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Required by flutter_local_notifications when core library desugaring is on.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
