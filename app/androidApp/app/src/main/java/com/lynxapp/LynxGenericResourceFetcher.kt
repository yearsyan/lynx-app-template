// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSES/Apache-2.0.txt file in the root directory of this repository.
// Modified by the Lynx template project to use its shared application transport.

package com.lynxapp

import com.lynx.tasm.resourceprovider.LynxResourceCallback
import com.lynx.tasm.resourceprovider.LynxResourceRequest
import com.lynx.tasm.resourceprovider.LynxResourceResponse
import com.lynx.tasm.resourceprovider.generic.LynxGenericResourceFetcher
import java.io.IOException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.Response

/**
 * App-owned fetcher for runtime-loaded Lynx resources such as rspeedy HMR
 * patches, which the engine requests outside the template provider flow.
 */
internal object LynxGenericResourceFetcher : LynxGenericResourceFetcher() {
    override fun fetchResource(
        request: LynxResourceRequest,
        callback: LynxResourceCallback<ByteArray>,
    ) {
        val call = runCatching {
            val url = Request.Builder().url(request.url).build().url
            require(BuildConfig.DEBUG || url.isHttps) {
                "Cleartext HTTP is disabled in release builds"
            }
            AppHttpClient.instance.newCall(Request.Builder().url(url).build())
        }.getOrElse { error ->
            deliverFailure(request.url, error, callback)
            return
        }

        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                deliverFailure(request.url, e, callback)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    val body = runCatching { it.body?.bytes() }.getOrElse { error ->
                        deliverFailure(request.url, error, callback)
                        return
                    }
                    if (!it.isSuccessful) {
                        deliverFailure(
                            request.url,
                            IOException("HTTP ${it.code} for ${request.url}"),
                            callback,
                        )
                        return
                    }
                    callback.onResponse(LynxResourceResponse.onSuccess(body ?: ByteArray(0)))
                }
            }
        })
    }

    override fun fetchResourcePath(
        request: LynxResourceRequest,
        callback: LynxResourceCallback<String>,
    ) {
        deliverFailure(request.url, UnsupportedOperationException("unsupported: ${request.url}"), callback)
    }

    override fun cancel(request: LynxResourceRequest) {
        // The shared OkHttp client does not expose per-request cancellation;
        // in-flight reads complete and are dropped when the view is destroyed.
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> deliverFailure(
        url: String,
        error: Throwable,
        callback: LynxResourceCallback<T>,
    ) {
        if (BuildConfig.DEBUG) android.util.Log.w(TAG, "resource fetch failed: $url", error)
        callback.onResponse(LynxResourceResponse.onFailed(error) as LynxResourceResponse<T>)
    }

    private const val TAG = "LynxResourceFetch"
}
