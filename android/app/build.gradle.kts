plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fl_muse_connection_test"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.fl_muse_connection_test"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs(
                "../../packages/brainflow/lib/android",
                "$buildDir/rust_output"
            )
        }
    }
}

val buildRustAndroid = tasks.register<Exec>("buildRustAndroid") {
    val isRelease = project.gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
    val buildMode = if (isRelease) "release" else "debug"
    val cargoFlags = if (isRelease) listOf("--release") else emptyList()

    workingDir("../../rust")
    commandLine(listOf("cargo", "ndk", "-t", "arm64-v8a", "build") + cargoFlags)
    
    // Performance: Only rebuild if files changed
    inputs.dir("../../rust/src")
    inputs.file("../../rust/Cargo.toml")
    outputs.dir("../../rust/target/aarch64-linux-android/$buildMode")
}

val syncRustLib = tasks.register<Copy>("syncRustLib") {
    dependsOn(buildRustAndroid)
    val isRelease = project.gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
    val buildMode = if (isRelease) "release" else "debug"
    
    from("../../rust/target/aarch64-linux-android/$buildMode/librust_lib_muse_stream.so")
    into("$buildDir/rust_output/arm64-v8a")
}

tasks.whenTaskAdded {
    if (name.contains("merge") && name.contains("JniLibFolders")) {
        dependsOn(syncRustLib)
    }
    if (name.contains("merge") && name.contains("NativeLibs")) {
        dependsOn(syncRustLib)
    }
}

flutter {
    source = "../.."
}
