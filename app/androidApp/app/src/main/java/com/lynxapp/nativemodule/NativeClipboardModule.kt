package com.lynxapp.nativemodule

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback

/** Plain-text system clipboard; JSON encoding stays in TypeScript. */
class NativeClipboardModule(context: Context) : LynxModule(context) {
    private val appContext = context.applicationContext

    @LynxMethod
    fun setString(text: String, callback: Callback) {
        runCatching {
            clipboard().setPrimaryClip(ClipData.newPlainText(CLIP_LABEL, text))
        }.onSuccess {
            callback.invoke("")
        }.onFailure { error ->
            callback.invoke(error.message ?: "Unable to write the clipboard")
        }
    }

    @LynxMethod
    fun getString(callback: Callback) {
        val text = runCatching {
            val clip = clipboard().primaryClip
            if (clip == null || clip.itemCount == 0) {
                null
            } else {
                clip.getItemAt(0).coerceToText(appContext)?.toString()
            }
        }.getOrNull()
        callback.invoke(text)
    }

    private fun clipboard(): ClipboardManager =
        appContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

    companion object {
        const val NAME = "NativeClipboardModule"
        private const val CLIP_LABEL = "lynx.clipboard"
    }
}
