pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

// Discovers every Lynx native library under node_modules (autolink/* in the
// repository root) and includes its android/ directory as a Gradle project.
plugins {
    id("org.lynxsdk.lynx.library-settings") version "4.0.1"
}

rootProject.name = "LynxTemplate"
include(":app")
