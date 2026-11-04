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

dependencies {
    implementation("com.mapbox.maps:android-ndk27:11.34.2")
    implementation("com.mapbox.navigationcore:android-ndk27:3.34.2")
}

flutter {
    source = "../.."
}
