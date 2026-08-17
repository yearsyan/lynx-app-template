plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.albumutils"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Alynx.library.packageName=com.lynxapp.autolink.albumutils")
}

dependencies {
    implementation("androidx.activity:activity:1.9.0")
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
