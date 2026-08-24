package com.lynxapp.autolink.camera;

import android.graphics.BitmapFactory;
import android.net.Uri;

import androidx.exifinterface.media.ExifInterface;

import com.lynx.react.bridge.JavaOnlyMap;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;

/** Immutable metadata for a JPEG kept in the application's cache directory. */
final class CameraPhoto {
    private final String uri;
    private final int width;
    private final int height;
    private final long sizeBytes;

    private CameraPhoto(String uri, int width, int height, long sizeBytes) {
        this.uri = uri;
        this.width = width;
        this.height = height;
        this.sizeBytes = sizeBytes;
    }

    static CameraPhoto fromFile(File file) throws IOException {
        if (!file.isFile() || file.length() <= 0) {
            throw new IOException("The camera did not write a photo");
        }

        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeFile(file.getAbsolutePath(), bounds);
        int width = bounds.outWidth;
        int height = bounds.outHeight;
        if (width <= 0 || height <= 0) {
            throw new IOException("Unable to read the captured photo dimensions");
        }

        try {
            int orientation = new ExifInterface(file.getAbsolutePath()).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL);
            if (orientation == ExifInterface.ORIENTATION_ROTATE_90
                    || orientation == ExifInterface.ORIENTATION_ROTATE_270
                    || orientation == ExifInterface.ORIENTATION_TRANSPOSE
                    || orientation == ExifInterface.ORIENTATION_TRANSVERSE) {
                int swap = width;
                width = height;
                height = swap;
            }
        } catch (IOException ignored) {
            // Pixel bounds are still useful when a camera omits EXIF metadata.
        }

        return new CameraPhoto(Uri.fromFile(file).toString(), width, height, file.length());
    }

    JSONObject toJSON() throws JSONException {
        JSONObject result = new JSONObject();
        result.put("uri", uri);
        result.put("width", width);
        result.put("height", height);
        result.put("mimeType", "image/jpeg");
        result.put("sizeBytes", sizeBytes);
        return result;
    }

    JavaOnlyMap toMap() {
        JavaOnlyMap result = new JavaOnlyMap();
        result.putString("uri", uri);
        result.putInt("width", width);
        result.putInt("height", height);
        result.putString("mimeType", "image/jpeg");
        result.putDouble("sizeBytes", (double) sizeBytes);
        return result;
    }
}
