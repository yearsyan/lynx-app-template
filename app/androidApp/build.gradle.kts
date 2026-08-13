// AGP 9 provides Kotlin support directly. Supplying KGP on the buildscript
// classpath upgrades the compiler used by built-in Kotlin without reapplying
// the incompatible org.jetbrains.kotlin.android plugin.
buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath(libs.kotlin.gradle.plugin)
    }
}

plugins {
    alias(libs.plugins.android.application) apply false
}
