package com.lynxapp.autolink.permissions;

import android.app.NotificationManager;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentActivity;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Unified runtime permission surface exported to Lynx as Permissions.
 *
 * Android cannot report whether a runtime permission was never requested
 * (the platform returns the same denial before the first prompt and after
 * "don't ask again"), so check never reports 'notDetermined' here:
 * a 'denied' status still means request() may show the system prompt.
 * 'notifications' additionally consults the app-level notification switch
 * (NotificationManager.areNotificationsEnabled), which is the real gate on
 * Android 12 and below and covers POST_NOTIFICATIONS on 13+.
 */
@LynxNativeModule(name = PermissionsModule.NAME)
public final class PermissionsModule extends LynxContextModule {
    public static final String NAME = "Permissions";

    static final String TYPE_NOTIFICATIONS = "notifications";
    static final String TYPE_CAMERA = "camera";
    static final String TYPE_PHOTO_LIBRARY = "photoLibrary";
    static final String TYPE_MICROPHONE = "microphone";

    /** Serializes prompts; one system dialog at a time per Lynx view. */
    private final AtomicBoolean requestActive = new AtomicBoolean(false);

    public PermissionsModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void check(ReadableMap permission, Callback callback) {
        final String type;
        try {
            type = parseType(permission);
        } catch (IllegalArgumentException error) {
            callback.invoke(errorResult(messageOf(error, "Invalid permission request")));
            return;
        }
        try {
            callback.invoke(stateResult(checkStatus(type)));
        } catch (Throwable error) {
            callback.invoke(errorResult(messageOf(error, "Unable to query the permission")));
        }
    }

