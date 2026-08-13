package com.lynxapp

import android.app.Application
import android.content.Intent
import android.os.Handler
import android.os.Looper
import com.lynx.devtoolwrapper.LynxDevtoolGlobalHelper
import com.lynx.service.devtool.LynxDevToolService
import com.lynx.tasm.service.LynxServiceCenter
import com.lynxapp.activity.DebugActivity

/** Debug-only Lynx DevTool wiring. This source set is absent from release. */
object DevToolInitializer {
    fun registerService() {
        val devToolService = LynxDevToolService.INSTANCE
        devToolService.enableAllSessions()
        LynxServiceCenter.inst().registerService(devToolService)
        devToolService.setLynxDebugPresetValue(true)
        devToolService.setLogBoxPresetValue(true)
        devToolService.setLoadQJSBridge(true)
        // Keep V8 out of the APK; QuickJS exposes the CDP Runtime/Debugger domains.
        devToolService.setLoadV8Bridge(false)
    }

    fun onEnvironmentInitialized(application: Application) {
        val mainHandler = Handler(Looper.getMainLooper())
        LynxDevtoolGlobalHelper.getInstance().registerCardListener { url ->
            mainHandler.post {
                val intent = Intent(application, DebugActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    putExtra("url", url)
                }
                application.startActivity(intent)
            }
        }
    }
}
