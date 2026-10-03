plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStore = System.getenv("HERMES_ANDROID_KEYSTORE")
val releaseStorePassword = System.getenv("HERMES_ANDROID_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("HERMES_ANDROID_KEY_PASSWORD")
val releaseKeyAlias = System.getenv("HERMES_ANDROID_KEY_ALIAS") ?: "hermes-mobile"
// Optional side-by-side variant for experiments (e.g. HERMES_APP_VARIANT=glass):
// installs next to the regular app with its own id, label and data.
val appVariant = System.getenv("HERMES_APP_VARIANT")?.takeIf { it.isNotBlank() }

android {
    namespace = "ai.ailigent.hermes_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ai.ailigent.hermes_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = if (appVariant != null) "Hermes ${appVariant.replaceFirstChar { it.uppercase() }}" else "Hermes"
        if (appVariant != null) {
            applicationIdSuffix = ".$appVariant"
        }
    }

    signingConfigs {
        if (releaseStore != null) {
            create("distribution") {
                storeFile = file(releaseStore)
                storePassword = requireNotNull(releaseStorePassword) { "Missing release store password" }
                keyAlias = releaseKeyAlias
                keyPassword = requireNotNull(releaseKeyPassword) { "Missing release key password" }
            }
        }
    }

    buildTypes {
        release {
            // CI without signing credentials produces a development-signed artifact.
            // Public Releases are signed with the maintainer's private distribution key.
            signingConfig = signingConfigs.getByName(if (releaseStore != null) "distribution" else "debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
