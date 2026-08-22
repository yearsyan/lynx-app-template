package com.lynxapp.deeplink

import android.content.Context
import android.net.Uri
import org.json.JSONObject

/**
 * Resolves incoming `scheme://host/path?query` deep links against the shared
 * `contracts/deeplinks.json` config, shipped in assets as
 * `lynxbundle/deeplinks.json` (see scripts/sync-native.mjs).
 *
 * A URL with a foreign scheme is not a deep link for this app (null). A URL
 * with our scheme but an unknown host or path falls back to the configured
 * default bundle with no params. On a match, route params merge the route's
 * static params with the URL query (query values win).
 */
object DeepLinkRouteResolver {
    data class Resolution(val bundle: String, val paramsJson: String)

    private const val CONFIG_ASSET_PATH = "lynxbundle/deeplinks.json"
    private const val PATH_ROOT = "/"
    private val BUNDLE_NAME = Regex("^[a-z0-9][a-z0-9-]*$")

    @Volatile
    private var cachedConfig: JSONObject? = null

    fun resolve(context: Context, uri: Uri?): Resolution? {
        if (uri == null) return null
        val config = config(context) ?: return null
        if (!uri.scheme.equals(config.optString("scheme"), ignoreCase = true)) return null

        val route = matchedRoute(config, uri)
        if (route == null) {
            val fallback = config.optString("defaultBundle")
            return if (BUNDLE_NAME.matches(fallback)) Resolution(fallback, "{}") else null
        }
        val bundle = route.optString("bundle")
        if (!BUNDLE_NAME.matches(bundle)) return null
        return Resolution(bundle, mergedParams(route, uri).toString())
    }

    private fun matchedRoute(config: JSONObject, uri: Uri): JSONObject? {
        if (!uri.host.equals(config.optString("host"), ignoreCase = true)) return null
        val path = normalizePath(uri.path)
        val routes = config.optJSONArray("routes") ?: return null
        for (index in 0 until routes.length()) {
            val route = routes.optJSONObject(index) ?: continue
            if (route.optString("path") == path) return route
        }
        return null
    }

    private fun mergedParams(route: JSONObject, uri: Uri): JSONObject {
        val params = JSONObject()
        route.optJSONObject("params")?.let { static ->
            for (key in static.keys()) {
                params.put(key, static.get(key))
            }
        }
        val queryNames = try {
            uri.queryParameterNames
        } catch (error: UnsupportedOperationException) {
            null
        }
        queryNames?.forEach { name ->
            params.put(name, uri.getQueryParameter(name) ?: "")
        }
        return params
    }

    private fun normalizePath(path: String?): String {
        if (path.isNullOrEmpty()) return PATH_ROOT
        val withLeadingSlash = if (path.startsWith("/")) path else "/$path"
        val trimmed = withLeadingSlash.trimEnd('/')
        return trimmed.ifEmpty { PATH_ROOT }
    }

    private fun config(context: Context): JSONObject? {
        cachedConfig?.let { return it }
        return synchronized(this) {
            cachedConfig ?: runCatching {
                context.assets.open(CONFIG_ASSET_PATH).bufferedReader().use { it.readText() }
            }.getOrNull()
                ?.let { text -> runCatching { JSONObject(text) }.getOrNull() }
                ?.also { cachedConfig = it }
        }
    }
}
