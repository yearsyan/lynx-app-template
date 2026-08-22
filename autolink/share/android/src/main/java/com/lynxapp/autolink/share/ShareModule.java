package com.lynxapp.autolink.share;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.Application;
import android.content.BroadcastReceiver;
import android.content.ClipData;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.IntentFilter;
import android.app.PendingIntent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.MimeTypeMap;

import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableArray;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.util.ArrayList;
import java.util.Locale;

/**
 * System share sheet exported to Lynx as {@code Share}. The chooser is built
 * with a chosen-component {@link PendingIntent} (API 22+), so picking a
 * target resolves a {@code sent} outcome carrying the target package name;
 * the platform never reports a bare chooser dismissal, so the module
 * best-effort resolves {@code dismissed} when the host Activity resumes and
 * no chosen-component broadcast arrives within a short grace window. Sandbox {@code file://} payloads go
 * through the library's FileProvider; picker {@code content://} URIs are
 * passed through with a transient read grant.
 */
@LynxNativeModule(name = ShareModule.NAME)
public final class ShareModule extends LynxContextModule {
    public static final String NAME = "Share";

    private static final String ACTION_CHOSEN =
            "com.lynxapp.autolink.share.action.CHOSEN";
    private static final String FILE_PROVIDER_SUFFIX = ".lynx.share.fileprovider";
    private static final String MIME_FALLBACK = "application/octet-stream";
    private static final String MIME_ALL = "*/*";
    /**
     * The chosen-component broadcast is enqueued by the system at pick time,
     * but OEM choosers may finish (and resume us) before it lands, so a bare
     * dismissal is only declared once this grace window has passed.
     */
    private static final long DISMISS_GRACE_MS = 500;

    private final Context applicationContext;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    /** Guarded by itself; null while no share interaction is in flight. */
    @Nullable
    private Session session;

    public ShareModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void share(ReadableMap options, Callback callback) {
        final ShareRequest request;
        try {
            request = parseRequest(options);
        } catch (IllegalArgumentException error) {
            callback.invoke(errorJSON(error.getMessage()));
            return;
        }
        mainHandler.post(() -> startShare(request, callback));
    }

    @Override
    public void destroy() {
        mainHandler.post(() -> {
            Session active = session;
            if (active != null) {
                active.cancel();
                session = null;
            }
        });
    }

    // ------------------------------------------------------------------
    // Share flow (main thread)
    // ------------------------------------------------------------------

