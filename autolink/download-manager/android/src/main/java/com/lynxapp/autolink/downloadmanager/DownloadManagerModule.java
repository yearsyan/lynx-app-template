package com.lynxapp.autolink.downloadmanager;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONArray;
import org.json.JSONObject;

import java.net.URI;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.regex.Pattern;

/** Download task bridge with an optional Android foreground-service adapter. */
@LynxNativeModule(name = DownloadManagerModule.NAME)
public final class DownloadManagerModule extends LynxContextModule
        implements DownloadEngine.Listener {
    public static final String NAME = "DownloadManager";
    public static final String EVENT_NAME = "downloadManager";

    private static final Pattern TASK_ID = Pattern.compile("^[A-Za-z0-9._-]{1,128}$");
    private static final Pattern HEADER_NAME =
            Pattern.compile("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");

    private final DownloadEngine engine;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final boolean debugBuild;
    private volatile boolean destroyed = false;

    public DownloadManagerModule(LynxContext context) {
        super(context);
        Context applicationContext = context.getApplicationContext();
        engine = DownloadEngine.get(applicationContext);
        engine.addListener(this);
        ApplicationInfo info = applicationContext.getApplicationInfo();
        debugBuild = (info.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    @LynxMethod
    public void getCapabilities(Callback callback) {
        try {
            JSONObject capabilities = new JSONObject();
            capabilities.put("platform", "android");
            capabilities.put("executionModes", new JSONArray()
                    .put(DownloadEngine.MODE_IN_APP)
                    .put(DownloadEngine.MODE_ANDROID_FOREGROUND));
            capabilities.put("byteRangeResume", true);
            capabilities.put("processRestartRecovery", true);
            callback.invoke(result(capabilities, ""));
        } catch (Throwable error) {
            callback.invoke(result(JSONObject.NULL, messageOf(error)));
        }
    }

    @LynxMethod
    public void enqueue(ReadableMap options, Callback callback) {
        try {
            DownloadEngine.Options normalized = options(options);
            callback.invoke(result(engine.enqueue(normalized).toJSON(), ""));
        } catch (Throwable error) {
            callback.invoke(result(JSONObject.NULL, messageOf(error)));
        }
    }

    @LynxMethod
    public void pause(String id, Callback callback) {
        taskCommand(callback, id, engine::pause);
    }

    @LynxMethod
    public void resume(String id, Callback callback) {
        taskCommand(callback, id, engine::resume);
    }

    @LynxMethod
    public void cancel(String id, Callback callback) {
        taskCommand(callback, id, engine::cancel);
    }

    @LynxMethod
    public void remove(String id, boolean deleteFile, Callback callback) {
        try {
            validateID(id);
            engine.remove(id, deleteFile);
            callback.invoke(result(JSONObject.NULL, ""));
        } catch (Throwable error) {
            callback.invoke(result(JSONObject.NULL, messageOf(error)));
        }
    }

    @LynxMethod
    public void getTask(String id, Callback callback) {
        try {
            validateID(id);
            DownloadEngine.Snapshot snapshot = engine.getTask(id);
            callback.invoke(result(snapshot == null ? JSONObject.NULL : snapshot.toJSON(), ""));
        } catch (Throwable error) {
            callback.invoke(result(JSONObject.NULL, messageOf(error)));
        }
    }

    @LynxMethod
    public void listTasks(Callback callback) {
        try {
            callback.invoke(result(engine.snapshotsJSON(), ""));
        } catch (Throwable error) {
            callback.invoke(result(JSONObject.NULL, messageOf(error)));
        }
    }

    @Override
    public void onDownloadEvent(String type, DownloadEngine.Snapshot snapshot) {
        if (destroyed) return;
        mainHandler.post(() -> {
            if (destroyed || mLynxContext == null) return;
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", type);
            payload.putMap("task", taskMap(snapshot));
            mLynxContext.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload));
        });
    }

    @Override
    public void destroy() {
        destroyed = true;
        engine.removeListener(this);
    }

    private interface TaskCommand {
        DownloadEngine.Snapshot run(String id) throws Exception;
    }

    private void taskCommand(Callback callback, String id, TaskCommand command) {
        try {
            validateID(id);
            callback.invoke(result(command.run(id).toJSON(), ""));
        } catch (Throwable error) {
            callback.invoke(result(JSONObject.NULL, messageOf(error)));
        }
    }

    private DownloadEngine.Options options(ReadableMap value) throws Exception {
        if (destroyed) throw new IllegalStateException("DownloadManager host has been destroyed");
        String id = string(value, "id");
        String url = string(value, "url");
        String fileName = string(value, "fileName");
        int progressIntervalMs = value.getInt("progressIntervalMs");
        boolean persistProgress = value.getBoolean("persistProgress");
        boolean foreground = value.getBoolean("androidForegroundService");
        String notificationTitle = string(value, "notificationTitle");
        String notificationText = string(value, "notificationText");

        validateID(id);
        validateURL(url);
        validateFileName(fileName);
        if (progressIntervalMs < 100 || progressIntervalMs > 10_000) {
            throw new IllegalArgumentException(
                    "progressIntervalMs must be between 100 and 10000");
        }
        if (notificationTitle.isEmpty() || notificationTitle.length() > 80) {
            throw new IllegalArgumentException("Invalid foreground notification title");
        }
        if (notificationText.isEmpty() || notificationText.length() > 160) {
            throw new IllegalArgumentException("Invalid foreground notification text");
        }

        Map<String, String> headers = headers(value.getMap("headers"));
        return new DownloadEngine.Options(
                id,
                url,
                fileName,
                headers,
                progressIntervalMs,
                persistProgress,
                foreground,
                notificationTitle,
                notificationText);
    }

    private void validateURL(String value) throws Exception {
        if (value.length() > 8192) throw new IllegalArgumentException("Download URL is too long");
        URI uri = new URI(value);
        String scheme = uri.getScheme();
        if (scheme == null || uri.getHost() == null) {
            throw new IllegalArgumentException("Invalid download URL");
        }
        if ("https".equalsIgnoreCase(scheme)) return;
        if (debugBuild && "http".equalsIgnoreCase(scheme)) return;
        throw new IllegalArgumentException("Download URL must use HTTPS (HTTP is Debug-only)");
    }

    private static void validateID(String value) {
        if (value == null || !TASK_ID.matcher(value).matches()) {
            throw new IllegalArgumentException("Invalid download task ID");
        }
    }

    private static void validateFileName(String value) {
        if (value.isEmpty() || value.length() > 128
                || ".".equals(value) || "..".equals(value)
                || !value.equals(value.trim())
                || value.indexOf('/') >= 0 || value.indexOf('\\') >= 0) {
            throw new IllegalArgumentException("Invalid download fileName");
        }
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            if (character < 0x20 || character == 0x7f) {
                throw new IllegalArgumentException("Invalid download fileName");
            }
        }
    }

    private static Map<String, String> headers(@Nullable ReadableMap value) {
        Map<String, String> result = new LinkedHashMap<>();
        if (value == null) return result;
        Map<String, Object> input = value.toHashMap();
        if (input.size() > 64) {
            throw new IllegalArgumentException("Too many download headers");
        }
        for (Map.Entry<String, Object> entry : input.entrySet()) {
            String name = entry.getKey();
            Object rawValue = entry.getValue();
            if (!HEADER_NAME.matcher(name).matches() || !(rawValue instanceof String)) {
                throw new IllegalArgumentException("Invalid download header: " + name);
            }
            String lower = name.toLowerCase(java.util.Locale.ROOT);
            if (lower.equals("accept-encoding") || lower.equals("host")
                    || lower.equals("content-length")
                    || lower.equals("connection") || lower.equals("transfer-encoding")
                    || lower.equals("range") || lower.equals("if-range")) {
                throw new IllegalArgumentException("DownloadManager owns the " + name + " header");
            }
            String headerValue = (String) rawValue;
            if (headerValue.length() > 8192
                    || headerValue.indexOf('\r') >= 0 || headerValue.indexOf('\n') >= 0) {
                throw new IllegalArgumentException("Invalid download header: " + name);
            }
            result.put(name, headerValue);
        }
        return result;
    }

    private static String string(ReadableMap map, String key) {
        String value = map == null ? null : map.getString(key);
        return value == null ? "" : value;
    }

    private static JavaOnlyMap taskMap(DownloadEngine.Snapshot task) {
        JavaOnlyMap value = new JavaOnlyMap();
        value.putString("id", task.id);
        value.putString("url", task.url);
        value.putString("fileName", task.fileName);
        value.putString("state", task.state);
        value.putString("executionMode", task.executionMode);
        value.putBoolean("persistProgress", task.persistProgress);
        value.putDouble("bytesDownloaded", task.bytesDownloaded);
        if (task.totalBytes == null) value.putNull("totalBytes");
        else value.putDouble("totalBytes", task.totalBytes);
        if (task.fileUri == null) value.putNull("fileUri");
        else value.putString("fileUri", task.fileUri);
        if (task.error == null) value.putNull("error");
        else value.putString("error", task.error);
        value.putDouble("createdAt", task.createdAt);
        value.putDouble("updatedAt", task.updatedAt);
        return value;
    }

    private static String result(Object value, String error) {
        try {
            JSONObject envelope = new JSONObject();
            envelope.put("value", value == null ? JSONObject.NULL : value);
            envelope.put("error", error == null ? "" : error);
            return envelope.toString();
        } catch (Throwable failure) {
            return "{\"value\":null,\"error\":\"Unable to encode DownloadManager result\"}";
        }
    }

    private static String messageOf(Throwable error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? "DownloadManager operation failed"
                : message;
    }
}
