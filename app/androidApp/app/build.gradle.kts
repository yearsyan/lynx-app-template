import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    // The settings plugin already places the shared 4.0.1 implementation JAR
    // on the classpath, so this companion plugin must be applied unversioned.
    id("org.lynxsdk.lynx.library-build")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use(::load)
    }
}

fun buildConfigString(property: String): String {
    val escaped = localProperties.getProperty(property, "")
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
    return "\"$escaped\""
}

android {
    namespace = "com.lynxapp"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.lynxapp"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        ndk {
            // This template targets modern physical devices. Keeping one ABI
            // prevents every APK from carrying four copies of Lynx/Fresco.
            abiFilters += listOf("arm64-v8a")
        }

        vectorDrawables {
            useSupportLibrary = true
        }

        buildConfigField(
            "String",
            "LYNX_DEV_BUNDLE_URL",
            buildConfigString("lynx.dev.bundle.url")
        )
        buildConfigField(
            "String",
            "LYNX_UPDATE_MANIFEST_URL",
            buildConfigString("lynx.update.manifest.url")
        )
        manifestPlaceholders["usesCleartextTraffic"] = "false"
    }

    buildTypes {
        debug {
            // Managed from package.json#nativeApp by scripts/apply-native-config.mjs.
            applicationIdSuffix = ".debug"
            // Rspeedy serves HTTP by default. Release remains HTTPS-only.
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        release {
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    // Lynx pages extend FragmentActivity so the autolinked Back and Biometric
    // libraries can use lifecycle-aware AndroidX host APIs.
    implementation("androidx.fragment:fragment:1.8.9")
    // Lynx 4.0 still requests AppCompat 1.0.0. Pin the current,
    // binary-compatible VectorDrawable artifacts across build toolchains.
    implementation(libs.androidx.vectordrawable)
    implementation(libs.androidx.vectordrawable.animated)

    // lynx dependencies
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    implementation("org.lynxsdk.lynx:lynx-jssdk:4.0.0")
    implementation("org.lynxsdk.lynx:lynx-trace:4.0.0")
    implementation("org.lynxsdk.lynx:primjs:4.0.0")

    // integrating image-service
    implementation("org.lynxsdk.lynx:lynx-service-image:4.0.0")

    // image-service dependencies, if not added, images cannot be loaded; if the host APP needs to use other image libraries, you can customize the image-service and remove this dependency
    implementation("com.facebook.fresco:fresco:2.3.0")
    implementation("com.facebook.fresco:animated-gif:2.3.0")
    implementation("com.facebook.fresco:animated-webp:2.3.0")
    implementation("com.facebook.fresco:webpsupport:2.3.0")
    implementation("com.facebook.fresco:animated-base:2.3.0")

    // integrating log-service
    implementation("org.lynxsdk.lynx:lynx-service-log:4.0.0")

    // App-owned Lynx HTTP service and bundle delivery share this transport.
    // OkHttp 5.x resolves okio 3.x and kotlin-stdlib 2.x transitively.
    implementation("com.squareup.okhttp3:okhttp:5.4.0")

    // LynxEnv uses Gson for its optional environment/FSP JSON helpers. DevTool
    // used to provide this transitively, so declare the runtime requirement.
    implementation("com.google.code.gson:gson:2.8.5")

    debugImplementation("org.lynxsdk.lynx:lynx-devtool:4.0.0")
    debugImplementation("org.lynxsdk.lynx:lynx-service-devtool:4.0.0")

    // Stetho: chrome://inspect debugging (network, database, dumpapp). Debug only.
    debugImplementation("com.facebook.stetho:stetho:1.6.0")
    debugImplementation("com.facebook.stetho:stetho-okhttp3:1.6.0")

    // integrating XElement
    implementation("org.lynxsdk.lynx:xelement:4.0.0")
    implementation("org.lynxsdk.lynx:xelement-input:4.0.0")
    implementation("org.lynxsdk.lynx:xelement-overlay:4.0.0")
    implementation("org.lynxsdk.lynx:xelement-svg:4.0.0")
    implementation("org.lynxsdk.lynx:xelement-webview:4.0.0")
    implementation("org.lynxsdk.lynx:servalsvg:0.0.2")
    implementation("org.lynxsdk.lynx:xelement-refresh:4.0.0")
}
