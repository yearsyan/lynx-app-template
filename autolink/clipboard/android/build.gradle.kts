plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.clipboard"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }
}

// lynx-processor generates the LynxLibraryProvider glue scanned by
// com.lynx.tasm.library.LynxLibraryRegistry; it needs the target package.
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Alynx.library.packageName=com.lynxapp.autolink.clipboard")
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
