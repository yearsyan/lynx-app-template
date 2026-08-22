package com.lynxapp.autolink.imagetooling;

import android.content.ContentResolver;
import android.content.Context;
import android.database.Cursor;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.net.Uri;
import android.provider.OpenableColumns;

import androidx.annotation.Nullable;
import androidx.exifinterface.media.ExifInterface;

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
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native image metadata, crop/composition, encoding and EXIF tools. */
@LynxNativeModule(name = ImageToolingModule.NAME)
public final class ImageToolingModule extends LynxContextModule {
    public static final String NAME = "ImageTooling";

    private static final String CACHE_DIRECTORY = "LynxImages";
    private static final int MAX_PIXELS = 50_000_000;
    private static final int MAX_DIMENSION = 16_384;
    private static final int MAX_IMAGES = 16;

    private static final String[] EXIF_TAGS = {
        ExifInterface.TAG_ORIENTATION,
        ExifInterface.TAG_IMAGE_DESCRIPTION,
        ExifInterface.TAG_MAKE,
        ExifInterface.TAG_MODEL,
        ExifInterface.TAG_SOFTWARE,
        ExifInterface.TAG_ARTIST,
        ExifInterface.TAG_COPYRIGHT,
        ExifInterface.TAG_DATETIME,
        ExifInterface.TAG_DATETIME_ORIGINAL,
        ExifInterface.TAG_OFFSET_TIME_ORIGINAL,
        ExifInterface.TAG_USER_COMMENT,
        ExifInterface.TAG_EXPOSURE_TIME,
        ExifInterface.TAG_F_NUMBER,
        ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY,
        ExifInterface.TAG_FOCAL_LENGTH,
        ExifInterface.TAG_LENS_MAKE,
        ExifInterface.TAG_LENS_MODEL,
    };

    // String names keep this exhaustive list compatible across ExifInterface
    // versions while setAttribute still validates the actual format support.
    private static final String[] GPS_TAGS = {
        "GPSVersionID", "GPSLatitudeRef", "GPSLatitude", "GPSLongitudeRef",
        "GPSLongitude", "GPSAltitudeRef", "GPSAltitude", "GPSTimeStamp",
        "GPSSatellites", "GPSStatus", "GPSMeasureMode", "GPSDOP",
        "GPSSpeedRef", "GPSSpeed", "GPSTrackRef", "GPSTrack",
        "GPSImgDirectionRef", "GPSImgDirection", "GPSMapDatum",
        "GPSDestLatitudeRef", "GPSDestLatitude", "GPSDestLongitudeRef",
        "GPSDestLongitude", "GPSDestBearingRef", "GPSDestBearing",
        "GPSDestDistanceRef", "GPSDestDistance", "GPSProcessingMethod",
        "GPSAreaInformation", "GPSDateStamp", "GPSDifferential",
        "GPSHPositioningError"
    };

    private static final Set<String> WRITABLE_EXIF_TAGS = new HashSet<>();

    static {
        for (String tag : EXIF_TAGS) {
            WRITABLE_EXIF_TAGS.add(tag);
        }
    }

    private final ExecutorService executor = Executors.newCachedThreadPool();

    public ImageToolingModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void info(String uriString, Callback callback) {
        run(callback, context -> valueResult(readInfo(context, uriString)));
    }

    @LynxMethod
    public void compress(ReadableMap options, Callback callback) {
        run(callback, context -> valueResult(compressImage(context, EncodingRequest.parse(options))));
    }

    @LynxMethod
    public void crop(ReadableMap options, Callback callback) {
        run(callback, context -> valueResult(cropImage(context, CropRequest.parse(options))));
    }

    @LynxMethod
    public void compose(ReadableMap options, Callback callback) {
        run(callback, context -> valueResult(composeImages(context, ComposeRequest.parse(options))));
    }

    @LynxMethod
    public void readExif(String uriString, Callback callback) {
        run(callback, context -> valueResult(readExifValue(context, uriString)));
    }

    @LynxMethod
    public void writeExif(ReadableMap options, Callback callback) {
        run(callback, context -> valueResult(writeExifCopy(context, options)));
    }