    private void startShare(ShareRequest request, Callback callback) {
        if (session != null) {
            callback.invoke(outcomeJSON("busy", null,
                    "Another share request is already active"));
            return;
        }
        Activity activity = resolveActivity();
        if (activity == null) {
            callback.invoke(errorJSON("Share requires a host Activity to present the chooser"));
            return;
        }
        final Intent target;
        try {
            target = buildTargetIntent(request);
        } catch (IllegalArgumentException error) {
            callback.invoke(errorJSON(error.getMessage()));
            return;
        }

        Session active = new Session(activity, callback);
        Intent chosen = new Intent(ACTION_CHOSEN).setPackage(applicationContext.getPackageName());
        @SuppressLint("MutablePendingIntent") // Chooser fill-in requires it.
        PendingIntent chosenIntent = PendingIntent.getBroadcast(
                applicationContext,
                0,
                chosen,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
        Intent chooser = Intent.createChooser(target, request.title, chosenIntent.getIntentSender());
        chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        try {
            active.register();
            activity.startActivity(chooser);
            session = active;
        } catch (Throwable error) {
            active.cancel();
            callback.invoke(errorJSON(messageOf(error, "Unable to open the share sheet")));
        }
    }

    private Intent buildTargetIntent(ShareRequest request) {
        String text = request.mergedText();
        ArrayList<Uri> streams = new ArrayList<>();
        for (String fileURI : request.files) {
            streams.add(resolveStreamURI(fileURI));
        }

        Intent intent;
        if (streams.isEmpty()) {
            intent = new Intent(Intent.ACTION_SEND);
            intent.setType("text/plain");
        } else if (streams.size() == 1) {
            intent = new Intent(Intent.ACTION_SEND);
            intent.setType(mimeTypeOf(streams.get(0), request.files.get(0)));
            intent.putExtra(Intent.EXTRA_STREAM, streams.get(0));
        } else {
            intent = new Intent(Intent.ACTION_SEND_MULTIPLE);
            intent.setType(commonMimeType(streams, request.files));
            intent.putParcelableArrayListExtra(Intent.EXTRA_STREAM, streams);
        }
        if (text != null) {
            intent.putExtra(Intent.EXTRA_TEXT, text);
        }
        if (request.title != null) {
            intent.putExtra(Intent.EXTRA_SUBJECT, request.title);
        }
        if (!streams.isEmpty()) {
            // ClipData is what the chooser actually forwards when granting
            // the transient read permission to the picked target.
            ClipData clip = null;
            ContentResolver resolver = applicationContext.getContentResolver();
            for (Uri stream : streams) {
                if (clip == null) {
                    clip = ClipData.newUri(resolver, "shared", stream);
                } else {
                    clip.addItem(new ClipData.Item(stream));
                }
            }
            intent.setClipData(clip);
        }
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return intent;
    }

    /** Maps a payload URI onto a grantable stream URI. */
    private Uri resolveStreamURI(String uriString) {
        Uri uri = Uri.parse(uriString);
        String scheme = uri.getScheme();
        if (ContentResolver.SCHEME_CONTENT.equals(scheme)) {
            return uri;
        }
        if (!ContentResolver.SCHEME_FILE.equals(scheme)) {
            throw new IllegalArgumentException(
                    "Share files must be file:// or content:// URIs: " + uriString);
        }
        String path = uri.getPath();
        if (path == null) {
            throw new IllegalArgumentException("Share file URI has no path: " + uriString);
        }
        File file = new File(path);
        if (!file.isFile()) {
            throw new IllegalArgumentException("Share file does not exist: " + uriString);
        }
        String authority = applicationContext.getPackageName() + FILE_PROVIDER_SUFFIX;
        return FileProvider.getUriForFile(applicationContext, authority, file);
    }

    private String mimeTypeOf(Uri uri, String uriString) {
        String extension = MimeTypeMap.getFileExtensionFromUrl(uriString);
        if (extension != null && !extension.isEmpty()) {
            String mime = MimeTypeMap.getSingleton()
                    .getMimeTypeFromExtension(extension.toLowerCase(Locale.US));
            if (mime != null) {
                return mime;
            }
        }
        if (ContentResolver.SCHEME_CONTENT.equals(uri.getScheme())) {
            String mime = applicationContext.getContentResolver().getType(uri);
            if (mime != null) {
                return mime;
            }
        }
        return MIME_FALLBACK;
    }

    /** Wildcard top-level type for images, or the all-mime wildcard for mixed types. */
    private String commonMimeType(ArrayList<Uri> streams, ArrayList<String> uriStrings) {
        String common = null;
        for (int index = 0; index < streams.size(); index++) {
            String mime = mimeTypeOf(streams.get(index), uriStrings.get(index));
            String topLevel = mime.substring(0, mime.indexOf('/') + 1) + "*";
            if (common == null) {
                common = topLevel;
            } else if (!common.equals(topLevel)) {
                return MIME_ALL;
            }
        }
        return common == null ? MIME_ALL : common;
    }

    /**
     * Resolves the Activity hosting this LynxView. The LynxContext is a
     * MutableContextWrapper whose base context is the activity the view was
     * built with.
     */
    @Nullable
    private Activity resolveActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context instanceof ContextWrapper) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }

    private Application application() {
        return (Application) applicationContext;
    }

    // ------------------------------------------------------------------
    // Session: chosen-component broadcast + dismissal heuristic
    // ------------------------------------------------------------------

    /**
     * One in-flight share interaction. The chooser's chosen-component
     * broadcast is queued by the system at pick time, while our resume fires
     * when the chooser finishes; OEM builds deliver them in either order, so
     * the dismissal verdict waits out a grace window after the resume.
     */
    private final class Session {
        private final Activity activity;
        private final Callback callback;
        private boolean settled;

        private final BroadcastReceiver chosenReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                ComponentName component;
                if (Build.VERSION.SDK_INT >= 33) {
                    component = intent.getParcelableExtra(
                            Intent.EXTRA_CHOSEN_COMPONENT, ComponentName.class);
                } else {
                    @SuppressWarnings("deprecation")
                    ComponentName legacy = intent.getParcelableExtra(Intent.EXTRA_CHOSEN_COMPONENT);
                    component = legacy;
                }
                complete(outcomeJSON("sent",
                        component == null ? null : component.getPackageName(), ""));
            }
        };

        private final Application.ActivityLifecycleCallbacks lifecycleCallbacks =
                new Application.ActivityLifecycleCallbacks() {
                    @Override
                    public void onActivityResumed(Activity resumed) {
                        if (resumed == activity) {
                            mainHandler.postDelayed(dismissalCheck, DISMISS_GRACE_MS);
                        }
                    }

                    @Override public void onActivityCreated(Activity a, Bundle b) {}
                    @Override public void onActivityStarted(Activity a) {}
                    @Override public void onActivityPaused(Activity a) {}
                    @Override public void onActivityStopped(Activity a) {}
                    @Override public void onActivitySaveInstanceState(Activity a, Bundle b) {}
                    @Override public void onActivityDestroyed(Activity a) {}
                };

        private final Runnable dismissalCheck = () -> complete(outcomeJSON(
                "dismissed", null, "Share sheet was dismissed without a target"));

        Session(Activity activity, Callback callback) {
            this.activity = activity;
            this.callback = callback;
        }

        void register() {
            IntentFilter filter = new IntentFilter(ACTION_CHOSEN);
            ContextCompat.registerReceiver(applicationContext, chosenReceiver, filter,
                    ContextCompat.RECEIVER_NOT_EXPORTED);
            application().registerActivityLifecycleCallbacks(lifecycleCallbacks);
        }

        void cancel() {
            mainHandler.removeCallbacks(dismissalCheck);
            try {
                applicationContext.unregisterReceiver(chosenReceiver);
            } catch (Throwable ignored) {
            }
            application().unregisterActivityLifecycleCallbacks(lifecycleCallbacks);
        }

        void complete(String result) {
            if (settled) {
                return;
            }
            settled = true;
            cancel();
            session = null;
            callback.invoke(result);
        }
    }

    // ------------------------------------------------------------------
    // Request parsing and result encoding
    // ------------------------------------------------------------------

    private static final class ShareRequest {
        @Nullable final String title;
        @Nullable final String text;
        @Nullable final String url;
        final ArrayList<String> files;

        ShareRequest(@Nullable String title, @Nullable String text,
                @Nullable String url, ArrayList<String> files) {
            this.title = title;
            this.text = text;
            this.url = url;
            this.files = files;
        }

        /** ACTION_SEND has no link field, so links ride inside EXTRA_TEXT. */
        @Nullable
        String mergedText() {
            if (text != null && url != null) {
                return text + "\n" + url;
            }
            return text != null ? text : url;
        }
    }

    private static ShareRequest parseRequest(ReadableMap options) {
        if (options == null) {
            throw new IllegalArgumentException("Share options must not be null");
        }
        String title = optionalString(options, "title");
        String text = optionalString(options, "text");
        String url = optionalString(options, "url");
        ArrayList<String> files = new ArrayList<>();
        ReadableArray fileArray = options.getArray("files");
        if (fileArray != null) {
            for (int index = 0; index < fileArray.size(); index++) {
                String uri = fileArray.getString(index);
                if (uri != null && !uri.trim().isEmpty()) {
                    files.add(uri.trim());
                }
            }
        }
        if (text == null && url == null && files.isEmpty()) {
            throw new IllegalArgumentException(
                    "Share requires a non-empty text, url or files payload");
        }
        return new ShareRequest(title, text, url, files);
    }

    @Nullable
    private static String optionalString(ReadableMap options, String key) {
        if (!options.hasKey(key) || options.isNull(key)) {
            return null;
        }
        String value = options.getString(key);
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }

    private static String outcomeJSON(String code, @Nullable String activityType, String message) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("activityType",
                    activityType == null ? JSONObject.NULL : activityType);
            value.put("message", message == null ? "" : message);
            JSONObject result = new JSONObject();
            result.put("error", "");
            result.put("value", value);
            return result.toString();
        } catch (JSONException exception) {
            return errorJSON("Unable to encode share result");
        }
    }

    private static String errorJSON(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"error\":\"Unable to encode share result\"}";
        }
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
