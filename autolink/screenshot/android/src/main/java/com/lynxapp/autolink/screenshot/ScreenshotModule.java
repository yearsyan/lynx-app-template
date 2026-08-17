package com.lynxapp.autolink.screenshot;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.PixelCopy;
import android.view.View;
import android.view.Window;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.LynxView;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * View snapshots encoded into the app cache directory, exported to Lynx as
 * {@code Screenshot}. {@code capture} draws the LynxView (or the element
 * matching an idSelector) into a bitmap; {@code capturePage} copies the
 * composited Activity window through PixelCopy, so it also contains native
 * chrome outside the LynxView and needs no screenshot permission.
 */
@LynxNativeModule(name = ScreenshotModule.NAME)
public final class ScreenshotModule extends LynxContextModule {
    public static final String NAME = "Screenshot";

    private static final String FORMAT_JPEG = "jpeg";
    private static final String FORMAT_PNG = "png";
    private static final int DEFAULT_JPEG_QUALITY = 80;
    private static final int MAX_ID_SELECTOR_LENGTH = 128;
    private static final int MAX_FILE_NAME_LENGTH = 120;

    private final Context applicationContext;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    public ScreenshotModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void capture(ReadableMap options, Callback callback) {
        CaptureRequest request;
        try {
            request = parseRequest(options);
        } catch (IllegalArgumentException error) {
            callback.invoke(errorJSON(error.getMessage()));
            return;
        }
        mainHandler.post(() -> {
            try {
                LynxView lynxView = lynxView();
                if (lynxView == null) {
                    throw new IllegalStateException("LynxView is not attached yet");
                }
                View target = lynxView;
                if (request.idSelector != null) {
                    target = lynxView.findViewByIdSelector(request.idSelector);
                    if (target == null) {
                        throw new IllegalArgumentException(
                                "No view matches idSelector: " + request.idSelector);
                    }
                }
                if (target.getWidth() <= 0 || target.getHeight() <= 0) {
                    throw new IllegalStateException("Screenshot target has not been laid out yet");
                }
                Bitmap bitmap = Bitmap.createBitmap(
                        target.getWidth(), target.getHeight(), Bitmap.Config.ARGB_8888);
                Canvas canvas = new Canvas(bitmap);
                if (request.jpeg) {
                    // JPEG has no alpha channel; transparent pixels would turn black.
                    canvas.drawColor(Color.WHITE);
                }
                target.draw(canvas);
                encode(bitmap, request, callback);
            } catch (Throwable error) {
                callback.invoke(errorJSON(messageOf(error)));
            }
        });
    }

