package com.lynxapp.nativemodule

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.ReadableMap
import com.lynxapp.activity.LynxPageActivity
import com.lynxapp.activity.TransparentLynxPageActivity
import org.json.JSONObject

/** Opens another Lynx bundle in a real Android Activity. */
class NativeRouterModule(context: Context, param: Any?) : LynxModule(context, param) {
    private val activity: Activity? = param as? Activity

    @LynxMethod
    fun open(options: ReadableMap, callback: Callback) {
        val bundle = options.getString("bundle", "")
        if (!BUNDLE_NAME.matches(bundle)) {
            callback.invoke("Invalid Lynx bundle name: $bundle")
            return
        }

        val host = activity
        if (host == null) {
            callback.invoke("Native router has no Activity host")
            return
        }

        val presentation = options.getString("presentation", PRESENTATION_PUSH)
        val transparent = options.getBoolean(
            "transparent",
            presentation == PRESENTATION_SHEET,
        )
        val params = options.getMap("params")?.toHashMap().orEmpty()
        host.runOnUiThread {
            runCatching {
                val destination = if (transparent) {
                    TransparentLynxPageActivity::class.java
                } else {
                    LynxPageActivity::class.java
                }
                host.startActivity(
                    Intent(host, destination).apply {
                        putExtra(LynxPageActivity.EXTRA_BUNDLE, bundle)
                        putExtra(LynxPageActivity.EXTRA_PRESENTATION, presentation)
                        putExtra(LynxPageActivity.EXTRA_TRANSPARENT, transparent)
                        putExtra(
                            LynxPageActivity.EXTRA_PARAMS_JSON,
                            JSONObject(params).toString(),
                        )
                    },
                )
                if (presentation == PRESENTATION_SHEET || presentation == PRESENTATION_MODAL) {
                    host.overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
                }
            }.onSuccess {
                callback.invoke("")
            }.onFailure { error ->
                callback.invoke(error.message ?: "Unable to open native route")
            }
        }
    }

    @LynxMethod
    fun close(callback: Callback) {
        val host = activity
        if (host !is LynxPageActivity) {
            callback.invoke("The root route cannot be closed")
            return
        }
        host.runOnUiThread {
            host.finish()
            if (host.routePresentation != PRESENTATION_PUSH) {
                host.overridePendingTransition(android.R.anim.fade_in, android.R.anim.fade_out)
            }
            callback.invoke("")
        }
    }

    companion object {
        const val NAME = "NativeRouterModule"
        const val PRESENTATION_PUSH = "push"
        const val PRESENTATION_MODAL = "modal"
        const val PRESENTATION_SHEET = "sheet"
        private val BUNDLE_NAME = Regex("^[a-z0-9][a-z0-9-]*$")
    }
}
