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

/** Resolves dev server, verified OTA cache, and embedded assets in that order. */
class LynxBundleRepository(context: Context) : AbsTemplateProvider() {
    private val appContext = context.applicationContext
    private val client = AppHttpClient.instance
    private val cacheDirectory = File(appContext.filesDir, "lynx-bundles")
    private val cachedBundle = File(cacheDirectory, EMBEDDED_BUNDLE)
    private val cachedMetadata = File(cacheDirectory, CACHE_METADATA)

    init {
        cacheDirectory.mkdirs()
    }

    fun startupUrl(): String {
        DevelopmentSettings.recordLoadedBundle(appContext, BUNDLE_NAME)
        DevelopmentSettings.developmentUrl(appContext, BUNDLE_NAME)?.let { return it }
        val developmentUrl = BuildConfig.LYNX_DEV_BUNDLE_URL.trim()
        if (BuildConfig.DEBUG && developmentUrl.isNotEmpty()) {
            return developmentUrl
        }
        return if (hasValidCachedBundle()) cachedUrl() else EMBEDDED_BUNDLE_PATH
    }

    fun cachedUrl(): String = "$CACHE_SCHEME://$BUNDLE_NAME"

    /** OTA policy currently applies to main; every bundle may have a debug override. */
    fun urlForBundle(bundleName: String): String {
        DevelopmentSettings.recordLoadedBundle(appContext, bundleName)
        DevelopmentSettings.developmentUrl(appContext, bundleName)?.let { return it }
        return if (bundleName == BUNDLE_NAME) {
            startupUrl()
        } else {
            "$EMBEDDED_BUNDLE_DIRECTORY/$bundleName.lynx.bundle"
        }
    }

    override fun loadTemplate(uri: String, callback: Callback) {
        when {
            uri.startsWith("https://") || uri.startsWith("http://") -> {
                loadRemote(uri, callback)
            }
            uri.startsWith("$CACHE_SCHEME://") -> {
                loadFile(cachedBundle, callback)
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

    fun checkForUpdate(onComplete: (Boolean) -> Unit) {
        if (
            DevelopmentSettings.developmentUrl(appContext, BUNDLE_NAME) != null ||
            (BuildConfig.DEBUG && BuildConfig.LYNX_DEV_BUNDLE_URL.isNotBlank())
        ) {
            onComplete(false)
            return
        }

        val manifestUrl = BuildConfig.LYNX_UPDATE_MANIFEST_URL.trim()
        val parsedManifestUrl = manifestUrl.toHttpUrlOrNull()
        if (
            parsedManifestUrl == null ||
            (!BuildConfig.DEBUG && !parsedManifestUrl.isHttps)
        ) {
            onComplete(false)
            return
        }

        client.newCall(Request.Builder().url(parsedManifestUrl).build())
            .enqueue(object : OkHttpCallback {
                override fun onFailure(call: Call, e: IOException) {
                    Log.w(TAG, "Manifest request failed", e)
                    onComplete(false)
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        val body = it.body.string()
                        if (!it.isSuccessful) {
                            onComplete(false)
                            return
                        }

                        val update = runCatching {
                            parseUpdate(body, parsedManifestUrl.toString())
                        }.getOrElse { error ->
                            Log.w(TAG, "Invalid update manifest", error)
                            null
                        }
                        if (update == null || update.sha256 == cachedSha256()) {
                            onComplete(false)
                            return
                        }
                        downloadUpdate(update, onComplete)
                    }
                }
            })
    }

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

    private fun parseUpdate(json: String, manifestUrl: String): Update {
        val manifest = JSONObject(json)
        require(manifest.getInt("schemaVersion") == 1) { "Unsupported schema" }
        require(manifest.getString("engineVersion") == ENGINE_VERSION) {
            "Bundle engine version does not match host"
        }

        val entries = manifest.getJSONArray("bundles")
        for (index in 0 until entries.length()) {
            val entry = entries.getJSONObject(index)
            if (entry.getString("name") != BUNDLE_NAME) continue

            val sha256 = entry.getString("sha256").lowercase()
            require(SHA_256.matches(sha256)) { "Invalid SHA-256" }
            val size = entry.getLong("size")
            require(size > 0) { "Invalid bundle size" }
            val base = manifestUrl.toHttpUrlOrNull() ?: error("Invalid manifest URL")
            val url = base.resolve(entry.getString("url"))
                ?: error("Invalid bundle URL")
            require(BuildConfig.DEBUG || url.isHttps) { "OTA bundle must use HTTPS" }
            return Update(entry.getString("version"), url.toString(), sha256, size)
        }
        error("Manifest does not contain $BUNDLE_NAME")
    }

    private fun downloadUpdate(update: Update, onComplete: (Boolean) -> Unit) {
        client.newCall(Request.Builder().url(update.url).build()).enqueue(object : OkHttpCallback {
            override fun onFailure(call: Call, e: IOException) {
                Log.w(TAG, "Bundle update request failed", e)
                onComplete(false)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val body = it.body
                    if (!it.isSuccessful) {
                        onComplete(false)
                        return
                    }
                    val bytes = body.bytes()
                    if (
                        bytes.size.toLong() != update.size ||
                        sha256(bytes) != update.sha256
                    ) {
                        Log.w(TAG, "Rejected bundle update: integrity check failed")
                        onComplete(false)
                        return
                    }

                    runCatching {
                        writeAtomically(cachedBundle, bytes)
                        val metadata = JSONObject()
                            .put("engineVersion", ENGINE_VERSION)
                            .put("version", update.version)
                            .put("sha256", update.sha256)
                            .toString()
                            .toByteArray()
                        writeAtomically(cachedMetadata, metadata)
                    }.onSuccess {
                        onComplete(true)
                    }.onFailure { error ->
                        Log.w(TAG, "Could not persist bundle update", error)
                        onComplete(false)
                    }
                }
            }
        })
    }

    private fun hasValidCachedBundle(): Boolean {
        if (!cachedBundle.isFile || !cachedMetadata.isFile) return false
        return runCatching {
            val metadata = JSONObject(cachedMetadata.readText())
            metadata.getString("engineVersion") == ENGINE_VERSION &&
                metadata.getString("sha256") == sha256(cachedBundle.readBytes())
        }.getOrDefault(false)
    }

    private fun cachedSha256(): String? {
        if (!hasValidCachedBundle()) return null
        return JSONObject(cachedMetadata.readText()).getString("sha256")
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

    private data class Update(
        val version: String,
        val url: String,
        val sha256: String,
        val size: Long,
    )

    companion object {
        const val BUNDLE_NAME = "main"
        private const val TAG = "LynxBundleRepository"
        private const val CACHE_SCHEME = "lynx-cache"
        private const val CACHE_METADATA = "main.metadata.json"
        private const val EMBEDDED_BUNDLE_DIRECTORY = "lynxbundle"
        private const val EMBEDDED_BUNDLE = "main.lynx.bundle"
        private const val EMBEDDED_BUNDLE_PATH = "lynxbundle/main.lynx.bundle"
        private const val ENGINE_VERSION = "3.9"
        private val SHA_256 = Regex("^[a-f0-9]{64}$")
    }
}
