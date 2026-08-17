package com.lynxapp

import android.app.Application
import okhttp3.Interceptor

/** Release no-op; Stetho is a debugImplementation-only dependency. */
object AppInstrumentation {
    val networkInterceptor: Interceptor? = null

    fun init(app: Application) = Unit
}
