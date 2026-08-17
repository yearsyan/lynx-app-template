package com.lynxapp

import okhttp3.OkHttpClient

/** Shared native HTTP stack for Lynx fetch, development bundles, and OTA updates. */
internal object AppHttpClient {
    val instance: OkHttpClient = OkHttpClient.Builder()
        .apply {
            AppInstrumentation.networkInterceptor?.let { addNetworkInterceptor(it) }
        }
        .build()
}
