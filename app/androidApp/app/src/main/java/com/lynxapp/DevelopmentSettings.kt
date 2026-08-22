package com.lynxapp

import android.content.Context
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.File

/**
 * Debug-only runtime overrides shared by every Lynx page in the Android host.
 *
 * The implementation lives in main because the bundle repository is shared by
 * both build types. Every read is nevertheless guarded by BuildConfig.DEBUG,
 * so a release build cannot observe values left behind by a debug install.
 */
internal object DevelopmentSettings {
    data class BundleServer(
        val bundleId: String,
        val server: String,
    )

    data class Snapshot(
        val bundleServers: List<BundleServer>,
    )

    fun snapshot(context: Context): Snapshot {
        if (!BuildConfig.DEBUG) return Snapshot(emptyList())
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val mappings = runCatching {
            parseMappings(preferences.getString(BUNDLE_SERVERS, "").orEmpty())
        }.getOrDefault(emptyList())
        return Snapshot(mappings)
    }

    fun developmentUrl(context: Context, bundleId: String): String? {
        if (!BuildConfig.DEBUG || !BUNDLE_ID.matches(bundleId)) return null
        val mapping = snapshot(context).bundleServers.firstOrNull { it.bundleId == bundleId }
        return mapping?.let { resolveBundleUrl(bundleId, it.server) }
    }

    /**
     * Agent/automation-driven overrides pushed over adb, one
     * `bundle-id=server-url` per line in the same format the DEV panel
     * serializes. `/data/local/tmp` is traversable (but not listable) by
     * apps and adb-pushed files are world-readable, so a fixed file name
     * works without any permission; on builds where SELinux still denies
     * the read, or on any parse problem, the file is simply ignored — it
     * can never break startup. There is deliberately no cache: `adb push`
     * takes effect on the next page open without a reinstall.
     */
    fun deviceFileDevelopmentUrl(bundleId: String): String? {
        if (!BuildConfig.DEBUG || !BUNDLE_ID.matches(bundleId)) return null
        val mapping = deviceFileMappings().firstOrNull { it.bundleId == bundleId }
        return mapping?.let { resolveBundleUrl(bundleId, it.server) }
    }

    private fun deviceFileMappings(): List<BundleServer> =
        runCatching {
            val file = File(DEVICE_MAPPINGS_FILE)
            if (!file.isFile) return@runCatching emptyList()
            parseMappings(file.readText())
        }.getOrDefault(emptyList())

    /** Returns normalized values suitable for showing again in the list UI. */
    fun save(context: Context, bundleServers: List<BundleServer>): Snapshot {
        check(BuildConfig.DEBUG) { "Development settings are unavailable in release builds" }
        val normalizedMappings = normalizeMappings(bundleServers)
        val serializedMappings = normalizedMappings.joinToString("\n") { mapping ->
            "${mapping.bundleId}=${mapping.server}"
        }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(BUNDLE_SERVERS, serializedMappings)
            .apply()
        return Snapshot(normalizedMappings)
    }

    fun validatedBundleServer(bundleId: String, server: String): BundleServer =
        normalizeMapping(BundleServer(bundleId, server), "Bundle server")

    fun loadedBundleIds(context: Context): List<String> {
        if (!BuildConfig.DEBUG) return emptyList()
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getStringSet(LOADED_BUNDLES, emptySet())
            .orEmpty()
            .filter(BUNDLE_ID::matches)
            .sorted()
    }

    @Synchronized
    fun recordLoadedBundle(context: Context, bundleId: String) {
        if (!BuildConfig.DEBUG || !BUNDLE_ID.matches(bundleId)) return
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val loaded = preferences.getStringSet(LOADED_BUNDLES, emptySet())
            .orEmpty()
            .toMutableSet()
        if (loaded.add(bundleId)) {
            preferences.edit().putStringSet(LOADED_BUNDLES, loaded).apply()
        }
    }

    fun clear(context: Context) {
        if (!BuildConfig.DEBUG) return
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .remove(BUNDLE_SERVERS)
            .apply()
    }

    /** Reads the previous line-based format so existing Debug installs migrate in place. */
    private fun parseMappings(value: String): List<BundleServer> {
        val mappings = mutableListOf<BundleServer>()
        val seen = mutableSetOf<String>()
        value.lineSequence().forEachIndexed { index, originalLine ->
            val line = originalLine.trim()
            if (line.isEmpty() || line.startsWith("#")) return@forEachIndexed
            val separator = line.indexOf('=')
            require(separator > 0 && separator < line.lastIndex) {
                "Line ${index + 1} must use bundle-id=server-url"
            }
            val bundleId = line.substring(0, separator).trim()
            val server = line.substring(separator + 1).trim()
            require(BUNDLE_ID.matches(bundleId)) {
                "Line ${index + 1} has an invalid bundle ID: $bundleId"
            }
            require(seen.add(bundleId)) {
                "Line ${index + 1} repeats bundle ID: $bundleId"
            }
            mappings += BundleServer(
                bundleId = bundleId,
                server = requireHttpUrl(server, "Line ${index + 1}"),
            )
        }
        return mappings
    }

    private fun normalizeMappings(value: List<BundleServer>): List<BundleServer> {
        val seen = mutableSetOf<String>()
        return value.mapIndexed { index, mapping ->
            val normalized = normalizeMapping(mapping, "Entry ${index + 1}")
            require(seen.add(normalized.bundleId)) {
                "Entry ${index + 1} repeats bundle ID: ${normalized.bundleId}"
            }
            normalized
        }
    }

    private fun normalizeMapping(mapping: BundleServer, label: String): BundleServer {
        val bundleId = mapping.bundleId.trim()
        require(BUNDLE_ID.matches(bundleId)) {
            "$label has an invalid bundle ID: $bundleId"
        }
        return BundleServer(
            bundleId = bundleId,
            server = requireHttpUrl(mapping.server.trim(), label),
        )
    }

    private fun requireHttpUrl(value: String, label: String): String {
        val url = value.toHttpUrlOrNull()
        require(url != null && (url.scheme == "http" || url.scheme == "https")) {
            "$label must be a valid http:// or https:// URL"
        }
        return url.toString()
    }

    private fun resolveBundleUrl(bundleId: String, server: String): String {
        val url = checkNotNull(server.toHttpUrlOrNull())
        if (url.encodedPath.endsWith(".lynx.bundle")) return url.toString()
        return url.newBuilder()
            .addPathSegment("$bundleId.lynx.bundle")
            .build()
            .toString()
    }

    private const val PREFERENCES = "lynx.debug.development-settings"
    private const val DEVICE_MAPPINGS_FILE = "/data/local/tmp/lynx_dev_bundles.txt"
    private const val BUNDLE_SERVERS = "bundle-servers"
    private const val LOADED_BUNDLES = "loaded-bundles"
    private val BUNDLE_ID = Regex("^[a-z0-9][a-z0-9-]*$")
}
