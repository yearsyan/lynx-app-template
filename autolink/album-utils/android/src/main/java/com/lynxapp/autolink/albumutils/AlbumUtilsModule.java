package com.lynxapp.autolink.albumutils;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;
import android.provider.OpenableColumns;
import android.webkit.MimeTypeMap;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.tasm.behavior.LynxContext;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Album image picking and saving without broad media-library access. */
@LynxNativeModule(name = AlbumUtilsModule.NAME)
public final class AlbumUtilsModule extends LynxContextModule {
    public static final String NAME = "AlbumUtils";

    private static final int BUFFER_SIZE = 16 * 1024;

    private final Context applicationContext;
    private final ExecutorService executor = Executors.newFixedThreadPool(1);

    public AlbumUtilsModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void pick(int maxSelection, Callback callback) {
        if (maxSelection < 1 || maxSelection > 50) {
            callback.invoke(PickerCallbackStore.errorJSON(
                    "Image picker maxSelection must be between 1 and 50"));
            return;
        }
        if (!PickerCallbackStore.begin(callback)) {
            callback.invoke(PickerCallbackStore.errorJSON(
                    "Another image picker request is already active"));
            return;
        }

        Context context = applicationContext;
        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                Intent intent = new Intent(context, AlbumUtilsActivity.class);
                intent.putExtra(AlbumUtilsActivity.EXTRA_MAX_SELECTION, maxSelection);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
                context.startActivity(intent);
            } catch (Throwable error) {
                PickerCallbackStore.fail(error, "Unable to open the image picker");
            }
        });
    }

    @LynxMethod
    public void saveToAlbum(String uriString, Callback callback) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            callback.invoke("Saving to the gallery requires Android 10 or later");
            return;
        }
        executor.execute(() -> {
            try {
                writeToMediaStore(parseURI(uriString));
                callback.invoke("");
            } catch (Throwable error) {
                callback.invoke(messageOf(error, "Unable to save the image to the gallery"));
            }
        });
    }

    @Override
    public void destroy() {
        executor.shutdownNow();
    }

    private Uri parseURI(String uriString) {
        if (uriString == null || uriString.trim().isEmpty()) {
            throw new IllegalArgumentException("Image URI must not be empty");
        }
        Uri uri = Uri.parse(uriString.trim());
        String scheme = uri.getScheme();
        if (!ContentResolver.SCHEME_CONTENT.equals(scheme)
                && !ContentResolver.SCHEME_FILE.equals(scheme)) {
            throw new IllegalArgumentException("AlbumUtils supports content:// and file:// URIs");
        }
        return uri;
    }

    private void writeToMediaStore(Uri source) throws IOException {
        ContentResolver resolver = applicationContext.getContentResolver();
        String name = displayName(resolver, source);
        String mimeType = resolver.getType(source);
        if (mimeType == null || mimeType.isEmpty()) {
            mimeType = mimeTypeFromName(name);
        }
        if (mimeType == null || !mimeType.startsWith("image/")) {
            throw new IOException("AlbumUtils saves image files only");
        }

        ContentValues values = new ContentValues();
        values.put(MediaStore.Images.Media.DISPLAY_NAME, name);
        values.put(MediaStore.Images.Media.MIME_TYPE, mimeType);
        values.put(MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/Lynx");
        Uri destination = resolver.insert(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values);
        if (destination == null) {
            throw new IOException("Unable to create the gallery entry");
        }

        boolean complete = false;
        try (InputStream input = openInput(resolver, source);
             OutputStream output = resolver.openOutputStream(destination)) {
            if (output == null) {
                throw new IOException("Unable to open the gallery entry");
            }
            byte[] buffer = new byte[BUFFER_SIZE];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                if (count > 0) {
                    output.write(buffer, 0, count);
                }
            }
            output.flush();
            complete = true;
        } finally {
            if (!complete) {
                //noinspection ResultOfMethodCallIgnored
                resolver.delete(destination, null, null);
            }
        }
    }

    private InputStream openInput(ContentResolver resolver, Uri uri) throws IOException {
        if (ContentResolver.SCHEME_FILE.equals(uri.getScheme())) {
            return new FileInputStream(new File(uri.getPath()));
        }
        InputStream input = resolver.openInputStream(uri);
        if (input == null) {
            throw new IOException("Unable to open the image URI");
        }
        return input;
    }

    private static String displayName(ContentResolver resolver, Uri uri) {
        try (Cursor cursor = resolver.query(
                uri,
                new String[] { OpenableColumns.DISPLAY_NAME },
                null,
                null,
                null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                    String name = cursor.getString(nameIndex);
                    if (name != null && !name.trim().isEmpty()) {
                        return sanitizeName(name);
                    }
                }
            }
        } catch (RuntimeException ignored) {
            // Providers may reject metadata queries; fall back to the path.
        }
        String segment = uri.getLastPathSegment();
        return segment == null || segment.trim().isEmpty()
                ? "image.jpg"
                : sanitizeName(segment);
    }

    private static String mimeTypeFromName(String name) {
        String extension = MimeTypeMap.getFileExtensionFromUrl(name);
        return extension == null || extension.isEmpty()
                ? null
                : MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(extension.toLowerCase(Locale.ROOT));
    }

    private static String sanitizeName(String name) {
        String sanitized = name.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]", "_").trim();
        if (sanitized.isEmpty()) {
            return "image.jpg";
        }
        return sanitized.length() > 120 ? sanitized.substring(sanitized.length() - 120) : sanitized;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
