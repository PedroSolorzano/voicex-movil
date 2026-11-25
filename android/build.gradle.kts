allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Several plugins pin an old compileSdk (file_picker 34, audio_session 34,
// just_audio 34, audio_service 35...). One of their dependencies,
// flutter_plugin_android_lifecycle, requires 36 or later, so the AAR metadata
// check fails the whole release build on the first plugin it reaches. Bring every
// library up to the compileSdk the app itself uses (`flutter.compileSdkVersion`).
// A library compiled against a newer API than it asked for still runs on the
// devices it supported: compileSdk is about what the code may reference, not about
// what it requires at runtime.
subprojects {
    if (project.name != "app") {
        val raise = {
            (project.extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
                ?.compileSdkVersion(36)
        }
        if (project.state.executed) raise() else project.afterEvaluate { raise() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
