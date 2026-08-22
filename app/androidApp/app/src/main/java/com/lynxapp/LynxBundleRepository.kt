package com.lynxapp

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import com.lynx.tasm.provider.AbsTemplateProvider
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import okhttp3.Call
import okhttp3.Callback as OkHttpCallback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject

/**
 * Resolves dev server, verified OTA cache, and embedded assets in that order,
 * and owns the OTA version list: the Application prefetches the manifest once
 * per process ([refreshManifest]); the root startup flow and route opens then
 * consult [pendingUpdateFor] and [download].
 */
class LynxBundleRepository(context: Context) : AbsTemplateProvider() {
    private val appContext = context.applicationContext
    private val client = AppHttpClient.instance
    private val cacheDirectory = File(appContext.filesDir, "lynx-bundles")

    // Manifest and download state. OkHttp callbacks arrive on background
    // threads, so every access synchronizes on updateLock.
    private val updateLock = Any()
    private var manifestEntries: Map<String, Update>? = null
    private var manifestInFlight = false
    private var manifestSettled = false
    private val manifestWaiters = mutableListOf<(Boolean) -> Unit>()
    private val downloadsInFlight = mutableMapOf<String, MutableList<(Boolean) -> Unit>>()
    private var cachedShaMemo: Pair<String, String?>? = null

    init {
        cacheDirectory.mkdirs()
    }

    /** Dev override, then the verified per-bundle cache, then the embedded asset. */
    fun urlForBundle(bundleName: String): String {
        DevelopmentSettings.recordLoadedBundle(appContext, bundleName)
        DevelopmentSettings.developmentUrl(appContext, bundleName)?.let { return it }
        DevelopmentSettings.deviceFileDevelopmentUrl(bundleName)?.let { return it }
        if (bundleName == BUNDLE_NAME) {
            val developmentUrl = BuildConfig.LYNX_DEV_BUNDLE_URL.trim()
            if (BuildConfig.DEBUG && developmentUrl.isNotEmpty()) return developmentUrl
        }
        return if (cachedSha256For(bundleName) != null) {
            cachedUrl(bundleName)
        } else {
            embeddedUrlForBundle(bundleName)
        }
    }

    fun cachedUrl(bundleName: String): String = "$CACHE_SCHEME://$bundleName"

    /** Embedded asset path for any bundle; the white-screen fallback target. */
    fun embeddedUrlForBundle(bundleName: String): String =
        "$EMBEDDED_BUNDLE_DIRECTORY/$bundleName.lynx.bundle"

    override fun loadTemplate(uri: String, callback: Callback) {
        when {
            uri.startsWith("https://") || uri.startsWith("http://") -> {
                loadRemote(uri, callback)
            }
            uri.startsWith("$CACHE_SCHEME://") -> {
                loadFile(cachedBundleFor(uri.removePrefix("$CACHE_SCHEME://")), callback)
            }
            else -> {
                Thread {
                    try {
                        appContext.assets.open(uri).use { callback.onSuccess(it.readBytes()) }
                    } catch (error: IOException) {
                        callback.onFailed(error.message ?: "Unable to load $uri")
                    }
                }.start()
            }
        }
    }

    /**
     * Fetches the OTA manifest once per process. Concurrent callers and later
     * [runWhenManifestReady] waiters share one request; once the fetch has
     * settled, its outcome is replayed instead of refetching. `true` means a
     * parsed version list is available.
     */
    fun refreshManifest(onComplete: (Boolean) -> Unit) {
        var fetch = false
        val settled: Boolean? = synchronized(updateLock) {
            when {
                manifestInFlight -> {
                    manifestWaiters.add(onComplete)
                    null
                }
                manifestSettled -> manifestEntries != null
                else -> {
                    manifestWaiters.add(onComplete)
                    manifestInFlight = true
                    fetch = true
                    null
                }
            }
        }
        when {
            settled != null -> onComplete(settled)
            fetch -> fetchManifest()
        }
    }

    /**
     * Runs [block] once the startup manifest fetch settled — immediately with
     * the outcome when already settled. Kicks off the fetch defensively when
     * nothing has started it yet so callers cannot wait forever.
     */
    fun runWhenManifestReady(block: (hasManifest: Boolean) -> Unit) {
        var startFetch = false
        val ready: Boolean? = synchronized(updateLock) {
            when {
                manifestEntries != null -> true
                manifestSettled -> false
                else -> {
                    manifestWaiters.add(block)
                    if (!manifestInFlight) startFetch = true
                    null
                }
            }
        }
        if (ready != null) {
            block(ready)
        } else if (startFetch) {
            refreshManifest { }
        }
    }

