package com.lynxapp.autolink.localnotification;

import android.content.Context;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

/**
 * Local notifications exported to Lynx as LocalNotification. Notification
 * permission is requested through the separate Permissions module; this
 * module only checks the enablement gate and reports 'permissionDenied'
 * when posting would be silently dropped.
 */
@LynxNativeModule(name = LocalNotificationModule.NAME)
public final class LocalNotificationModule extends LynxContextModule {
    public static final String NAME = "LocalNotification";

    private static final long MAX_DELAY_MS = 7L * 24 * 60 * 60 * 1000;

    public LocalNotificationModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void notify(ReadableMap optionsMap, Callback callback) {
        final Options options;
        try {
            options = Options.parse(optionsMap);
        } catch (RuntimeException error) {
            callback.invoke(errorResult(messageOf(error, "Invalid notification options")));
            return;
        }
        try {
            Context context = applicationContext();
            if (!LocalNotificationPresenter.notificationsEnabled(context)) {
                callback.invoke(outcomeResult("permissionDenied",
                        "Notifications are disabled; request the notification permission"
                                + " (Permissions module) or enable them in system settings"));
                return;
            }
            if (options.delayMs > 0) {
                LocalNotificationPresenter.schedule(
                        context, options.id, options.title, options.body,
                        options.sound, options.delayMs);
            } else {
                LocalNotificationPresenter.post(
                        context, options.id, options.title, options.body, options.sound);
            }
            callback.invoke(outcomeResult("success", ""));
        } catch (Throwable error) {
            callback.invoke(outcomeResult("unavailable",
                    messageOf(error, "Unable to post the notification")));
        }
    }

    @LynxMethod
    public void cancel(String id, Callback callback) {
        if (id == null || id.trim().isEmpty()) {
            callback.invoke("LocalNotification id must not be empty");
            return;
        }
        try {
            LocalNotificationPresenter.cancel(applicationContext(), id);
            callback.invoke("");
        } catch (Throwable error) {
            callback.invoke(messageOf(error, "Unable to cancel the notification"));
        }
    }

    @LynxMethod
    public void cancelAll(Callback callback) {
        try {
            LocalNotificationPresenter.cancelAll(applicationContext());
            callback.invoke("");
        } catch (Throwable error) {
            callback.invoke(messageOf(error, "Unable to cancel notifications"));
        }
    }

    private static JavaOnlyMap outcomeResult(String code, String message) {
        JavaOnlyMap value = new JavaOnlyMap();
        value.putString("code", code);
        value.putString("message", message == null ? "" : message);
        JavaOnlyMap result = new JavaOnlyMap();
        result.putMap("value", value);
        return result;
    }

    private static JavaOnlyMap errorResult(String message) {
        JavaOnlyMap result = new JavaOnlyMap();
        result.putString("error", message);
        return result;
    }

    private Context applicationContext() {
        Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
        if (context == null && mContext != null) {
            context = mContext.getApplicationContext();
        }
        if (context == null) {
            throw new IllegalStateException("LocalNotification has no host context");
        }
        return context;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }

    /** Bridge-level subset of the shared option contracts. */
    private static final class Options {
        final String id;
        final String title;
        final String body;
        final long delayMs;
        final boolean sound;

        private Options(String id, String title, String body, long delayMs, boolean sound) {
            this.id = id;
            this.title = title;
            this.body = body;
            this.delayMs = delayMs;
            this.sound = sound;
        }

        static Options parse(ReadableMap options) {
            String id = requireNonEmpty(optionalString(options, "id"), "LocalNotification id");
            String title = requireNonEmpty(
                    optionalString(options, "title"), "LocalNotification title");
            double rawDelay = options != null && options.hasKey("delayMs")
                    && !options.isNull("delayMs") ? options.getDouble("delayMs") : 0.0;
            if (!Double.isFinite(rawDelay) || rawDelay != Math.rint(rawDelay)
                    || rawDelay < 0 || rawDelay > MAX_DELAY_MS) {
                throw new IllegalArgumentException(
                        "LocalNotification delayMs must be between 0 and " + MAX_DELAY_MS);
            }
            long delayMs = (long) rawDelay;
            return new Options(
                    id,
                    title,
                    optionalString(options, "body"),
                    delayMs,
                    options == null || !options.hasKey("sound")
                            || options.isNull("sound") || options.getBoolean("sound"));
        }

        private static String optionalString(ReadableMap options, String key) {
            if (options == null || !options.hasKey(key) || options.isNull(key)) {
                return "";
            }
            String value = options.getString(key);
            return value == null ? "" : value;
        }

        private static String requireNonEmpty(String value, String field) {
            String trimmed = value == null ? "" : value.trim();
            if (trimmed.isEmpty()) {
                throw new IllegalArgumentException(field + " must not be empty");
            }
            return trimmed;
        }
    }
}
