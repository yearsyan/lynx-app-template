package com.lynxapp.autolink.scanner;

import com.lynx.react.bridge.Callback;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Bridges the scanner Activity and image decoder back to the current Lynx
 * module. Only one request may be in flight at a time.
 */
final class ScannerCallbackStore {
    private static final Object LOCK = new Object();
    private static Callback pendingCallback;

    private ScannerCallbackStore() {}

    static boolean begin(Callback callback) {
        synchronized (LOCK) {
            if (pendingCallback != null) {
                return false;
            }
            pendingCallback = callback;
            return true;
        }
    }

    /** Resolves a structured outcome such as success / userCancel / busy. */
    static void completeOutcome(String code, String content, String format, String message) {
        complete(outcomeJSON(code, content, format, message));
    }

    static void fail(Throwable error, String fallback) {
        String message = error.getMessage();
        complete(errorJSON(message == null || message.trim().isEmpty() ? fallback : message));
    }

    static void fail(String message) {
        complete(errorJSON(message));
    }

    static String outcomeJSON(String code, String content, String format, String message) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("content", content == null ? JSONObject.NULL : content);
            value.put("format", format == null ? JSONObject.NULL : format);
            value.put("message", message == null ? "" : message);
            JSONObject result = new JSONObject();
            result.put("error", "");
            result.put("value", value);
            return result.toString();
        } catch (JSONException exception) {
            return errorJSON("Unable to encode scanner result");
        }
    }

    private static String errorJSON(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"error\":\"Unable to encode scanner result\"}";
        }
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
}
