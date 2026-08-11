plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val androidUploadKeystorePath =
    providers.environmentVariable("ANDROID_UPLOAD_KEYSTORE_PATH").orNull
val androidDebugKeystorePath =
    providers.environmentVariable("ANDROID_DEBUG_KEYSTORE_PATH").orNull
val androidKeystorePassword =
    providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull
val androidKeyAlias =
    providers.environmentVariable("ANDROID_KEY_ALIAS").orNull
val androidKeyPassword =
    providers.environmentVariable("ANDROID_KEY_PASSWORD").orNull
val hasReleaseSigning =
    !androidUploadKeystorePath.isNullOrBlank() &&
        !androidKeystorePassword.isNullOrBlank() &&
        !androidKeyAlias.isNullOrBlank() &&
        !androidKeyPassword.isNullOrBlank() &&
        file(androidUploadKeystorePath).exists()

android {
    namespace = "io.github.lspinheiro.open_workout_logger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.lspinheiro.open_workout_logger"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            androidDebugKeystorePath
                ?.takeIf { it.isNotBlank() }
                ?.let {
                    val debugKeystore = file(it)
                    require(debugKeystore.isFile) {
                        "ANDROID_DEBUG_KEYSTORE_PATH is not a readable file: $it"
                    }
                    storeFile = debugKeystore
                }
        }
        create("release") {
            androidUploadKeystorePath
                ?.takeIf { it.isNotBlank() }
                ?.let { storeFile = file(it) }
            storePassword = androidKeystorePassword
            keyAlias = androidKeyAlias
            keyPassword = androidKeyPassword
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
