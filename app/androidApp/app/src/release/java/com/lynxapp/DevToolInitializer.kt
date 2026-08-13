package com.lynxapp

import android.app.Application

/** Release no-op: DevTool and its V8 runtime are not release dependencies. */
object DevToolInitializer {
    fun registerService() = Unit

    @Suppress("UNUSED_PARAMETER")
    fun onEnvironmentInitialized(application: Application) = Unit
}