    @LynxMethod
    public void capturePage(ReadableMap options, Callback callback) {
        CaptureRequest request;
        try {
            request = parseRequest(options);
        } catch (IllegalArgumentException error) {
            callback.invoke(errorJSON(error.getMessage()));
            return;
        }
        mainHandler.post(() -> {
            try {
                Activity activity = hostActivity();
                Window window = activity == null ? null : activity.getWindow();
                if (window == null) {
                    throw new IllegalStateException("Screenshot has no Activity window");
                }
                View decor = window.getDecorView();
                if (decor.getWidth() <= 0 || decor.getHeight() <= 0) {
                    throw new IllegalStateException("Screenshot page has not been laid out yet");
                }
                Bitmap bitmap = Bitmap.createBitmap(
                        decor.getWidth(), decor.getHeight(), Bitmap.Config.ARGB_8888);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    PixelCopy.request(window, bitmap, result -> {
                        if (result == PixelCopy.SUCCESS) {
                            encode(bitmap, request, callback);
                        } else {
                            bitmap.recycle();
                            callback.invoke(errorJSON(
                                    "PixelCopy failed with error " + result));
                        }
                    }, mainHandler);
                } else {
                    Canvas canvas = new Canvas(bitmap);
                    if (request.jpeg) {
                        canvas.drawColor(Color.WHITE);
                    }
                    decor.draw(canvas);
                    encode(bitmap, request, callback);
                }
            } catch (Throwable error) {
                callback.invoke(errorJSON(messageOf(error)));
            }
        });
    }

    @Override
    public void destroy() {
        executor.shutdownNow();
    }

    private void encode(Bitmap bitmap, CaptureRequest request, Callback callback) {
        executor.execute(() -> {
            try {
                File file = cacheFile(request);
                try (FileOutputStream output = new FileOutputStream(file)) {
                    Bitmap.CompressFormat format = request.jpeg
                            ? Bitmap.CompressFormat.JPEG
                            : Bitmap.CompressFormat.PNG;
                    if (!bitmap.compress(format, request.quality, output)) {
                        throw new IOException("Unable to encode the screenshot");
                    }
                }
                callback.invoke(resultJSON(file, bitmap.getWidth(), bitmap.getHeight()));
            } catch (Throwable error) {
                callback.invoke(errorJSON(messageOf(error)));
            } finally {
                bitmap.recycle();
            }
        });
    }

    private File cacheFile(CaptureRequest request) throws IOException {
        File directory = new File(applicationContext.getCacheDir(), "LynxImages");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Unable to create the Lynx image cache");
        }
        String name = request.fileName != null
                ? request.fileName
                : "screenshot";
        return new File(directory,
                UUID.randomUUID() + "-" + name + (request.jpeg ? ".jpg" : ".png"));
    }

    @Nullable
    private LynxView lynxView() {
        return mLynxContext != null ? mLynxContext.getLynxView() : null;
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

    private static CaptureRequest parseRequest(ReadableMap options) {
        String idSelector = optionalString(options, "idSelector");
        if (idSelector != null && idSelector.length() > MAX_ID_SELECTOR_LENGTH) {
            throw new IllegalArgumentException(
                    "Screenshot idSelector is longer than " + MAX_ID_SELECTOR_LENGTH);
        }

        String format = optionalString(options, "format");
        boolean jpeg;
        if (format == null || FORMAT_PNG.equals(format)) {
            jpeg = false;
        } else if (FORMAT_JPEG.equals(format)) {
            jpeg = true;
        } else {
            throw new IllegalArgumentException("Invalid screenshot format: " + format);
        }

        int quality = options.hasKey("quality") && !options.isNull("quality")
                ? options.getInt("quality")
                : DEFAULT_JPEG_QUALITY;
        if (quality < 1 || quality > 100) {
            throw new IllegalArgumentException("Screenshot quality must be between 1 and 100");
        }

        String fileName = optionalString(options, "fileName");
        if (fileName != null) {
            fileName = sanitizeName(fileName);
        }
        return new CaptureRequest(idSelector, jpeg, quality, fileName);
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
        value = value.trim();
        return value.isEmpty() ? null : value;
    }

    private static String sanitizeName(String name) {
        String sanitized = name.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        if (sanitized.isEmpty()) {
            return "screenshot";
        }
        return sanitized.length() > MAX_FILE_NAME_LENGTH
                ? sanitized.substring(sanitized.length() - MAX_FILE_NAME_LENGTH)
                : sanitized;
    }

    private static String resultJSON(File file, int width, int height) {
        try {
            JSONObject value = new JSONObject();
            value.put("uri", Uri.fromFile(file).toString());
            value.put("width", width);
            value.put("height", height);
            JSONObject result = new JSONObject();
            result.put("value", value);
            result.put("error", "");
            return result.toString();
        } catch (JSONException error) {
            return errorJSON("Unable to encode Screenshot result");
        }
    }

    private static String errorJSON(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("value", JSONObject.NULL);
            result.put("error", message);
            return result.toString();
        } catch (JSONException ignored) {
            return "{\"value\":null,\"error\":\"Unable to encode Screenshot result\"}";
        }
    }

    private static String messageOf(Throwable error) {
        String message = error.getMessage();
        if (message == null || message.trim().isEmpty()) {
            return "Screenshot capture failed";
        }
        return message;
    }

    private static final class CaptureRequest {
        @Nullable
        final String idSelector;
        final boolean jpeg;
        final int quality;
        @Nullable
        final String fileName;

        CaptureRequest(
                @Nullable String idSelector,
                boolean jpeg,
                int quality,
                @Nullable String fileName) {
            this.idSelector = idSelector;
            this.jpeg = jpeg;
            this.quality = quality;
            this.fileName = fileName;
        }
    }
}
