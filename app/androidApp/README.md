# Android host

Kotlin host based on the official Lynx 4.0 integration reference.

The build uses AGP 9.3.1, Gradle 9.5.0, and AGP's built-in Kotlin support with
Kotlin Gradle plugin 2.4.10 supplied on the root buildscript classpath.

The install application ID is managed by `package.json#nativeApp`. From the
repository root, run `pnpm native:apply` after changing it. The default Debug
variant uses the `.debug` suffix, so it can be installed beside Release without
renaming the Kotlin namespace.

```bash
cp local.properties.example local.properties
./gradlew assembleDebug
./gradlew assembleRelease
```

`MainActivity` renders the configured development URL, a verified OTA cache, or
`app/src/main/assets/lynxbundle/main.lynx.bundle`. See the repository root
README for the configuration keys and release workflow.

Both variants target `arm64-v8a`. DevTool wiring and dependencies live only in
the `debug` source set; the minified release APK uses PrimJS and excludes every
V8 and DevTool native library.
