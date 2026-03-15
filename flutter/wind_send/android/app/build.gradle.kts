import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Please set the key.properties and store.jks file in the app directory
// Kotlin DSL version for loading properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("app/key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
} else {
    // Fallback to environment variables if key.properties doesn't exist
    keystoreProperties.setProperty("storePassword", System.getenv("KEY_STORE_PASSWORD"))
    keystoreProperties.setProperty("keyPassword", System.getenv("KEY_PASSWORD"))
    keystoreProperties.setProperty("keyAlias", System.getenv("ALIAS"))
    keystoreProperties.setProperty("storeFile", System.getenv("KEY_PATH"))
}

android {
    namespace = "com.doraemon.wind_send"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    lint {
        // AGP runs `lintVitalAnalyzeRelease` as part of release packaging when
        // `checkReleaseBuilds` is enabled. On Windows this task can fail before
        // analysis starts because its cache cleanup hits transient file locks in
        // `build/app/intermediates/lint-cache`. Keep lint available as an
        // explicit workflow (`gradlew lint` / CI) and decouple APK packaging
        // from this host-specific cache behavior.
        checkReleaseBuilds = false
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.doraemon.wind_send"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // This is the corrected Kotlin DSL version for signing configs
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storePassword = keystoreProperties.getProperty("storePassword")
            
            // Safely handle the storeFile path
            val storeFilePath = keystoreProperties.getProperty("storeFile")
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
            }
        }
    }

    buildTypes {
        getByName("release") {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
    // Enable Coroutines for Android
    // implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
