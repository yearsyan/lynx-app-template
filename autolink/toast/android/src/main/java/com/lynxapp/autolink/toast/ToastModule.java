package com.lynxapp.autolink.toast;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.Color;
import android.os.Handler;
import android.os.Looper;
import android.view.View;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

/**
 * One-shot toast exported to Lynx as Toast. The bubble keeps the app's
 * custom styling in every system theme, and no notification permission is
 * ever required.
 *
 * Android renders it through two channels (see {@link ToastRouter}):
 *
 * 1. System channel (preferred): the bubble is added as a TYPE_TOAST window
 *    backed by a NotificationManagerService window token — the same pipeline
 *    the framework Toast uses, but with the app's own view. The window
 *    belongs to no Activity, so page exit transitions never carry the toast
 *    away; it stays pinned to the screen like the window-level toasts on
 *    iOS/HarmonyOS.
 * 2. In-app fallback: the bubble lives in an Activity's decor view and is
 *    re-anchored to the next resumed Activity while its host finishes, so
 *    the toast still rides through the exit animation pinned on screen.
 *
 * The fallback engages whenever the system channel cannot serve the toast:
 * hidden-API restrictions, an NMS refusal (app backgrounded, package
 * suspended, queue overflow — all detected through enqueueToast's boolean
 * return), or durations beyond the NMS window (~3.5s), which the in-app
 * channel can still honor with millisecond accuracy.
 */
@LynxNativeModule(name = ToastModule.NAME)
public final class ToastModule extends LynxContextModule {
    public static final String NAME = "Toast";

    public ToastModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void show(String message, ReadableMap options, Callback callback) {
        Activity activity = hostActivity();
        if (activity == null) {
            callback.invoke("Toast has no host Activity");
            return;
        }
        String type = options.hasKey("type") ? options.getString("type") : "info";
        boolean showIcon = !options.hasKey("showIcon") || options.getBoolean("showIcon");
        int backgroundColor = parseColor(
                options.hasKey("backgroundColor") ? options.getString("backgroundColor") : null,
                ToastBubble.DEFAULT_BACKGROUND);
        int textColor = parseColor(
                options.hasKey("textColor") ? options.getString("textColor") : null,
                ToastBubble.DEFAULT_TEXT_COLOR);
        long durationMs = options.hasKey("durationMs")
                ? (long) options.getDouble("durationMs")
                : 2000L;

        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            View bubble = ToastBubble.build(
                    activity, message, type, showIcon, backgroundColor, textColor);
            ToastRouter.show(activity, bubble, Math.max(durationMs, 0L));
            callback.invoke("");
        });
    }

    private static int parseColor(@Nullable String value, int fallback) {
        if (value == null) {
            return fallback;
        }
        try {
            return Color.parseColor(value);
        } catch (IllegalArgumentException error) {
            return fallback;
        }
    }

    @Nullable
    private Activity hostActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context instanceof ContextWrapper) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }
}