    @LynxMethod
    public void removeExif(ReadableMap options, Callback callback) {
        run(callback, context -> valueResult(removeExifImage(context, RemoveExifRequest.parse(options))));
    }

    @Override
    public void destroy() {
        executor.shutdown();
    }

    private interface NativeWork {
        String execute(Context context) throws Exception;
    }

    private void run(Callback callback, NativeWork work) {
        Context context = applicationContext();
        if (context == null) {
            callback.invoke(errorResult("ImageTooling has no application context"));
            return;
        }
        executor.execute(() -> {
            try {
                callback.invoke(work.execute(context));
            } catch (IllegalArgumentException failure) {
                callback.invoke(errorResult(messageOf(failure, "Invalid ImageTooling request")));
            } catch (OutOfMemoryError failure) {
                callback.invoke(errorResult("ImageTooling ran out of memory decoding the image"));
            } catch (Exception failure) {
                callback.invoke(errorResult(messageOf(failure, "ImageTooling operation failed")));
            }
        });
    }

    private static class EncodingRequest {
        final String uri;
        final Integer maxWidth;
        final Integer maxHeight;
        final int quality;
        final boolean jpeg;

        EncodingRequest(
                String uri, Integer maxWidth, Integer maxHeight, int quality, boolean jpeg) {
            this.uri = uri;
            this.maxWidth = maxWidth;
            this.maxHeight = maxHeight;
            this.quality = quality;
            this.jpeg = jpeg;
        }

        static EncodingRequest parse(ReadableMap options) {
            requireOptions(options, "compress");
            return new EncodingRequest(
                    requireURI(options, "uri"),
                    optionalPositiveInt(options, "maxWidth"),
                    optionalPositiveInt(options, "maxHeight"),
                    positiveInt(options, "quality", 80),
                    parseJPEG(options.getString("format"), true));
        }
    }

    private static final class CropRequest extends EncodingRequest {
        final int x;
        final int y;
        final int width;
        final int height;

        CropRequest(
                String uri, int x, int y, int width, int height,
                Integer maxWidth, Integer maxHeight, int quality, boolean jpeg) {
            super(uri, maxWidth, maxHeight, quality, jpeg);
            this.x = x;
            this.y = y;
            this.width = width;
            this.height = height;
        }

        static CropRequest parse(ReadableMap options) {
            requireOptions(options, "crop");
            return new CropRequest(
                    requireURI(options, "uri"),
                    nonNegativeInt(options, "x"),
                    nonNegativeInt(options, "y"),
                    positiveInt(options, "width", -1),
                    positiveInt(options, "height", -1),
                    optionalPositiveInt(options, "maxWidth"),
                    optionalPositiveInt(options, "maxHeight"),
                    positiveInt(options, "quality", 80),
                    parseJPEG(options.getString("format"), true));
        }
    }

    private static final class ComposeLayer {
        final String uri;
        final int x;
        final int y;
        final double opacity;

        ComposeLayer(String uri, int x, int y, double opacity) {
            this.uri = uri;
            this.x = x;
            this.y = y;
            this.opacity = opacity;
        }
    }

    private static final class ComposeRequest {
        final List<ComposeLayer> layers;
        final String layout;
        final int spacing;
        final Integer maxWidth;
        final Integer maxHeight;
        final int quality;
        final boolean jpeg;

        ComposeRequest(
                List<ComposeLayer> layers, String layout, int spacing,
                Integer maxWidth, Integer maxHeight, int quality, boolean jpeg) {
            this.layers = layers;
            this.layout = layout;
            this.spacing = spacing;
            this.maxWidth = maxWidth;
            this.maxHeight = maxHeight;
            this.quality = quality;
            this.jpeg = jpeg;
        }

