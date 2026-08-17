plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.webviewbridge"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Alynx.library.packageName=com.lynxapp.autolink.webviewbridge")
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    implementation("org.lynxsdk.lynx:xelement-webview:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
