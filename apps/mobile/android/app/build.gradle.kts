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
val allowDebugSignedRelease =
    providers.environmentVariable("PERENNIA_ALLOW_DEBUG_SIGNED_RELEASE").orNull == "true"
val releaseSigningProblems = buildList {
    if (androidUploadKeystorePath.isNullOrBlank()) {
        add("ANDROID_UPLOAD_KEYSTORE_PATH is not set")
    } else if (!file(androidUploadKeystorePath).isFile) {
        add("ANDROID_UPLOAD_KEYSTORE_PATH is not a readable file: $androidUploadKeystorePath")
    }
    if (androidKeystorePassword.isNullOrBlank()) add("ANDROID_KEYSTORE_PASSWORD is not set")
    if (androidKeyAlias.isNullOrBlank()) add("ANDROID_KEY_ALIAS is not set")
    if (androidKeyPassword.isNullOrBlank()) add("ANDROID_KEY_PASSWORD is not set")
}
val hasReleaseSigning = releaseSigningProblems.isEmpty()
val anyReleaseSigningSet =
    listOf(androidUploadKeystorePath, androidKeystorePassword, androidKeyAlias, androidKeyPassword)
        .any { !it.isNullOrBlank() }

android {
    namespace = "fit.perennia.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications schedules with java.time, desugared for
        // older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent from the first store upload: Play keys the listing, every
        // install's data, and the signing chain to this ID. It must stay equal
        // to the iOS PRODUCT_BUNDLE_IDENTIFIER, and a build that changes it is a
        // different app that cannot reach existing users' data.
        applicationId = "fit.perennia.app"
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

// A release build must be signed with the real key, or it can never be updated.
// Android only installs an update over an existing app when both carry the same
// signing certificate, so a debug-signed release that reaches a phone strands
// that install: the next real build cannot replace it, and uninstalling erases
// the local database. The check runs when a release variant actually builds, not
// at configuration time, so debug and profile builds never need signing keys.
// A contributor who wants a throwaway release build on their own device opts in
// with PERENNIA_ALLOW_DEBUG_SIGNED_RELEASE=true; a half-configured key (one
// variable set, or a path that points nowhere) fails even then, because that is
// a mistake, not a choice.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        if (!hasReleaseSigning && (anyReleaseSigningSet || !allowDebugSignedRelease)) {
            throw GradleException(
                "Release signing is not configured:\n" +
                    releaseSigningProblems.joinToString("\n") { "  - $it" } +
                    "\nSet all four ANDROID_* signing variables, or, for a local build " +
                    "that will never be updated, set PERENNIA_ALLOW_DEBUG_SIGNED_RELEASE=true " +
                    "with none of them set.",
            )
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

dependencies {
    // The version flutter_local_notifications' README requires.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
