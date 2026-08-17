package com.lynxapp.autolink.albumutils;

import android.net.Uri;

import com.lynx.react.bridge.Callback;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.Collections;
import java.util.List;

/** Bridges the result-only proxy Activity back to the current Lynx module. */
final class PickerCallbackStore {
    private static final Object LOCK = new Object();
    private static Callback pendingCallback;

    private PickerCallbackStore() {}

    static boolean begin(Callback callback) {
        synchronized (LOCK) {
            if (pendingCallback != null) {
                return false;
            }
            pendingCallback = callback;
            return true;
        }
    }

    static void succeed(List<Uri> uris) {
        complete(resultJSON(uris, ""));
    }

    static void fail(Throwable error, String fallback) {
        String message = error.getMessage();
        complete(errorJSON(message == null || message.isEmpty() ? fallback : message));
    }

    static void fail(String message) {
        complete(errorJSON(message));
    }

    static String errorJSON(String message) {
        return resultJSON(Collections.emptyList(), message);
    }

    private static void complete(String result) {
        Callback callback;
        synchronized (LOCK) {
            callback = pendingCallback;
            pendingCallback = null;
        }
        if (callback != null) {
            callback.invoke(result);
        }
    }

    private static String resultJSON(List<Uri> uris, String error) {
        try {
            JSONArray values = new JSONArray();
            for (Uri uri : uris) {
                values.put(uri.toString());
            }
            JSONObject result = new JSONObject();
            result.put("uris", values);
            result.put("error", error);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"uris\":[],\"error\":\"Unable to encode image picker result\"}";
        }
    }
}
