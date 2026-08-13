// Copyright 2024 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSES/Apache-2.0.txt file in the root directory of this repository.
// Modified by the Lynx template project to use its shared application transport.

package com.lynxapp

import android.util.Log
import com.lynx.jsbridge.network.HttpRequest
import com.lynx.jsbridge.network.HttpResponse as LynxHttpResponse
import com.lynx.jsbridge.network.HttpStreamingDelegate
import com.lynx.react.bridge.JavaOnlyMap
import com.lynx.tasm.service.ILynxHttpService
import com.lynx.tasm.service.LynxHttpRequestCallback
import java.io.IOException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/** App-owned Lynx fetch transport backed by the host's shared OkHttp client. */
internal object LynxTemplateHttpService : ILynxHttpService {
    private const val SDK_ERROR_STATUS_CODE = 499
    private const val DEPRECATED_STREAMING_FLAG = "useStreaming"
    private const val TAG = "LynxTemplateHttp"

    override fun request(request: HttpRequest, callback: LynxHttpRequestCallback) {
        execute(request, callback, null)
    }

    override fun requestStreaming(
        request: HttpRequest,
        callback: LynxHttpRequestCallback,
        delegate: HttpStreamingDelegate,
    ) {
        execute(request, callback, delegate)
    }

    private fun execute(
        lynxRequest: HttpRequest,
        callback: LynxHttpRequestCallback,
        streamingDelegate: HttpStreamingDelegate?,
    ) {
        val call = runCatching {
            AppHttpClient.instance.newCall(buildRequest(lynxRequest))
        }.getOrElse { error ->
            deliverFailure(lynxRequest.url.orEmpty(), error, callback, streamingDelegate)
            return
        }

        call.enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                deliverFailure(lynxRequest.url.orEmpty(), e, callback, streamingDelegate)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (BuildConfig.DEBUG) {
                        Log.d(TAG, "${lynxRequest.httpMethod} ${it.request.url.host} -> ${it.code}")
                    }

                    callback.invoke(it.toLynxResponse(includeBody = streamingDelegate == null))
                    if (streamingDelegate == null) return

                    try {
                        it.body?.byteStream()?.use { bodyStream ->
                            if (
                                lynxRequest.customConfig?.getBoolean(
                                    DEPRECATED_STREAMING_FLAG,
                                    false,
                                ) == true
                            ) {
                                streamingDelegate.deprecatedChunkedStreamingBody(bodyStream)
                            } else {
                                streamingDelegate.streamingBody(bodyStream)
                            }
                        }
                    } catch (error: IOException) {
                        streamingDelegate.onError(error.message ?: error.toString())
                    } finally {
                        streamingDelegate.onEnd()
                    }
                }
            }
        })
    }

    private fun buildRequest(request: HttpRequest): Request {
        val method = request.httpMethod?.uppercase().orEmpty().ifEmpty { "GET" }
        val url = request.url?.toHttpUrlOrNull() ?: error("Invalid HTTP URL")
        require(BuildConfig.DEBUG || url.isHttps) {
            "Cleartext HTTP is disabled in release builds"
        }
        val body = when (method) {
            "GET", "HEAD" -> null
            else -> (request.httpBody ?: byteArrayOf()).toRequestBody(null)
        }
        val builder = Request.Builder()
            .url(url)
            .method(method, body)

        request.httpHeaders?.asHashMap()?.forEach { (name, value) ->
            if (value != null) builder.addHeader(name, value.toString())
        }
        return builder.build()
    }

    private fun Response.toLynxResponse(includeBody: Boolean): LynxHttpResponse {
        val headers = JavaOnlyMap()
        this.headers.toMultimap().forEach { (name, values) ->
            headers.putString(name, values.joinToString(","))
        }
        val responseBody = if (includeBody) body?.bytes() ?: byteArrayOf() else null
        return LynxHttpResponse().apply {
            statusCode = code
            statusText = message
            url = request.url.toString()
            httpHeaders = headers
            if (includeBody) {
                httpBody = responseBody
            }
        }
    }

    private fun deliverFailure(
        url: String,
        error: Throwable,
        callback: LynxHttpRequestCallback,
        streamingDelegate: HttpStreamingDelegate?,
    ) {
        val message = error.message ?: error.toString()
        if (BuildConfig.DEBUG) Log.w(TAG, "Request failed", error)
        callback.invoke(LynxHttpResponse().apply {
            this.url = url
            statusCode = SDK_ERROR_STATUS_CODE
            statusText = message
        })
        streamingDelegate?.onError(message)
        streamingDelegate?.onEnd()
    }
}
