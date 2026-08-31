import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.pedrosolorzano.voicex_movil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pedrosolorzano.voicex_movil"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String?
            keyPassword = keyProperties["keyPassword"] as String?
            storeFile = keyProperties["storeFile"]?.let { rootProject.file(it) }
            storePassword = keyProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// versionName comes from pubspec.yaml, which is where the semantic version
// belongs. It used to be hardcoded here as "0.2.<commitCount>", so the minor
// never moved and the APK disagreed with docs/RELEASES.md.
//
// The commit count still drives versionCode: Android requires a value that only
// ever grows, and it is the one number that cannot be forgotten on a release.
fun gitCommitCount(): Int {
    return try {
        ProcessBuilder("git", "rev-list", "--count", "HEAD")
            .redirectErrorStream(true)
            .start()
            .inputStream.bufferedReader().readText().trim().toInt()
    } catch (e: Exception) {
        0
    }
}

val gitCount = gitCommitCount()

android.defaultConfig.versionCode = gitCount

tasks.configureEach {
    if (name == "assembleRelease") {
        doLast {
            val versionName = android.defaultConfig.versionName ?: "unknown"
            val apkDir = file("${layout.buildDirectory.get()}/outputs/flutter-apk")
            val src = File(apkDir, "app-release.apk")
            val dst = File(apkDir, "voicex-${versionName}-release.apk")
            if (src.exists()) {
                src.copyTo(dst, overwrite = true)
                println("APK renamed to: ${dst.name}")
            }
        }
    }
}
