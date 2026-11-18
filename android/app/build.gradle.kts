
// ESPANA_OUTDOOR_RELEASE_SIGNING
val releaseStoreFilePath = System.getenv("ANDROID_RELEASE_STORE_FILE")?.trim()?.takeIf { it.isNotEmpty() }
val releaseStorePassword = System.getenv("ANDROID_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("ANDROID_RELEASE_KEY_ALIAS")?.trim()?.takeIf { it.isNotEmpty() }
val releaseKeyPassword = System.getenv("ANDROID_RELEASE_KEY_PASSWORD")
val releaseSigningConfigured = releaseStoreFilePath != null && !releaseStorePassword.isNullOrBlank() && releaseKeyAlias != null && !releaseKeyPassword.isNullOrBlank() && file(releaseStoreFilePath).isFile
if (System.getenv("APP_ENV") == "production" && !releaseSigningConfigured) {
    throw GradleException("Production Android builds require a configured release keystore.")
}

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.espana_outdoors"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    flavorDimensions += "environment"
    productFlavors {
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".iconspreview"
        }
        create("production") {
            dimension = "environment"
        }
    }

    defaultConfig {
        applicationId = "com.espanaoutdoors.espana_outdoors"
        manifestPlaceholders["appAuthRedirectScheme"] = "com.espanaoutdoors"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningConfigured) { signingConfigs.getByName("release") } else { signingConfigs.getByName("debug") }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(
            org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        )
    }
}

flutter {
    source = "../.."
}
