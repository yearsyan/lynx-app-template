plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.permissions"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    // Runtime-permission prompts are hosted by a headless androidx
    // fragment; the host activity must be a FragmentActivity (the same
    // requirement BiometricModule already documents).
    implementation("androidx.fragment:fragment:1.8.9")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
