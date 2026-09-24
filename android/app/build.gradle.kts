import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val externalSigningPath = System.getenv("MYUNE_SIGNING_PROPERTIES")
val signingFile = if (externalSigningPath.isNullOrBlank()) {
    rootProject.file("key.properties")
} else {
    file(externalSigningPath)
}
val signingProperties = Properties()
if (signingFile.exists()) {
    signingFile.inputStream().use { signingProperties.load(it) }
}

android {
    namespace = "com.myune.music"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.myune.music.preview"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // mpv_audio_kit supports Android 7.0 (API 24) and newer.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (signingFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (signingFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

if (!signingFile.exists() &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
    throw GradleException("Release signing requires MYUNE_SIGNING_PROPERTIES or android/key.properties")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
