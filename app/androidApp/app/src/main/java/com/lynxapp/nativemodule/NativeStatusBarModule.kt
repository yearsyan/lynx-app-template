package com.lynxapp.nativemodule

import android.app.Activity
import android.content.Context
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback
import com.lynxapp.component.isLynxStatusBarStyle
import com.lynxapp.component.setLynxStatusBarStyle

/** Controls status-bar icon/text contrast for the Activity hosting this Lynx page. */
class NativeStatusBarModule(context: Context, param: Any?) : LynxModule(context, param) {
    private val activity: Activity? = param as? Activity

    @LynxMethod
    fun setStyle(style: String, callback: Callback) {
        if (!isLynxStatusBarStyle(style)) {
            callback.invoke("Invalid status bar style: $style")
            return
        }
        val host = activity
        if (host == null) {
            callback.invoke("Native status bar has no Activity host")
            return
        }
        host.runOnUiThread {
            host.setLynxStatusBarStyle(style)
            callback.invoke("")
        }
    }

    companion object {
        const val NAME = "NativeStatusBarModule"
    }
}
