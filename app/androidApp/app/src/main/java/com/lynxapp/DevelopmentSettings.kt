package com.lynxapp

import android.content.Context
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * Debug-only runtime overrides shared by every Lynx page in the Android host.
 *
 * The implementation lives in main because the bundle repository is shared by
 * both build types. Every read is nevertheless guarded by BuildConfig.DEBUG,
 * so a release build cannot observe values left behind by a debug install.
 */
internal object DevelopmentSettings {
    data class Snapshot(
        val apiServer: String,
        val bundleServers: String,
    )

    fun snapshot(context: Context): Snapshot {
        if (!BuildConfig.DEBUG) return Snapshot("", "")
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        return Snapshot(
            apiServer = preferences.getString(API_SERVER, "").orEmpty(),
            bundleServers = preferences.getString(BUNDLE_SERVERS, "").orEmpty(),
        )
    }

    fun apiServer(context: Context): String = snapshot(context).apiServer

    fun developmentUrl(context: Context, bundleId: String): String? {
        if (!BuildConfig.DEBUG || !BUNDLE_ID.matches(bundleId)) return null
        val mappings = runCatching { parseMappings(snapshot(context).bundleServers) }
            .getOrDefault(emptyMap())
        return mappings[bundleId]?.let { resolveBundleUrl(bundleId, it) }
    }

    /** Returns normalized values suitable for showing again in the editor. */
    fun save(context: Context, apiServer: String, bundleServers: String): Snapshot {
        check(BuildConfig.DEBUG) { "Development settings are unavailable in release builds" }
        val normalizedApiServer = normalizeApiServer(apiServer)
        val mappings = parseMappings(bundleServers)
        val normalizedMappings = mappings.entries.joinToString("\n") { (bundleId, server) ->
            "$bundleId=$server"
        }
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putString(API_SERVER, normalizedApiServer)
            .putString(BUNDLE_SERVERS, normalizedMappings)
            .apply()
        return Snapshot(normalizedApiServer, normalizedMappings)
    }

    fun clear(context: Context) {
        if (!BuildConfig.DEBUG) return
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .apply()
    }

    private fun normalizeApiServer(value: String): String {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return ""
        return requireHttpUrl(trimmed, "API Server")
    }

    private fun parseMappings(value: String): LinkedHashMap<String, String> {
        val mappings = linkedMapOf<String, String>()
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
            require(!mappings.containsKey(bundleId)) {
                "Line ${index + 1} repeats bundle ID: $bundleId"
            }
            mappings[bundleId] = requireHttpUrl(server, "Line ${index + 1}")
        }
        return mappings
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
    private const val API_SERVER = "api-server"
    private const val BUNDLE_SERVERS = "bundle-servers"
    private val BUNDLE_ID = Regex("^[a-z0-9][a-z0-9-]*$")
}
