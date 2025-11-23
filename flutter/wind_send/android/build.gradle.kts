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

// see https://stackoverflow.com/questions/77317993/compiledebugjavawithjavac-task-current-target-is-1-8-and-compiledebugkotlin
subprojects {
  afterEvaluate {
        if (project.plugins.hasPlugin("com.android.application")
                || project.plugins.hasPlugin("com.android.library")) {

            if (project.name == "receive_sharing_intent") {
                // project.android.compileOptions {
                //     sourceCompatibility = JavaVersion.VERSION_17
                //     targetCompatibility = JavaVersion.VERSION_17
                // }
            }
        }
    }
}

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
