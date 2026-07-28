import java.util.Properties

plugins {
    id("com.android.application")
}

fun configuredValue(name: String): String? =
    providers.gradleProperty(name)
        .orElse(providers.environmentVariable(name))
        .orNull
        ?.trim()
        ?.takeIf { it.isNotEmpty() }

val versionProperties = Properties().apply {
    rootProject.file("version.properties").inputStream().use(::load)
}
val hostVersionCode = versionProperties.getProperty("HOST_VERSION_CODE")
    ?.toIntOrNull()
    ?.takeIf { it > 0 }
    ?: throw GradleException("HOST_VERSION_CODE must be a positive integer")
val hostVersionName = versionProperties.getProperty("HOST_VERSION_NAME")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?: throw GradleException("HOST_VERSION_NAME is missing")
val molstarVersion = project.file("src/main/assets/viewer/vendor/molstar/VERSION")
    .readText()
    .trim()
    .takeIf { it.isNotEmpty() }
    ?: throw GradleException("Vendored Mol* VERSION is missing")
val configuredVersionCode = configuredValue("MOLSTAR_ANDROID_VERSION_CODE")
    ?.toIntOrNull()
    ?.takeIf { it > 0 }
    ?: hostVersionCode
val configuredVersionName = configuredValue("MOLSTAR_ANDROID_VERSION_NAME")
    ?: "$hostVersionName-molstar.$molstarVersion"

val signingStoreFile = configuredValue("MOLSTAR_ANDROID_KEYSTORE_FILE")
val signingStorePassword = configuredValue("MOLSTAR_ANDROID_KEYSTORE_PASSWORD")
val signingKeyAlias = configuredValue("MOLSTAR_ANDROID_KEY_ALIAS")
val signingKeyPassword = configuredValue("MOLSTAR_ANDROID_KEY_PASSWORD")
val signingValues = listOf(
    signingStoreFile,
    signingStorePassword,
    signingKeyAlias,
    signingKeyPassword,
)
val hasAnySigningValue = signingValues.any { it != null }
val hasCompleteSigning = signingValues.all { it != null }
if (hasAnySigningValue && !hasCompleteSigning) {
    throw GradleException(
        "Android signing is partially configured. Set all MOLSTAR_ANDROID_KEYSTORE_* and " +
            "MOLSTAR_ANDROID_KEY_* values, or none of them.",
    )
}

android {
    namespace = "io.github.daylight00.molstarandroid"
    compileSdk = 36

    defaultConfig {
        applicationId = "io.github.daylight00.molstarandroid"
        minSdk = 24
        targetSdk = 36
        versionCode = configuredVersionCode
        versionName = configuredVersionName
        manifestPlaceholders["appLabel"] = "Mol* Viewer"
    }

    val sideloadSigning = if (hasCompleteSigning) {
        signingConfigs.create("sideload") {
            storeFile = rootProject.file(signingStoreFile!!)
            storePassword = signingStorePassword
            keyAlias = signingKeyAlias
            keyPassword = signingKeyPassword
        }
    } else {
        null
    }

    flavorDimensions += "channel"
    productFlavors {
        create("stable") {
            dimension = "channel"
            manifestPlaceholders["appLabel"] = "Mol* Viewer"
        }
        create("candidate") {
            dimension = "channel"
            applicationIdSuffix = ".candidate"
            versionNameSuffix = "-candidate"
            manifestPlaceholders["appLabel"] = "Mol* Viewer Candidate"
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
            isDebuggable = true
        }
        getByName("release") {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (sideloadSigning != null) signingConfig = sideloadSigning
        }
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.16.0")
    testImplementation("junit:junit:4.13.2")
}
