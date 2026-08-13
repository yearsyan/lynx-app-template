package com.lynxapp.nativemodule

import android.content.Context
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback
import com.tencent.mmkv.MMKV

/** String primitives shared by every bundle; JSON encoding stays in TypeScript. */
class NativeKVModule(context: Context) : LynxModule(context) {
    private val storage: MMKV = requireNotNull(MMKV.mmkvWithID(STORAGE_ID)) {
        "Unable to open MMKV storage $STORAGE_ID"
    }

    @LynxMethod
    fun setString(key: String, value: String, callback: Callback) {
        val error = if (isValidKey(key) && storage.encode(key, value)) {
            ""
        } else {
            "Unable to persist MMKV key"
        }
        callback.invoke(error)
    }

    @LynxMethod
    fun getString(key: String, defaultValue: String?, callback: Callback) {
        if (!isValidKey(key)) {
            callback.invoke(defaultValue)
            return
        }
        callback.invoke(storage.decodeString(key, defaultValue))
    }

    @LynxMethod
    fun remove(key: String, callback: Callback) {
        if (!isValidKey(key)) {
            callback.invoke("MMKV key must not be empty")
            return
        }
        storage.removeValueForKey(key)
        callback.invoke("")
    }

    @LynxMethod
    fun clear(callback: Callback) {
        storage.clearAll()
        callback.invoke("")
    }

    @LynxMethod
    fun contains(key: String, callback: Callback) {
        callback.invoke(isValidKey(key) && storage.containsKey(key))
    }

    private fun isValidKey(key: String): Boolean = key.isNotBlank()

    companion object {
        const val NAME = "NativeKVModule"
        private const val STORAGE_ID = "lynx.native.kv"
    }
}
