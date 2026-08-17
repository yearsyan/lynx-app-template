package com.lynxapp

import android.app.Application
import com.facebook.stetho.Stetho
import okhttp3.Interceptor

/** Debug-only instrumentation backed by Stetho (chrome://inspect + dumpapp). */
object AppInstrumentation {
    val networkInterceptor: Interceptor? = com.facebook.stetho.okhttp3.StethoInterceptor()

    fun init(app: Application) {
        Stetho.initializeWithDefaults(app)
    }
}
