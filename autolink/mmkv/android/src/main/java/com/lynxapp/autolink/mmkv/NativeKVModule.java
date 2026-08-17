package com.lynxapp.autolink.mmkv;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;
import com.tencent.mmkv.MMKV;

import java.util.concurrent.atomic.AtomicBoolean;

/** String primitives shared by every bundle; JSON encoding stays in TypeScript. */
@LynxNativeModule(name = NativeKVModule.NAME)
public class NativeKVModule extends LynxContextModule {
    public static final String NAME = "NativeKVModule";
    private static final String STORAGE_ID = "lynx.native.kv";
    private static final AtomicBoolean INITIALIZED = new AtomicBoolean(false);

    private final MMKV storage;

    public NativeKVModule(LynxContext context) {
        super(context);
        // The library owns its MMKV bootstrap so hosts no longer call
        // MMKV.initialize() themselves; the call is idempotent per process.
        if (INITIALIZED.compareAndSet(false, true)) {
            MMKV.initialize(context);
        }
        storage = MMKV.mmkvWithID(STORAGE_ID);
    }

    @LynxMethod
    public void setString(String key, String value, Callback callback) {
        boolean ok = isValidKey(key) && storage.encode(key, value);
        callback.invoke(ok ? "" : "Unable to persist MMKV key");
    }

    @LynxMethod
    public void getString(String key, @Nullable String defaultValue, Callback callback) {
        if (!isValidKey(key)) {
            callback.invoke(defaultValue);
            return;
        }
        callback.invoke(storage.decodeString(key, defaultValue));
    }

    @LynxMethod
    public void remove(String key, Callback callback) {
        if (!isValidKey(key)) {
            callback.invoke("MMKV key must not be empty");
            return;
        }
        storage.removeValueForKey(key);
        callback.invoke("");
    }

    @LynxMethod
    public void clear(Callback callback) {
        storage.clearAll();
        callback.invoke("");
    }

    @LynxMethod
    public void contains(String key, Callback callback) {
        callback.invoke(isValidKey(key) && storage.containsKey(key));
    }

    private static boolean isValidKey(String key) {
        return key != null && !key.trim().isEmpty();
    }
}
