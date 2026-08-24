package com.lynxapp

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import android.util.Log
import com.lynx.tasm.provider.AbsTemplateProvider
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.Call
import okhttp3.Callback as OkHttpCallback
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject

/**
 * Resolves dev server, verified OTA cache, and embedded assets in that order,
 * and owns the OTA version list. The Application prefetches the manifest once
 * per process ([refreshManifest]); every page entry (root and pushed routes)
 * then goes through [resolveEntryUrl], which briefly waits for the manifest
 * and for a changed bundle before falling back to the best verified source.
 */
class LynxBundleRepository(context: Context) : AbsTemplateProvider() {
    private val appContext = context.applicationContext
    private val client = AppHttpClient.instance
    private val cacheDirectory = File(appContext.filesDir, "lynx-bundles")
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "lynx-bundle-resolver").apply { isDaemon = true }
    }

    // Manifest and download state. OkHttp callbacks arrive on background
    // threads, so every access synchronizes on updateLock.
    private val updateLock = Any()
    private var manifestEntries: Map<String, Update>? = null
    private var manifestInFlight = false
    private var manifestSettled = false
    private val manifestWaiters = mutableListOf<(Boolean) -> Unit>()
    private val downloadsInFlight = mutableMapOf<String, MutableList<(Boolean) -> Unit>>()
    private var cachedShaMemo: Pair<String, String?>? = null
    private val embeddedShaMemo = ConcurrentHashMap<String, String?>()
    private var embeddedPreloadMap: Map<String, List<String>>? = null

    init {
        cacheDirectory.mkdirs()
    }

    /** Dev override, then the verified per-bundle cache, then the embedded asset. */
    fun urlForBundle(bundleName: String): String {
        DevelopmentSettings.recordLoadedBundle(appContext, bundleName)
        developmentOverridesFor(bundleName)?.let { return it }
        cachedSha256For(bundleName)?.let { return cachedUrl(bundleName, it) }
        return embeddedUrlForBundle(bundleName)
    }

    /**
     * Unified entry resolution for every page (root and pushed routes):
     * 1. a dev override wins immediately — development flows skip OTA;
     * 2. otherwise wait up to [MANIFEST_WAIT_MS] for the prefetched manifest
     *    and compare its SHA-256 with the verified cache (or the embedded
     *    asset when no download exists);
     * 3. on a mismatch, wait up to [DOWNLOAD_TIMEOUT_MS] for the download to
     *    finish. The result is the best verified source — a timed-out or
     *    failed download keeps the previous cache or embedded bundle; the
     *    download itself continues in the background for the next entry.
     *
     * [onDownloadStarted] fires once on the main thread (before [onReady])
     * when a bundle download will block the entry, so the caller can show a
     * splash. [onReady] fires exactly once on the main thread.
     */
    fun resolveEntryUrl(
        bundleName: String,
        onReady: (String) -> Unit,
        onDownloadStarted: () -> Unit = {},
    ) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { resolveEntryUrl(bundleName, onReady, onDownloadStarted) }
            return
        }
        DevelopmentSettings.recordLoadedBundle(appContext, bundleName)
        developmentOverridesFor(bundleName)?.let { return onReady(it) }

        val settled = AtomicBoolean(false)
        fun finish(url: String) {
            if (settled.compareAndSet(false, true)) {
                mainHandler.post { onReady(url) }
            }
        }
        waitForManifestWithin(MANIFEST_WAIT_MS) {
            ioExecutor.execute {
                val update = synchronized(updateLock) { manifestEntries }?.get(bundleName)
                val fallback = bestUrlFor(bundleName)
                if (update == null || update.sha256 == currentShaFor(bundleName)) {
                    finish(fallback)
                } else {
                    mainHandler.post(onDownloadStarted)
                    downloadWithin(update, DOWNLOAD_TIMEOUT_MS) { success ->
                        finish(
                            if (success) {
                                cachedUrl(bundleName, update.sha256)
                            } else {
                                fallback
                            },
                        )
                    }
                }
            }
        }
    }

    /** The cache URL embeds the SHA-256 so engine groups key per version. */
    fun cachedUrl(bundleName: String, sha256: String): String =
        "$CACHE_SCHEME://$bundleName?v=$sha256"

    /** Embedded asset path for any bundle; the white-screen fallback target. */
    fun embeddedUrlForBundle(bundleName: String): String =
        "$EMBEDDED_BUNDLE_DIRECTORY/$bundleName.lynx.bundle"

    override fun loadTemplate(uri: String, callback: Callback) {
        // The version query only versions the URL for engine groups; the
        // provider always resolves the plain cache path.
        val path = uri.substringBefore('?')
        when {
            path.startsWith("https://") || path.startsWith("http://") -> {
                loadRemote(path, callback)
            }
            path.startsWith("$CACHE_SCHEME://") -> {
                loadFile(cachedBundleFor(path.removePrefix("$CACHE_SCHEME://")), callback)
            }
            else -> {
                Thread {
                    try {
                        appContext.assets.open(path).use { callback.onSuccess(it.readBytes()) }
                    } catch (error: IOException) {
                        callback.onFailed(error.message ?: "Unable to load $path")
                    }
                }.start()
            }
        }
    }

    /**
     * Fetches the OTA manifest once per process. Concurrent callers and later
     * waiters share one request; once the fetch has settled, its outcome is
     * replayed instead of refetching. `true` means a parsed version list is
     * available.
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
     * Downloads and verifies [update] into the per-bundle cache: the byte
     * count must match `size`, the SHA-256 must match, and both files are
     * written atomically. Concurrent downloads of the same bundle share one
     * request.
     */
    private fun download(update: Update, onComplete: (Boolean) -> Unit) {
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
        if (developmentOverridesFor(BUNDLE_NAME) != null) {
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

    private fun developmentOverridesFor(bundleName: String): String? {
        DevelopmentSettings.developmentUrl(appContext, bundleName)?.let { return it }
        DevelopmentSettings.deviceFileDevelopmentUrl(bundleName)?.let { return it }
        if (bundleName == BUNDLE_NAME) {
            val developmentUrl = BuildConfig.LYNX_DEV_BUNDLE_URL.trim()
            if (BuildConfig.DEBUG && developmentUrl.isNotEmpty()) return developmentUrl
        }
        return null
    }

    /**
     * Runs [onDone] once on the main thread, as soon as the manifest settles
     * or [timeoutMs] passes — whichever comes first.
     */
    private fun waitForManifestWithin(timeoutMs: Long, onDone: () -> Unit) {
        val fired = AtomicBoolean(false)
        fun fire() {
            if (fired.compareAndSet(false, true)) mainHandler.post(onDone)
        }
        var startFetch = false
        synchronized(updateLock) {
            when {
                manifestSettled -> fire()
                else -> {
                    manifestWaiters.add { _ -> fire() }
                    if (!manifestInFlight) {
                        manifestInFlight = true
                        startFetch = true
                    }
                }
            }
        }
        if (startFetch) fetchManifest()
        mainHandler.postDelayed({ fire() }, timeoutMs)
    }

    /**
     * Runs [block] on the IO executor once the manifest has settled, however
     * long that takes (a missing URL settles immediately; the network is
     * bounded by the HTTP client's own timeouts). Used by the background
     * preload, which must not skip bundles just because the manifest was slow.
     */
    private fun whenManifestReadyOnIo(block: () -> Unit) {
        var startFetch = false
        val ready = synchronized(updateLock) {
            when {
                manifestSettled -> true
                else -> {
                    manifestWaiters.add { _ -> ioExecutor.execute(block) }
                    if (!manifestInFlight) {
                        manifestInFlight = true
                        startFetch = true
                    }
                    false
                }
            }
        }
        if (ready) ioExecutor.execute(block)
        if (startFetch) fetchManifest()
    }

    /**
     * Schedules the OTA preload for [triggerBundle]'s dependents 200ms after
     * its first screen: every bundle whose package.json `lynxBundle.downloadAt`
     * listed this one downloads in parallel when the manifest marks it
     * outdated. Bundles without an update are skipped, and in-flight
     * downloads are shared with page-entry waits, never restarted.
     */
    fun schedulePreloadAfterFirstScreen(triggerBundle: String) {
        mainHandler.postDelayed({
            ioExecutor.execute {
                val targets = preloadTargetsFor(triggerBundle)
                if (targets.isEmpty()) return@execute
                whenManifestReadyOnIo {
                    for (target in targets) preloadIfOutdated(target)
                }
            }
        }, PRELOAD_DELAY_MS)
    }

    /** Fire-and-forget download of an outdated bundle, deduped in flight. */
    private fun preloadIfOutdated(bundleName: String) {
        if (developmentOverridesFor(bundleName) != null) return
        val update = synchronized(updateLock) { manifestEntries }?.get(bundleName) ?: return
        if (update.sha256 == currentShaFor(bundleName)) return
        Log.i(TAG, "Preloading outdated bundle $bundleName")
        download(update) { }
    }

    /**
     * The `preload_bundles` list for [bundleName] from the embedded
     * lynx-bundles.json; parsed once per process and tolerant of manifests
     * generated before the field existed.
     */
    private fun preloadTargetsFor(bundleName: String): List<String> {
        synchronized(updateLock) { embeddedPreloadMap }?.let { return it[bundleName].orEmpty() }
        val parsed = runCatching { parseEmbeddedPreloadMap() }.getOrElse { error ->
            Log.w(TAG, "Unable to parse embedded lynx-bundles.json", error)
            emptyMap()
        }
        synchronized(updateLock) { embeddedPreloadMap = parsed }
        return parsed[bundleName].orEmpty()
    }

    private fun parseEmbeddedPreloadMap(): Map<String, List<String>> {
        appContext.assets.open("$EMBEDDED_BUNDLE_DIRECTORY/lynx-bundles.json").use { stream ->
            val entries = JSONObject(stream.readBytes().decodeToString()).getJSONArray("bundles")
            val byTrigger = mutableMapOf<String, List<String>>()
            for (index in 0 until entries.length()) {
                val entry = entries.getJSONObject(index)
                val preload = entry.optJSONArray("preload_bundles") ?: continue
                val targets = mutableListOf<String>()
                for (position in 0 until preload.length()) {
                    targets.add(preload.getString(position))
                }
                byTrigger[entry.getString("name")] = targets
            }
            return byTrigger
        }
    }

    /**
     * [download] with a timeout: fires once on the main thread; a timed-out
     * download keeps running so its result lands for the next entry.
     */
    private fun downloadWithin(update: Update, timeoutMs: Long, onDone: (Boolean) -> Unit) {
        val fired = AtomicBoolean(false)
        fun fire(success: Boolean) {
            if (fired.compareAndSet(false, true)) mainHandler.post { onDone(success) }
        }
        download(update) { success -> fire(success) }
        mainHandler.postDelayed({ fire(false) }, timeoutMs)
    }

    /** The verified per-bundle cache when present, otherwise the embedded asset. */
    private fun bestUrlFor(bundleName: String): String {
        cachedSha256For(bundleName)?.let { return cachedUrl(bundleName, it) }
        return embeddedUrlForBundle(bundleName)
    }

    /**
     * The SHA-256 of the currently best source: the verified cache digest, or
     * the embedded asset's digest when no download exists. Memoized per bundle.
     */
    private fun currentShaFor(bundleName: String): String? =
        cachedSha256For(bundleName) ?: embeddedShaFor(bundleName)

    private fun embeddedShaFor(bundleName: String): String? =
        embeddedShaMemo.getOrPut(bundleName) { computeEmbeddedSha(bundleName) }

    private fun computeEmbeddedSha(bundleName: String): String? = runCatching {
        appContext.assets.open(embeddedUrlForBundle(bundleName)).use { sha256(it.readBytes()) }
    }.getOrNull()

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
        private const val MANIFEST_WAIT_MS = 400L
        private const val DOWNLOAD_TIMEOUT_MS = 3000L
        private const val PRELOAD_DELAY_MS = 200L
        private val SHA_256 = Regex("^[a-f0-9]{64}$")
    }
}
