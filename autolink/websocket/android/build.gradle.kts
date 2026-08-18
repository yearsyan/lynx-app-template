plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.websocket"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    implementation("com.squareup.okhttp3:okhttp:5.4.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