        static ComposeRequest parse(ReadableMap options) {
            requireOptions(options, "compose");
            ReadableArray images = options.getArray("images");
            if (images == null || images.size() < 1 || images.size() > MAX_IMAGES) {
                throw new IllegalArgumentException(
                        "ImageTooling compose requires 1-" + MAX_IMAGES + " images");
            }
            List<ComposeLayer> layers = new ArrayList<>();
            for (int index = 0; index < images.size(); index++) {
                ReadableMap image = images.getMap(index);
                if (image == null) {
                    throw new IllegalArgumentException("Invalid ImageTooling compose image");
                }
                double opacity = image.hasKey("opacity") && !image.isNull("opacity")
                        ? image.getDouble("opacity") : 1.0;
                if (!Double.isFinite(opacity) || opacity < 0.0 || opacity > 1.0) {
                    throw new IllegalArgumentException("Invalid ImageTooling layer opacity");
                }
                layers.add(new ComposeLayer(
                        requireURI(image, "uri"),
                        nonNegativeInt(image, "x"),
                        nonNegativeInt(image, "y"),
                        opacity));
            }
            String layout = options.getString("layout");
            if (!"horizontal".equals(layout)
                    && !"vertical".equals(layout)
                    && !"overlay".equals(layout)) {
                throw new IllegalArgumentException("Invalid ImageTooling compose layout");
            }
            return new ComposeRequest(
                    layers,
                    layout,
                    nonNegativeInt(options, "spacing"),
                    optionalPositiveInt(options, "maxWidth"),
                    optionalPositiveInt(options, "maxHeight"),
                    positiveInt(options, "quality", 80),
                    parseJPEG(options.getString("format"), true));
        }
    }

    private static final class RemoveExifRequest {
        final String uri;
        final int quality;
        @Nullable final Boolean jpeg;

        RemoveExifRequest(String uri, int quality, @Nullable Boolean jpeg) {
            this.uri = uri;
            this.quality = quality;
            this.jpeg = jpeg;
        }

        static RemoveExifRequest parse(ReadableMap options) {
            requireOptions(options, "removeExif");
            String format = options.getString("format");
            return new RemoveExifRequest(
                    requireURI(options, "uri"),
                    positiveInt(options, "quality", 100),
                    format == null ? null : parseJPEG(format, false));
        }
    }

    private static final class SourceInfo {
        final Uri uri;
        final int rawWidth;
        final int rawHeight;
        final int displayWidth;
        final int displayHeight;
        final int orientation;
        @Nullable final String mimeType;
        final long sizeBytes;

        SourceInfo(
                Uri uri, int rawWidth, int rawHeight, int orientation,
                @Nullable String mimeType, long sizeBytes) {
            this.uri = uri;
            this.rawWidth = rawWidth;
            this.rawHeight = rawHeight;
            this.orientation = orientation;
            boolean quarterTurn = isQuarterTurn(orientation);
            this.displayWidth = quarterTurn ? rawHeight : rawWidth;
            this.displayHeight = quarterTurn ? rawWidth : rawHeight;
            this.mimeType = mimeType;
            this.sizeBytes = sizeBytes;
        }
    }

    private static String readInfo(Context context, String uriString) throws IOException {
        SourceInfo info = readSourceInfo(context, uriString);
        JSONObject value = new JSONObject();
        put(value, "width", info.displayWidth);
        put(value, "height", info.displayHeight);
        put(value, "mimeType", info.mimeType != null ? info.mimeType : JSONObject.NULL);
        put(value, "sizeBytes", info.sizeBytes >= 0 ? info.sizeBytes : JSONObject.NULL);
        return value.toString();
    }

    private static SourceInfo readSourceInfo(Context context, String uriString) throws IOException {
        Uri uri = parseImageUri(uriString);
        ContentResolver resolver = context.getContentResolver();
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        try (InputStream input = resolver.openInputStream(uri)) {
            if (input == null) {
                throw new IllegalArgumentException("ImageTooling cannot open the image URI");
            }
            BitmapFactory.decodeStream(input, null, bounds);
        }
        if (bounds.outWidth < 1 || bounds.outHeight < 1) {
            throw new IllegalArgumentException("ImageTooling cannot decode the image dimensions");
        }
        int orientation = ExifInterface.ORIENTATION_NORMAL;
        try (InputStream input = resolver.openInputStream(uri)) {
            if (input != null) {
                orientation = new ExifInterface(input).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
            }
        }
        String mimeType = resolver.getType(uri);
        if (mimeType == null) {
            mimeType = bounds.outMimeType;
        }
        return new SourceInfo(
                uri, bounds.outWidth, bounds.outHeight, orientation, mimeType,
                sizeOf(context, uri));
    }

