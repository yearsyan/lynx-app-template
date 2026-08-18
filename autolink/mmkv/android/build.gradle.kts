plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.mmkv"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
    }
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    implementation("com.tencent:mmkv:2.4.1")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
