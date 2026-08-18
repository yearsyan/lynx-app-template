# Android host

Kotlin host based on the official Lynx 4.0 integration reference.

The build uses AGP 8.13.2, Gradle 8.13, Android SDK 36, and the classic Kotlin
Android plugin 2.4.10. This toolchain keeps Lynx's official
`library-settings`/`library-build` 4.0.1 Autolink plugins enabled: Gradle scans
`node_modules`, connects every Android Lynx library, and generates the app-wide
registry. The host does not maintain a dependency loop or provider list.

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
