plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.espana_outdoors"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.3.13750724"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Preserve the package ID already emitted by the Android staging workflow.
        applicationId = "com.espanaoutdoors.espana_outdoors"
        manifestPlaceholders["appAuthRedirectScheme"] = "com.espanaoutdoors"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// Force the transitive Maps dependency from the Flutter plugin to use the
// NDK 27 variant too; adding the NDK27 artifact directly alone is not enough.
configurations.configureEach {
    resolutionStrategy.dependencySubstitution {
        substitute(module("com.mapbox.maps:android"))
            .using(module("com.mapbox.maps:android-ndk27:11.34.1"))
            .because("Use the supported NDK 27 artifact for 16 KB page-size compatibility")
    }
}

dependencies {
    implementation("com.mapbox.maps:android-ndk27:11.34.1")
    implementation("com.mapbox.navigationcore:android-ndk27:3.34.1")
}

flutter {
    source = "../.."
}
