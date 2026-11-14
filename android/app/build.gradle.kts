plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// ESPANA_OUTDOOR_RELEASE_SIGNING
val releaseStoreFilePath = System.getenv("ANDROID_RELEASE_STORE_FILE")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
val releaseStorePassword = System.getenv("ANDROID_RELEASE_STORE_PASSWORD")
val releaseKeyAlias = System.getenv("ANDROID_RELEASE_KEY_ALIAS")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
val releaseKeyPassword = System.getenv("ANDROID_RELEASE_KEY_PASSWORD")
val releaseSigningConfigured =
    releaseStoreFilePath != null &&
    !releaseStorePassword.isNullOrBlank() &&
    releaseKeyAlias != null &&
    !releaseKeyPassword.isNullOrBlank() &&
    file(releaseStoreFilePath).isFile

if (System.getenv("APP_ENV") == "production" && !releaseSigningConfigured) {
    throw GradleException(
        "Production Android builds require ANDROID_RELEASE_STORE_FILE, " +
            "ANDROID_RELEASE_STORE_PASSWORD, ANDROID_RELEASE_KEY_ALIAS, " +
            "and ANDROID_RELEASE_KEY_PASSWORD with a valid keystore."
    )
}

android {
    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                storeFile = file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword!!
                keyAlias = releaseKeyAlias!!
                keyPassword = releaseKeyPassword!!
            }
        }
    }

    namespace = "com.example.espana_outdoors"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.3.13750724"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.espanaoutdoors.espana_outdoors"
        manifestPlaceholders["appAuthRedirectScheme"] = "com.espanaoutdoors"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (releaseSigningConfigured) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