    /**
     * The manifest entry for [bundleName] when it differs from the verified
     * cache; null when the bundle is up to date or no version list is known.
     * Safe on the UI thread: the cached digest is memoized per bundle.
     */
    internal fun pendingUpdateFor(bundleName: String): Update? {
        val update = synchronized(updateLock) { manifestEntries }?.get(bundleName) ?: return null
        return if (update.sha256 == cachedSha256For(bundleName)) null else update
    }

    /**
     * Downloads and verifies [update] into the per-bundle cache: the byte
     * count must match `size`, the SHA-256 must match, and both files are
     * written atomically. Concurrent downloads of the same bundle share one
     * request.
     */
    internal fun download(update: Update, onComplete: (Boolean) -> Unit) {
        synchronized(updateLock) {
            val waiters = downloadsInFlight.getOrPut(update.bundle) { mutableListOf() }
            waiters.add(onComplete)
            if (waiters.size > 1) return
        }
        client.newCall(Request.Builder().url(update.url).build())
            .enqueue(object : OkHttpCallback {
                override fun onFailure(call: Call, e: IOException) {
                    Log.w(TAG, "Bundle update request failed", e)
                    finishDownload(update.bundle, false)
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        val body = it.body
                        if (!it.isSuccessful) {
                            finishDownload(update.bundle, false)
                            return
                        }
                        val bytes = body.bytes()
                        if (
                            bytes.size.toLong() != update.size ||
                            sha256(bytes) != update.sha256
                        ) {
                            Log.w(TAG, "Rejected bundle update: integrity check failed")
                            finishDownload(update.bundle, false)
                            return
                        }

                        runCatching {
                            writeAtomically(cachedBundleFor(update.bundle), bytes)
                            val metadata = JSONObject()
                                .put("engineVersion", ENGINE_VERSION)
                                .put("version", update.version)
                                .put("sha256", update.sha256)
                                .toString()
                                .toByteArray()
                            writeAtomically(cachedMetadataFor(update.bundle), metadata)
                        }.onSuccess {
                            synchronized(updateLock) { cachedShaMemo = null }
                            finishDownload(update.bundle, true)
                        }.onFailure { error ->
                            Log.w(TAG, "Could not persist bundle update", error)
                            finishDownload(update.bundle, false)
                        }
                    }
                }
            })
    }

    private fun fetchManifest() {
        if (
            DevelopmentSettings.developmentUrl(appContext, BUNDLE_NAME) != null ||
            DevelopmentSettings.deviceFileDevelopmentUrl(BUNDLE_NAME) != null ||
            (BuildConfig.DEBUG && BuildConfig.LYNX_DEV_BUNDLE_URL.isNotBlank())
        ) {
            finishManifest(null)
            return
        }

        val manifestUrl = BuildConfig.LYNX_UPDATE_MANIFEST_URL.trim()
        val parsedManifestUrl = manifestUrl.toHttpUrlOrNull()
        if (
            parsedManifestUrl == null ||
            (!BuildConfig.DEBUG && !parsedManifestUrl.isHttps)
        ) {
            finishManifest(null)
            return
        }

        client.newCall(Request.Builder().url(parsedManifestUrl).build())
            .enqueue(object : OkHttpCallback {
                override fun onFailure(call: Call, e: IOException) {
                    Log.w(TAG, "Manifest request failed", e)
                    finishManifest(null)
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        val body = it.body.string()
                        if (!it.isSuccessful) {
                            finishManifest(null)
                            return
                        }

                        val entries = runCatching {
                            parseManifest(body, parsedManifestUrl.toString())
                        }.getOrElse { error ->
                            Log.w(TAG, "Invalid update manifest", error)
                            null
                        }
                        finishManifest(entries)
                    }
                }
            })
    }

    /** Stores a parsed version list (null = fetch failed) and wakes every waiter. */
    private fun finishManifest(entries: Map<String, Update>?) {
        val waiters = synchronized(updateLock) {
            manifestInFlight = false
            manifestSettled = true
            if (entries != null) manifestEntries = entries
            manifestWaiters.toList().also { manifestWaiters.clear() }
        }
        val result = entries != null
        waiters.forEach { it(result) }
    }

    private fun finishDownload(bundleName: String, success: Boolean) {
        val waiters = synchronized(updateLock) { downloadsInFlight.remove(bundleName) } ?: return
        waiters.forEach { it(success) }
    }

    private fun parseManifest(json: String, manifestUrl: String): Map<String, Update> {
        val manifest = JSONObject(json)
        require(manifest.getInt("schemaVersion") == 1) { "Unsupported schema" }
        require(manifest.getString("engineVersion") == ENGINE_VERSION) {
            "Bundle engine version does not match host"
        }

        val base = manifestUrl.toHttpUrlOrNull() ?: error("Invalid manifest URL")
        val entries = manifest.getJSONArray("bundles")
        val byName = mutableMapOf<String, Update>()
        for (index in 0 until entries.length()) {
            val entry = entries.getJSONObject(index)
            val sha256 = entry.getString("sha256").lowercase()
            require(SHA_256.matches(sha256)) { "Invalid SHA-256" }
            val size = entry.getLong("size")
            require(size > 0) { "Invalid bundle size" }
            val url = base.resolve(entry.getString("url")) ?: error("Invalid bundle URL")
            require(BuildConfig.DEBUG || url.isHttps) { "OTA bundle must use HTTPS" }
            val name = entry.getString("name")
            byName[name] = Update(name, entry.getString("version"), url.toString(), sha256, size)
        }
        return byName
    }

    /**
     * SHA-256 recorded in the cache metadata for [bundleName] after
     * re-verifying the cached bytes, or null when the cache is absent or
     * stale. Memoized per bundle and reset after a successful download.
     */
    private fun cachedSha256For(bundleName: String): String? {
        synchronized(updateLock) { cachedShaMemo }
            ?.takeIf { it.first == bundleName }
            ?.let { return it.second }
        val computed = computeCachedSha256(bundleName)
        synchronized(updateLock) { cachedShaMemo = bundleName to computed }
        return computed
    }

    private fun computeCachedSha256(bundleName: String): String? {
        val bundle = cachedBundleFor(bundleName)
        val metadata = cachedMetadataFor(bundleName)
        if (!bundle.isFile || !metadata.isFile) return null
        return runCatching {
            val meta = JSONObject(metadata.readText())
            if (meta.getString("engineVersion") != ENGINE_VERSION) return@runCatching null
            val expected = meta.getString("sha256")
            if (expected == sha256(bundle.readBytes())) expected else null
        }.getOrDefault(null)
    }

    private fun cachedBundleFor(bundleName: String) = File(cacheDirectory, "$bundleName.lynx.bundle")

    private fun cachedMetadataFor(bundleName: String) = File(cacheDirectory, "$bundleName.metadata.json")

    private fun loadRemote(uri: String, callback: Callback) {
        val url = uri.toHttpUrlOrNull()
        if (url == null || (!BuildConfig.DEBUG && !url.isHttps)) {
            callback.onFailed("Only valid HTTPS bundle URLs are allowed in release builds")
            return
        }

        client.newCall(Request.Builder().url(url).build()).enqueue(object : OkHttpCallback {
            override fun onFailure(call: Call, e: IOException) {
                callback.onFailed(e.message ?: "Bundle request failed")
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val body = it.body
                    if (!it.isSuccessful) {
                        callback.onFailed("Bundle request returned HTTP ${it.code}")
                        return
                    }
                    callback.onSuccess(body.bytes())
                }
            }
        })
    }

    private fun loadFile(file: File, callback: Callback) {
        Thread {
            runCatching { file.readBytes() }
                .onSuccess(callback::onSuccess)
                .onFailure { callback.onFailed(it.message ?: "Unable to read bundle cache") }
        }.start()
    }

    private fun writeAtomically(file: File, data: ByteArray) {
        val atomicFile = AtomicFile(file)
        val stream = atomicFile.startWrite()
        try {
            stream.write(data)
            stream.fd.sync()
            atomicFile.finishWrite(stream)
        } catch (error: Throwable) {
            atomicFile.failWrite(stream)
            throw error
        }
    }

    private fun sha256(data: ByteArray): String = MessageDigest
        .getInstance("SHA-256")
        .digest(data)
        .joinToString("") { "%02x".format(it) }

    internal data class Update(
        val bundle: String,
        val version: String,
        val url: String,
        val sha256: String,
        val size: Long,
    )

    companion object {
        const val BUNDLE_NAME = "main"
        private const val TAG = "LynxBundleRepository"
        private const val CACHE_SCHEME = "lynx-cache"
        private const val EMBEDDED_BUNDLE_DIRECTORY = "lynxbundle"
        private const val ENGINE_VERSION = "3.9"
        private val SHA_256 = Regex("^[a-f0-9]{64}$")
    }
}
