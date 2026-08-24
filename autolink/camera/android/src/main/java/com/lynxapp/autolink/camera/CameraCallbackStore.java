package com.lynxapp.autolink.camera;

import com.lynx.react.bridge.Callback;

import org.json.JSONException;
import org.json.JSONObject;

/** Bridges the transparent system-camera Activity back to the Lynx module. */
final class CameraCallbackStore {
    private static final Object LOCK = new Object();
    private static Callback pendingCallback;

    private CameraCallbackStore() {}

    static boolean begin(Callback callback) {
        synchronized (LOCK) {
            if (pendingCallback != null) {
                return false;
            }
            pendingCallback = callback;
            return true;
        }
    }

    static void completeOutcome(String code, CameraPhoto photo, String message) {
        complete(outcomeJSON(code, photo, message));
    }

    static void fail(Throwable error, String fallback) {
        String message = error.getMessage();
        complete(errorJSON(message == null || message.trim().isEmpty() ? fallback : message));
    }

    static String outcomeJSON(String code, CameraPhoto photo, String message) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("photo", photo == null ? JSONObject.NULL : photo.toJSON());
            value.put("message", message == null ? "" : message);
            JSONObject result = new JSONObject();
            result.put("error", "");
            result.put("value", value);
            return result.toString();
        } catch (JSONException exception) {
            return errorJSON("Unable to encode the camera result");
        }
    }

    static String errorJSON(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message == null ? "Camera failed" : message);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"error\":\"Unable to encode the camera result\"}";
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
