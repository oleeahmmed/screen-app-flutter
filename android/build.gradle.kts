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
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
            compileSdk = 36
            buildToolsVersion = "36.0.0"
        }
    }
}

// file_picker (and other plugins) lintVitalAnalyzeRelease can fail on AGP 8.x.
gradle.projectsEvaluated {
    subprojects {
        tasks.matching { it.name.contains("lintVital", ignoreCase = true) }.configureEach {
            enabled = false
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
