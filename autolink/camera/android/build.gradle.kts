plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.camera"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.activity:activity:1.9.0")
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-core:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("androidx.core:core:1.13.1")
    implementation("androidx.exifinterface:exifinterface:1.3.7")
    implementation("androidx.fragment:fragment:1.8.9")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
