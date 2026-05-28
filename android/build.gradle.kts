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

subprojects {
    val configureAndroid = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val baseExtensionClass = Class.forName("com.android.build.gradle.BaseExtension")
                if (baseExtensionClass.isInstance(android)) {
                    val compileSdkMethod = baseExtensionClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    compileSdkMethod.invoke(android, 36)
                }
            } catch (e: Exception) {
                // Ignore if class or method is not found
            }
        }
    }
    if (project.state.executed) {
        configureAndroid()
    } else {
        project.afterEvaluate {
            configureAndroid()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
