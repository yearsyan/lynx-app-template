package com.lynxapp.autolink.filesystem;

import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.OpenableColumns;
import android.util.Base64;
import android.webkit.MimeTypeMap;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Locale;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** System file picker and URI-aware file operations exported as {@code FileSystem}. */
@LynxNativeModule(name = FileSystemModule.NAME)
public final class FileSystemModule extends LynxContextModule {
    public static final String NAME = "FileSystem";

    private static final int MAX_READ_BYTES = 20 * 1024 * 1024;
    private static final int MAX_WRITE_BYTES = 20 * 1024 * 1024;
    private static final int BUFFER_SIZE = 16 * 1024;

    private final Context applicationContext;
    private final ExecutorService executor = Executors.newFixedThreadPool(2);

    public FileSystemModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void pick(int maxSelection, Callback callback) {
        if (maxSelection < 1 || maxSelection > 50) {
            callback.invoke(PickerCallbackStore.errorJSON(
                    "File picker maxSelection must be between 1 and 50"));
            return;
        }
        if (!PickerCallbackStore.begin(callback)) {
            callback.invoke(PickerCallbackStore.errorJSON(
                    "Another file picker request is already active"));
            return;
        }

        Context context = applicationContext;
        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                Intent intent = new Intent(context, FilePickerActivity.class);
                intent.putExtra(FilePickerActivity.EXTRA_MAX_SELECTION, maxSelection);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
                context.startActivity(intent);
            } catch (Throwable error) {
                PickerCallbackStore.fail(error, "Unable to open the file picker");
            }
        });
    }

    @LynxMethod
    public void stat(String uriString, Callback callback) {
        execute(callback, () -> fileInfo(parseURI(uriString)));
    }

    @LynxMethod
    public void copyToCache(String uriString, Callback callback) {
        execute(callback, () -> copyToCache(parseURI(uriString)));
    }

    @LynxMethod
    public void readText(String uriString, int maxBytes, Callback callback) {
        execute(callback, () -> {
            byte[] bytes = readBytes(parseURI(uriString), validatedMaxBytes(maxBytes));
            try {
                return StandardCharsets.UTF_8.newDecoder()
                        .onMalformedInput(CodingErrorAction.REPORT)
                        .onUnmappableCharacter(CodingErrorAction.REPORT)
                        .decode(ByteBuffer.wrap(bytes))
                        .toString();
            } catch (CharacterCodingException error) {
                throw new IOException("File is not valid UTF-8", error);
            }
        });
    }

    @LynxMethod
    public void readBase64(String uriString, int maxBytes, Callback callback) {
        execute(callback, () -> Base64.encodeToString(
                readBytes(parseURI(uriString), validatedMaxBytes(maxBytes)),
                Base64.NO_WRAP));
    }

    @LynxMethod
    public void writeText(
            String uriString,
            String contents,
            boolean append,
            Callback callback) {
        execute(callback, () -> writeBytes(
                sandboxFile(uriString),
                contents.getBytes(StandardCharsets.UTF_8),
                append));
    }

    @LynxMethod
    public void writeBase64(
            String uriString,
            String base64,
            boolean append,
            Callback callback) {
        execute(callback, () -> writeBytes(
                sandboxFile(uriString),
                Base64.decode(base64, Base64.DEFAULT),
                append));
    }

    @LynxMethod
    public void delete(String uriString, Callback callback) {
        execute(callback, () -> {
            File target = sandboxFile(uriString);
            if (!target.exists()) {
                throw new IOException("File does not exist");
            }
            if (!deleteRecursively(target)) {
                throw new IOException("Unable to delete " + target.getName());
            }
            return JSONObject.NULL;
        });
    }

    @LynxMethod
    public void listDir(String uriString, Callback callback) {
        execute(callback, () -> listSandboxDir(sandboxFile(uriString)));
    }

    @LynxMethod
    public void cacheDir(Callback callback) {
        execute(callback, () -> Uri.fromFile(sandboxRoot()).toString());
    }

    @Override
    public void destroy() {
        executor.shutdownNow();
    }

    private void execute(Callback callback, Operation operation) {
        executor.execute(() -> {
            try {
                callback.invoke(resultJSON(operation.run(), ""));
            } catch (Throwable error) {
                callback.invoke(resultJSON(JSONObject.NULL, messageOf(error)));
            }
        });
    }

    private Uri parseURI(String uriString) {
        if (uriString == null || uriString.trim().isEmpty()) {
            throw new IllegalArgumentException("File URI must not be empty");
        }
        Uri uri = Uri.parse(uriString.trim());
        String scheme = uri.getScheme();
        if (!ContentResolver.SCHEME_CONTENT.equals(scheme)
                && !ContentResolver.SCHEME_FILE.equals(scheme)) {
            throw new IllegalArgumentException("FileSystem supports content:// and file:// URIs");
        }
        return uri;
    }

    private int validatedMaxBytes(int maxBytes) {
        if (maxBytes < 1 || maxBytes > MAX_READ_BYTES) {
            throw new IllegalArgumentException(
                    "File maxBytes must be between 1 and " + MAX_READ_BYTES);
        }
        return maxBytes;
    }

    private JSONObject fileInfo(Uri uri) throws Exception {
        String name = null;
        String mimeType = null;
        Long size = null;

        if (ContentResolver.SCHEME_FILE.equals(uri.getScheme())) {
            File file = fileForURI(uri);
            name = file.getName();
            size = file.length();
            mimeType = mimeTypeFromName(name);
        } else {
            ContentResolver resolver = applicationContext.getContentResolver();
            try (Cursor cursor = resolver.query(
                    uri,
                    new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE },
                    null,
                    null,
                    null)) {
                if (cursor != null && cursor.moveToFirst()) {
                    int nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                    int sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE);
                    if (nameIndex >= 0 && !cursor.isNull(nameIndex)) {
                        name = cursor.getString(nameIndex);
                    }
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) {
                        long value = cursor.getLong(sizeIndex);
                        if (value >= 0) {
                            size = value;
                        }
                    }
                }
            }
            mimeType = resolver.getType(uri);
        }

        if (name == null || name.trim().isEmpty()) {
            name = uri.getLastPathSegment();
        }
        if (name == null || name.trim().isEmpty()) {
            name = "file";
        }
        if (mimeType == null || mimeType.isEmpty()) {
            mimeType = mimeTypeFromName(name);
        }

        JSONObject info = new JSONObject();
        info.put("uri", uri.toString());
        info.put("name", name);
        info.put("mimeType", mimeType == null ? JSONObject.NULL : mimeType);
        info.put("size", size == null ? JSONObject.NULL : size);
        return info;
    }

    private String copyToCache(Uri uri) throws Exception {
        JSONObject info = fileInfo(uri);
        String name = sanitizeName(info.optString("name", "file"));
        File destination = new File(sandboxRoot(), UUID.randomUUID() + "-" + name);
        boolean complete = false;
        try (InputStream input = openInput(uri);
             OutputStream output = new FileOutputStream(destination)) {
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
                destination.delete();
            }
        }
        return Uri.fromFile(destination).toString();
    }

    /** Returns the app-private cache sandbox, creating it on demand. */
    private File sandboxRoot() throws IOException {
        File directory = new File(applicationContext.getCacheDir(), "LynxFiles");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Unable to create the Lynx file cache");
        }
        return directory;
    }

    /**
     * Resolves a sandbox-relative path or an in-sandbox {@code file://} URI,
     * rejecting anything that canonicalizes outside the sandbox.
     */
    private File sandboxFile(String uriString) throws IOException {
        if (uriString == null || uriString.trim().isEmpty()) {
            throw new IllegalArgumentException("File URI must not be empty");
        }
        String input = uriString.trim();
        File root = sandboxRoot();
        String rootCanonical = root.getCanonicalPath();

        File candidate;
        if (input.indexOf("://") < 0) {
            candidate = new File(root, input);
        } else {
            Uri uri = Uri.parse(input);
            if (!ContentResolver.SCHEME_FILE.equals(uri.getScheme())) {
                throw new IllegalArgumentException(
                        "Cache sandbox supports file:// URIs and relative paths");
            }
            String path = uri.getPath();
            if (path == null || path.isEmpty()) {
                throw new IOException("Invalid file URI");
            }
            candidate = new File(path);
        }

        String canonical = candidate.getCanonicalPath();
        if (!canonical.equals(rootCanonical)
                && !canonical.startsWith(rootCanonical + File.separator)) {
            throw new IllegalArgumentException("Path escapes the cache sandbox");
        }
        return new File(canonical);
    }

    private String writeBytes(File target, byte[] bytes, boolean append)
            throws IOException {
        if (bytes.length > MAX_WRITE_BYTES) {
            throw new IllegalArgumentException(
                    "File contents must not exceed " + MAX_WRITE_BYTES + " bytes");
        }
        File parent = target.getParentFile();
        if (parent == null || (!parent.isDirectory() && !parent.mkdirs())) {
            throw new IOException("Unable to create the target directory");
        }
        try (OutputStream output = new FileOutputStream(target, append)) {
            output.write(bytes);
            output.flush();
        }
        return Uri.fromFile(target).toString();
    }

    private static boolean deleteRecursively(File file) {
        File[] children = file.isDirectory() ? file.listFiles() : null;
        if (children != null) {
            for (File child : children) {
                if (!deleteRecursively(child)) {
                    return false;
                }
            }
        }
        return file.delete();
    }

    private JSONArray listSandboxDir(File directory) throws Exception {
        if (!directory.isDirectory()) {
            throw new IOException("Path is not a directory");
        }
        File[] children = directory.listFiles();
        if (children == null) {
            throw new IOException("Unable to list the directory");
        }
        Arrays.sort(children, (left, right) ->
                left.getName().compareToIgnoreCase(right.getName()));
        JSONArray entries = new JSONArray();
        for (File child : children) {
            JSONObject entry = new JSONObject();
            entry.put("name", child.getName());
            entry.put("uri", Uri.fromFile(child).toString());
            entry.put("isDirectory", child.isDirectory());
            entry.put("size", child.isDirectory() ? JSONObject.NULL : child.length());
            entries.put(entry);
        }
        return entries;
    }

    private byte[] readBytes(Uri uri, int maxBytes) throws IOException {
        try (InputStream input = openInput(uri);
             ByteArrayOutputStream output = new ByteArrayOutputStream(
                     Math.min(maxBytes, BUFFER_SIZE))) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int total = 0;
            int count;
            while ((count = input.read(buffer)) >= 0) {
                if (count == 0) {
                    continue;
                }
                total += count;
                if (total > maxBytes) {
                    throw new IOException("File exceeds maxBytes (" + maxBytes + ")");
                }
                output.write(buffer, 0, count);
            }
            return output.toByteArray();
        }
    }

    private InputStream openInput(Uri uri) throws IOException {
        if (ContentResolver.SCHEME_FILE.equals(uri.getScheme())) {
            return new FileInputStream(fileForURI(uri));
        }
        InputStream input = applicationContext.getContentResolver().openInputStream(uri);
        if (input == null) {
            throw new IOException("Unable to open the file URI");
        }
        return input;
    }

    private File fileForURI(Uri uri) throws IOException {
        String path = uri.getPath();
        if (path == null || path.isEmpty()) {
            throw new IOException("Invalid file URI");
        }
        File file = new File(path);
        if (!file.isFile()) {
            throw new IOException("File does not exist or is not a regular file");
        }
        return file;
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
            return "file";
        }
        return sanitized.length() > 120 ? sanitized.substring(sanitized.length() - 120) : sanitized;
    }

    private static String resultJSON(Object value, String error) {
        try {
            JSONObject result = new JSONObject();
            result.put("value", value == null ? JSONObject.NULL : value);
            result.put("error", error == null ? "" : error);
            return result.toString();
        } catch (Throwable encodingError) {
            return "{\"value\":null,\"error\":\"Unable to encode FileSystem result\"}";
        }
    }

    private static String messageOf(Throwable error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? "FileSystem operation failed"
                : message;
    }

    private interface Operation {
        Object run() throws Exception;
    }
}