    private static JSONObject compressImage(Context context, EncodingRequest request)
            throws IOException {
        SourceInfo source = readSourceInfo(context, request.uri);
        validateSource(source);
        double scale = fitScale(
                source.displayWidth, source.displayHeight, request.maxWidth, request.maxHeight);
        int width = scaled(source.displayWidth, scale);
        int height = scaled(source.displayHeight, scale);
        validateOutput(width, height);
        Bitmap bitmap = decodeUpright(context, source, width, height);
        try {
            return writeBitmap(context, bitmap, request.jpeg, request.quality, "compressed");
        } finally {
            recycle(bitmap);
        }
    }

    private static JSONObject cropImage(Context context, CropRequest request) throws IOException {
        SourceInfo source = readSourceInfo(context, request.uri);
        validateSource(source);
        if ((long) request.x + request.width > source.displayWidth
                || (long) request.y + request.height > source.displayHeight) {
            throw new IllegalArgumentException(
                    "ImageTooling crop rectangle is outside the oriented image bounds");
        }
        double scale = fitScale(
                request.width, request.height, request.maxWidth, request.maxHeight);
        int outputWidth = scaled(request.width, scale);
        int outputHeight = scaled(request.height, scale);
        validateOutput(outputWidth, outputHeight);
        int fullWidth = scaled(source.displayWidth, scale);
        int fullHeight = scaled(source.displayHeight, scale);
        Bitmap upright = decodeUpright(context, source, fullWidth, fullHeight);
        Bitmap cropped = null;
        try {
            int left = Math.min(
                    Math.max(0, (int) Math.round(request.x * scale)),
                    Math.max(0, upright.getWidth() - outputWidth));
            int top = Math.min(
                    Math.max(0, (int) Math.round(request.y * scale)),
                    Math.max(0, upright.getHeight() - outputHeight));
            cropped = Bitmap.createBitmap(upright, left, top, outputWidth, outputHeight);
            return writeBitmap(context, cropped, request.jpeg, request.quality, "cropped");
        } finally {
            recycle(upright, cropped);
        }
    }

