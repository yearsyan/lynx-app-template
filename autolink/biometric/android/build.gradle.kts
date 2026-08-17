plugins {
    id("com.android.library")
}

android {
    namespace = "com.lynxapp.autolink.biometric"
    compileSdk = 37

    defaultConfig {
        minSdk = 24
    }
}

// lynx-processor generates the LynxLibraryProvider glue scanned by
// com.lynx.tasm.library.LynxLibraryRegistry; it needs the target package.
tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Alynx.library.packageName=com.lynxapp.autolink.biometric")
}

dependencies {
    implementation("androidx.annotation:annotation:1.9.1")
    // BiometricPrompt must be hosted by a FragmentActivity; the fragment
    // dependency is declared so the module compiles against it directly.
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.fragment:fragment:1.8.9")
    implementation("org.lynxsdk.lynx:lynx:4.0.0")
    annotationProcessor("org.lynxsdk.lynx:lynx-processor:4.0.0")
}
