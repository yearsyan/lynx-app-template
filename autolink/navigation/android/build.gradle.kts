plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.navigation"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.activity:activity:1.13.0")
    implementation("androidx.annotation:annotation:1.9.1")
    // Back interception is intentionally hosted only by FragmentActivity pages.
    implementation("androidx.fragment:fragment:1.8.9")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
