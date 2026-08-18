plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.scanner"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.activity:activity:1.9.0")
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    // Bundled variant: the recognition model ships inside the app and runs
    // offline, with no Google Play Services dependency at runtime.
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
