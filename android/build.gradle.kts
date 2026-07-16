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

// Force every Android module (app + all plugin modules) to compile against
// SDK 36. Newer plugin versions (flutter_plugin_android_lifecycle, file_picker,
// etc.) require compileSdk 36, but the Flutter tool still hands plugins its
// default (34). This override keeps every module consistent.
//
// evaluationDependsOn(":app") above eagerly evaluates some modules, so a plain
// afterEvaluate would throw "project already evaluated". Guard on state.executed:
// configure now if already evaluated, otherwise defer.
subprojects {
    if (state.executed) {
        extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(36) }
    } else {
        afterEvaluate {
            extensions.findByName("android")?.withGroovyBuilder { "compileSdkVersion"(36) }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