    @LynxMethod
    public void request(ReadableMap permission, Callback callback) {
        final String type;
        try {
            type = parseType(permission);
        } catch (IllegalArgumentException error) {
            callback.invoke(errorResult(messageOf(error, "Invalid permission request")));
            return;
        }
        if (TYPE_NOTIFICATIONS.equals(type) && Build.VERSION.SDK_INT < 33) {
            // No runtime prompt exists below Android 13; the app-level
            // notification switch is the only state to report.
            try {
                callback.invoke(stateResult(checkStatus(type)));
            } catch (Throwable error) {
                callback.invoke(errorResult(messageOf(error, "Unable to query notifications")));
            }
            return;
        }
        if (!requestActive.compareAndSet(false, true)) {
            callback.invoke(errorResult("Another permission request is already active"));
            return;
        }

        // The fragment transaction and ActivityResult launcher must run on the
        // main thread; the Lynx JS thread posts the request, then resolves the
        // host before touching FragmentActivity (mirrors BiometricModule).
        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            final FragmentActivity activity = resolveFragmentActivity();
            if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                requestActive.set(false);
                callback.invoke(errorResult(
                        "Permissions prompts require the host activity to be a FragmentActivity"));
                return;
            }
            final String[] permissions = androidPermissionsFor(type);
            try {
                PermissionPrompt.request(activity, permissions, result -> {
                    requestActive.set(false);
                    try {
                        callback.invoke(stateResult(statusAfterRequest(type, result)));
                    } catch (Throwable error) {
                        callback.invoke(errorResult(messageOf(error, "Unable to query the permission")));
                    }
                });
            } catch (Throwable error) {
                requestActive.set(false);
                callback.invoke(errorResult(messageOf(error, "Unable to show the permission prompt")));
            }
        });
    }

    private String checkStatus(String type) {
        Context context = applicationContext();
        switch (type) {
            case TYPE_NOTIFICATIONS:
                return notificationStatus(context);
            case TYPE_CAMERA:
                return runtimeStatus(context, android.Manifest.permission.CAMERA);
            case TYPE_MICROPHONE:
                return runtimeStatus(context, android.Manifest.permission.RECORD_AUDIO);
            case TYPE_PHOTO_LIBRARY:
                return photoLibraryStatus(context);
            default:
                throw new IllegalArgumentException("Unknown permission type: " + type);
        }
    }

    /** statusAfterRequest runs after the prompt, when re-checking is enough. */
    private String statusAfterRequest(String type, Map<String, Boolean> granted) {
        Context context = applicationContext();
        if (TYPE_PHOTO_LIBRARY.equals(type) && Build.VERSION.SDK_INT >= 34) {
            // The Android 14 partial-access answer grants only
            // READ_MEDIA_VISUAL_USER_SELECTED; re-checking both permissions
            // classifies it as 'limited'.
            return photoLibraryStatus(context);
        }
        for (Boolean value : granted.values()) {
            if (value == null || !value) {
                return TYPE_NOTIFICATIONS.equals(type)
                        ? notificationStatus(context)
                        : "denied";
            }
        }
        return TYPE_NOTIFICATIONS.equals(type)
                ? notificationStatus(context)
                : "granted";
    }

    private static String runtimeStatus(Context context, String permission) {
        return context.checkPermission(permission, android.os.Process.myPid(),
                android.os.Process.myUid()) == PackageManager.PERMISSION_GRANTED
                        ? "granted"
                        : "denied";
    }

    private static String photoLibraryStatus(Context context) {
        if (Build.VERSION.SDK_INT >= 34) {
            if (context.checkPermission(android.Manifest.permission.READ_MEDIA_IMAGES,
                    android.os.Process.myPid(), android.os.Process.myUid())
                    == PackageManager.PERMISSION_GRANTED) {
                return "granted";
            }
            return context.checkPermission(
                    android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                    android.os.Process.myPid(), android.os.Process.myUid())
                            == PackageManager.PERMISSION_GRANTED
                                    ? "limited"
                                    : "denied";
        }
        if (Build.VERSION.SDK_INT >= 33) {
            return runtimeStatus(context, android.Manifest.permission.READ_MEDIA_IMAGES);
        }
        // This template supports Android 7.0+, where external-storage access
        // is always a runtime permission. The manifest caps it at API 32.
        return runtimeStatus(context, android.Manifest.permission.READ_EXTERNAL_STORAGE);
    }

    private static String notificationStatus(Context context) {
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        return manager != null && manager.areNotificationsEnabled() ? "granted" : "denied";
    }

    /** Runtime permissions to prompt for; empty when already satisfied. */
    private String[] androidPermissionsFor(String type) {
        switch (type) {
            case TYPE_NOTIFICATIONS:
                return new String[] { android.Manifest.permission.POST_NOTIFICATIONS };
            case TYPE_CAMERA:
                return new String[] { android.Manifest.permission.CAMERA };
            case TYPE_MICROPHONE:
                return new String[] { android.Manifest.permission.RECORD_AUDIO };
            case TYPE_PHOTO_LIBRARY:
                if (Build.VERSION.SDK_INT >= 34) {
                    // Requesting both lets the system dialog offer full,
                    // partial ("Select photos") or no access.
                    return new String[] {
                            android.Manifest.permission.READ_MEDIA_IMAGES,
                            android.Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED,
                    };
                }
                if (Build.VERSION.SDK_INT >= 33) {
                    return new String[] { android.Manifest.permission.READ_MEDIA_IMAGES };
                }
                return new String[] { android.Manifest.permission.READ_EXTERNAL_STORAGE };
            default:
                throw new IllegalArgumentException("Unknown permission type: " + type);
        }
    }

    private static String parseType(ReadableMap permission) {
        String type = permission != null && permission.hasKey("type")
                && !permission.isNull("type") ? permission.getString("type") : null;
        if (TYPE_NOTIFICATIONS.equals(type) || TYPE_CAMERA.equals(type)
                || TYPE_PHOTO_LIBRARY.equals(type) || TYPE_MICROPHONE.equals(type)) {
            return type;
        }
        throw new IllegalArgumentException("Unknown permission type: " + type);
    }

    private static JavaOnlyMap stateResult(String status) {
        JavaOnlyMap value = new JavaOnlyMap();
        value.putString("status", status);
        JavaOnlyMap result = new JavaOnlyMap();
        result.putMap("value", value);
        return result;
    }

    private static JavaOnlyMap errorResult(String message) {
        JavaOnlyMap result = new JavaOnlyMap();
        result.putString("error", message);
        return result;
    }

    /**
     * Resolves the FragmentActivity hosting this LynxView, mirroring
     * BiometricModule. The LynxContext is a MutableContextWrapper whose
     * base context is the activity the view was built with.
     */
    @Nullable
    private FragmentActivity resolveFragmentActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context instanceof ContextWrapper) {
            if (context instanceof FragmentActivity) {
                return (FragmentActivity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }

    private Context applicationContext() {
        Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
        if (context == null && mContext != null) {
            context = mContext.getApplicationContext();
        }
        if (context == null) {
            throw new IllegalStateException("Permissions has no host context");
        }
        return context;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