    private static JSONObject composeImages(Context context, ComposeRequest request)
            throws IOException {
        List<SourceInfo> sources = new ArrayList<>();
        long rawWidth = 0;
        long rawHeight = 0;
        for (int index = 0; index < request.layers.size(); index++) {
            ComposeLayer layer = request.layers.get(index);
            SourceInfo source = readSourceInfo(context, layer.uri);
            validateSource(source);
            sources.add(source);
            if ("horizontal".equals(request.layout)) {
                rawWidth += source.displayWidth;
                rawHeight = Math.max(rawHeight, source.displayHeight);
            } else if ("vertical".equals(request.layout)) {
                rawWidth = Math.max(rawWidth, source.displayWidth);
                rawHeight += source.displayHeight;
            } else {
                rawWidth = Math.max(rawWidth, (long) layer.x + source.displayWidth);
                rawHeight = Math.max(rawHeight, (long) layer.y + source.displayHeight);
            }
        }
        if (!"overlay".equals(request.layout)) {
            long gaps = (long) request.spacing * (request.layers.size() - 1);
            if ("horizontal".equals(request.layout)) {
                rawWidth += gaps;
            } else {
                rawHeight += gaps;
            }
        }
        if (rawWidth < 1 || rawHeight < 1
                || rawWidth > Integer.MAX_VALUE || rawHeight > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("ImageTooling composition dimensions are invalid");
        }
        double scale = fitScale(
                (int) rawWidth, (int) rawHeight, request.maxWidth, request.maxHeight);
        int outputWidth = scaled((int) rawWidth, scale);
        int outputHeight = scaled((int) rawHeight, scale);
        validateOutput(outputWidth, outputHeight);

        Bitmap canvasBitmap = Bitmap.createBitmap(outputWidth, outputHeight, Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(canvasBitmap);
        if (request.jpeg) {
            canvas.drawColor(0xFFFFFFFF);
        }
        Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        long cursor = 0;
        try {
            for (int index = 0; index < sources.size(); index++) {
                SourceInfo source = sources.get(index);
                ComposeLayer layer = request.layers.get(index);
                int layerWidth = scaled(source.displayWidth, scale);
                int layerHeight = scaled(source.displayHeight, scale);
                Bitmap bitmap = decodeUpright(context, source, layerWidth, layerHeight);
                try {
                    int left;
                    int top;
                    if ("horizontal".equals(request.layout)) {
                        left = (int) Math.round(cursor * scale);
                        top = 0;
                        cursor += source.displayWidth + request.spacing;
                    } else if ("vertical".equals(request.layout)) {
                        left = 0;
                        top = (int) Math.round(cursor * scale);
                        cursor += source.displayHeight + request.spacing;
                    } else {
                        left = (int) Math.round(layer.x * scale);
                        top = (int) Math.round(layer.y * scale);
                    }
                    paint.setAlpha((int) Math.round(layer.opacity * 255.0));
                    canvas.drawBitmap(bitmap, left, top, paint);
                } finally {
                    recycle(bitmap);
                }
            }
            return writeBitmap(
                    context, canvasBitmap, request.jpeg, request.quality, "composed");
        } finally {
            recycle(canvasBitmap);
        }
    }

    private static Bitmap decodeUpright(
            Context context, SourceInfo source, int targetWidth, int targetHeight)
            throws IOException {
        BitmapFactory.Options decode = new BitmapFactory.Options();
        decode.inSampleSize = 1;
        boolean quarterTurn = isQuarterTurn(source.orientation);
        int targetRawWidth = quarterTurn ? targetHeight : targetWidth;
        int targetRawHeight = quarterTurn ? targetWidth : targetHeight;
        while (source.rawWidth / (decode.inSampleSize * 2) >= targetRawWidth
                && source.rawHeight / (decode.inSampleSize * 2) >= targetRawHeight) {
            decode.inSampleSize *= 2;
        }
        Bitmap decoded;
        try (InputStream input = context.getContentResolver().openInputStream(source.uri)) {
            if (input == null) {
                throw new IllegalArgumentException("ImageTooling cannot open the image URI");
            }
            decoded = BitmapFactory.decodeStream(input, null, decode);
        }
        if (decoded == null) {
            throw new IllegalArgumentException("ImageTooling cannot decode the image");
        }
        Matrix matrix = orientationMatrix(source.orientation);
        Bitmap oriented = matrix.isIdentity()
                ? decoded
                : Bitmap.createBitmap(
                        decoded, 0, 0, decoded.getWidth(), decoded.getHeight(), matrix, true);
        Bitmap fitted = oriented.getWidth() == targetWidth && oriented.getHeight() == targetHeight
                ? oriented
                : Bitmap.createScaledBitmap(oriented, targetWidth, targetHeight, true);
        if (decoded != fitted) {
            recycle(decoded);
        }
        if (oriented != decoded && oriented != fitted) {
            recycle(oriented);
        }
        return fitted;
    }

    private static Matrix orientationMatrix(int orientation) {
        Matrix matrix = new Matrix();
        switch (orientation) {
            case ExifInterface.ORIENTATION_FLIP_HORIZONTAL:
                matrix.setScale(-1f, 1f);
                break;
            case ExifInterface.ORIENTATION_ROTATE_180:
                matrix.setRotate(180f);
                break;
            case ExifInterface.ORIENTATION_FLIP_VERTICAL:
                matrix.setRotate(180f);
                matrix.postScale(-1f, 1f);
                break;
            case ExifInterface.ORIENTATION_TRANSPOSE:
                matrix.setRotate(90f);
                matrix.postScale(-1f, 1f);
                break;
            case ExifInterface.ORIENTATION_ROTATE_90:
                matrix.setRotate(90f);
                break;
            case ExifInterface.ORIENTATION_TRANSVERSE:
                matrix.setRotate(-90f);
                matrix.postScale(-1f, 1f);
                break;
            case ExifInterface.ORIENTATION_ROTATE_270:
                matrix.setRotate(-90f);
                break;
            default:
                break;
        }
        return matrix;
    }

    private static JSONObject writeBitmap(
            Context context, Bitmap bitmap, boolean jpeg, int quality, String suffix)
            throws IOException {
        File directory = cacheDirectory(context);
        String extension = jpeg ? "jpg" : "png";
        File destination = new File(
                directory, UUID.randomUUID() + "-" + suffix + "." + extension);
        Bitmap output = bitmap;
        if (jpeg && bitmap.hasAlpha()) {
            output = Bitmap.createBitmap(bitmap.getWidth(), bitmap.getHeight(), Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(output);
            canvas.drawColor(0xFFFFFFFF);
            canvas.drawBitmap(bitmap, 0f, 0f, null);
        }
        try (FileOutputStream stream = new FileOutputStream(destination)) {
            Bitmap.CompressFormat format = jpeg
                    ? Bitmap.CompressFormat.JPEG : Bitmap.CompressFormat.PNG;
            if (!output.compress(format, quality, stream)) {
                throw new IOException("ImageTooling encoder failed");
            }
        } finally {
            if (output != bitmap) {
                recycle(output);
            }
        }
        return outputValue(destination, bitmap.getWidth(), bitmap.getHeight());
    }

    private static JSONObject readExifValue(Context context, String uriString) throws IOException {
        Uri uri = parseImageUri(uriString);
        ExifInterface exif;
        try (InputStream input = context.getContentResolver().openInputStream(uri)) {
            if (input == null) {
                throw new IllegalArgumentException("ImageTooling cannot open the image URI");
            }
            exif = new ExifInterface(input);
        }
        JSONObject tags = new JSONObject();
        for (String tag : EXIF_TAGS) {
            String value = exif.getAttribute(tag);
            if (value != null) {
                put(tags, canonicalTag(tag), value);
            }
        }
        JSONObject value = new JSONObject();
        put(value, "tags", tags);
        float[] coordinates = new float[2];
        if (exif.getLatLong(coordinates)) {
            JSONObject gps = new JSONObject();
            put(gps, "latitude", coordinates[0]);
            put(gps, "longitude", coordinates[1]);
            double altitude = exif.getAltitude(Double.NaN);
            if (!Double.isNaN(altitude)) {
                put(gps, "altitude", altitude);
            }
            put(value, "gps", gps);
        } else {
            put(value, "gps", JSONObject.NULL);
        }
        return value;
    }

    private static JSONObject writeExifCopy(Context context, ReadableMap options) throws IOException {
        requireOptions(options, "writeExif");
        String uriString = requireURI(options, "uri");
        SourceInfo source = readSourceInfo(context, uriString);
        File destination = new File(
                cacheDirectory(context),
                UUID.randomUUID() + "-exif." + extensionOf(source));
        try (InputStream input = context.getContentResolver().openInputStream(source.uri);
                FileOutputStream output = new FileOutputStream(destination)) {
            if (input == null) {
                throw new IllegalArgumentException("ImageTooling cannot open the image URI");
            }
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                output.write(buffer, 0, count);
            }
        }

        ExifInterface exif = new ExifInterface(destination);
        ReadableMap tags = options.getMap("tags");
        if (tags != null) {
            for (Map.Entry<String, Object> entry : tags.toHashMap().entrySet()) {
                String tag = nativeTag(entry.getKey());
                if (!WRITABLE_EXIF_TAGS.contains(tag)) {
                    throw new IllegalArgumentException(
                            "Unsupported ImageTooling EXIF tag: " + entry.getKey());
                }
                Object tagValue = entry.getValue();
                exif.setAttribute(tag, tagValue == null ? null : tagValue.toString());
            }
        }
        if (options.hasKey("gps")) {
            if (options.isNull("gps")) {
                clearGPS(exif);
            } else {
                ReadableMap gps = options.getMap("gps");
                if (gps == null) {
                    throw new IllegalArgumentException("Invalid ImageTooling GPS update");
                }
                double latitude = gps.getDouble("latitude");
                double longitude = gps.getDouble("longitude");
                exif.setLatLong(latitude, longitude);
                if (gps.hasKey("altitude")) {
                    if (gps.isNull("altitude")) {
                        exif.setAttribute(ExifInterface.TAG_GPS_ALTITUDE, null);
                        exif.setAttribute(ExifInterface.TAG_GPS_ALTITUDE_REF, null);
                    } else {
                        exif.setAltitude(gps.getDouble("altitude"));
                    }
                }
            }
        }
        exif.saveAttributes();
        SourceInfo result = readSourceInfo(context, Uri.fromFile(destination).toString());
        return outputValue(destination, result.displayWidth, result.displayHeight);
    }

    private static JSONObject removeExifImage(Context context, RemoveExifRequest request)
            throws IOException {
        SourceInfo source = readSourceInfo(context, request.uri);
        validateSource(source);
        boolean jpeg = request.jpeg != null
                ? request.jpeg
                : !"image/png".equalsIgnoreCase(source.mimeType);
        validateOutput(source.displayWidth, source.displayHeight);
        Bitmap bitmap = decodeUpright(
                context, source, source.displayWidth, source.displayHeight);
        try {
            return writeBitmap(context, bitmap, jpeg, request.quality, "exif-removed");
        } finally {
            recycle(bitmap);
        }
    }

    private static void clearGPS(ExifInterface exif) {
        for (String tag : GPS_TAGS) {
            exif.setAttribute(tag, null);
        }
    }

    private static String canonicalTag(String nativeTag) {
        if (ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY.equals(nativeTag)) {
            return "ISOSpeedRatings";
        }
        return nativeTag;
    }

    private static String nativeTag(String canonicalTag) {
        if ("ISOSpeedRatings".equals(canonicalTag)) {
            return ExifInterface.TAG_PHOTOGRAPHIC_SENSITIVITY;
        }
        return canonicalTag;
    }

    private static JSONObject outputValue(File file, int width, int height) {
        JSONObject value = new JSONObject();
        put(value, "uri", Uri.fromFile(file).toString());
        put(value, "width", width);
        put(value, "height", height);
        put(value, "sizeBytes", file.length());
        return value;
    }

    private static File cacheDirectory(Context context) throws IOException {
        File directory = new File(context.getCacheDir(), CACHE_DIRECTORY);
        if (!directory.exists() && !directory.mkdirs()) {
            throw new IOException("ImageTooling cannot create the cache directory");
        }
        return directory;
    }

    private static void validateSource(SourceInfo source) {
        if ((long) source.rawWidth * source.rawHeight > MAX_PIXELS) {
            throw new IllegalArgumentException("ImageTooling image is larger than 50 MP");
        }
    }

    private static void validateOutput(int width, int height) {
        if (width < 1 || height < 1 || width > MAX_DIMENSION || height > MAX_DIMENSION) {
            throw new IllegalArgumentException(
                    "ImageTooling output dimensions must not exceed " + MAX_DIMENSION);
        }
        if ((long) width * height > MAX_PIXELS) {
            throw new IllegalArgumentException("ImageTooling output is larger than 50 MP");
        }
    }

    private static double fitScale(
            int width, int height, @Nullable Integer maxWidth, @Nullable Integer maxHeight) {
        double scale = 1.0;
        if (maxWidth != null && width > maxWidth) {
            scale = Math.min(scale, maxWidth / (double) width);
        }
        if (maxHeight != null && height > maxHeight) {
            scale = Math.min(scale, maxHeight / (double) height);
        }
        return scale;
    }

    private static int scaled(int value, double scale) {
        return Math.max(1, (int) Math.round(value * scale));
    }

    private static boolean isQuarterTurn(int orientation) {
        return orientation == ExifInterface.ORIENTATION_ROTATE_90
                || orientation == ExifInterface.ORIENTATION_ROTATE_270
                || orientation == ExifInterface.ORIENTATION_TRANSPOSE
                || orientation == ExifInterface.ORIENTATION_TRANSVERSE;
    }

    private static void recycle(Bitmap... bitmaps) {
        Set<Bitmap> seen = new HashSet<>();
        for (Bitmap bitmap : bitmaps) {
            if (bitmap != null && seen.add(bitmap) && !bitmap.isRecycled()) {
                bitmap.recycle();
            }
        }
    }

    private static void requireOptions(@Nullable ReadableMap options, String action) {
        if (options == null) {
            throw new IllegalArgumentException(
                    "ImageTooling " + action + " requires options");
        }
    }

    private static String requireURI(ReadableMap options, String key) {
        String value = options.getString(key);
        if (value == null || value.trim().isEmpty()) {
            throw new IllegalArgumentException("ImageTooling requires a non-empty image URI");
        }
        return value.trim();
    }

    private static int positiveInt(ReadableMap options, String key, int fallback) {
        int value = options.hasKey(key) && !options.isNull(key)
                ? options.getInt(key) : fallback;
        if (value < 1) {
            throw new IllegalArgumentException("ImageTooling " + key + " must be positive");
        }
        return value;
    }

    private static int nonNegativeInt(ReadableMap options, String key) {
        int value = options.hasKey(key) && !options.isNull(key) ? options.getInt(key) : 0;
        if (value < 0) {
            throw new IllegalArgumentException(
                    "ImageTooling " + key + " must not be negative");
        }
        return value;
    }

    @Nullable
    private static Integer optionalPositiveInt(ReadableMap options, String key) {
        if (!options.hasKey(key) || options.isNull(key)) {
            return null;
        }
        int value = options.getInt(key);
        if (value < 1) {
            throw new IllegalArgumentException("ImageTooling " + key + " must be positive");
        }
        return value;
    }

    private static boolean parseJPEG(@Nullable String format, boolean defaultJPEG) {
        if (format == null) {
            return defaultJPEG;
        }
        if ("jpeg".equals(format)) {
            return true;
        }
        if ("png".equals(format)) {
            return false;
        }
        throw new IllegalArgumentException("Invalid ImageTooling format: " + format);
    }

    private static Uri parseImageUri(String uriString) {
        if (uriString == null || uriString.trim().isEmpty()) {
            throw new IllegalArgumentException("ImageTooling requires a non-empty image URI");
        }
        Uri uri = Uri.parse(uriString.trim());
        String scheme = uri.getScheme();
        if (!ContentResolver.SCHEME_CONTENT.equals(scheme)
                && !ContentResolver.SCHEME_FILE.equals(scheme)) {
            throw new IllegalArgumentException(
                    "ImageTooling supports content:// and file:// image URIs");
        }
        return uri;
    }

    private static long sizeOf(Context context, Uri uri) {
        if (ContentResolver.SCHEME_FILE.equals(uri.getScheme())) {
            String path = uri.getPath();
            return path != null && new File(path).exists() ? new File(path).length() : -1;
        }
        try (Cursor cursor = context.getContentResolver().query(
                uri, new String[] {OpenableColumns.SIZE}, null, null, null)) {
            if (cursor != null && cursor.moveToFirst() && !cursor.isNull(0)) {
                return cursor.getLong(0);
            }
        } catch (RuntimeException ignored) {
            // Some providers do not project OpenableColumns.SIZE.
        }
        return -1;
    }

    private static String extensionOf(SourceInfo source) {
        if (source.mimeType != null) {
            if (source.mimeType.equalsIgnoreCase("image/png")) return "png";
            if (source.mimeType.equalsIgnoreCase("image/webp")) return "webp";
            if (source.mimeType.equalsIgnoreCase("image/heic")) return "heic";
            if (source.mimeType.equalsIgnoreCase("image/heif")) return "heif";
        }
        String path = source.uri.getPath();
        if (path != null) {
            int dot = path.lastIndexOf('.');
            if (dot >= 0 && dot < path.length() - 1) {
                String extension = path.substring(dot + 1).toLowerCase();
                if (extension.matches("[a-z0-9]{1,5}")) {
                    return extension;
                }
            }
        }
        return "jpg";
    }

    @Nullable
    private Context applicationContext() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        return context != null ? context.getApplicationContext() : null;
    }

    private static String valueResult(String valueJSON) {
        try {
            JSONObject result = new JSONObject();
            result.put("value", new JSONObject(valueJSON));
            return result.toString();
        } catch (JSONException failure) {
            return errorResult("ImageTooling serialization failed");
        }
    }

    private static String valueResult(JSONObject value) {
        JSONObject result = new JSONObject();
        put(result, "value", value);
        return result.toString();
    }

    private static String errorResult(String message) {
        JSONObject result = new JSONObject();
        put(result, "error", message == null || message.isEmpty()
                ? "ImageTooling failed" : message);
        return result.toString();
    }

    private static void put(JSONObject object, String key, Object value) {
        try {
            object.put(key, value);
        } catch (JSONException failure) {
            throw new IllegalStateException("ImageTooling serialization failed", failure);
        }
    }

    private static String messageOf(Throwable failure, String fallback) {
        String message = failure.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }
}
