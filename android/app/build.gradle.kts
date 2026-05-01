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

// Auto-increment patch from total git commit count so every commit produces a
// uniquely named APK: voicex-0.2.<commitCount>-preview.1-release.apk
fun gitCommitCount(): Int {
    return try {
        val stdout = java.io.ByteArrayOutputStream()
        exec {
            commandLine("git", "rev-list", "--count", "HEAD")
            standardOutput = stdout
        }
        stdout.toString().trim().toInt()
    } catch (e: Exception) {
        0
    }
}

val gitCount = gitCommitCount()

android.defaultConfig.versionCode = gitCount
android.defaultConfig.versionName = "0.2.${gitCount}-preview.1"

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
