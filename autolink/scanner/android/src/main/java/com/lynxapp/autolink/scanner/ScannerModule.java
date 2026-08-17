package com.lynxapp.autolink.scanner;

import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.WorkerThread;

import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.tasm.behavior.LynxContext;

import com.google.android.gms.tasks.Tasks;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * QR and barcode scanning exported to Lynx as {@code Scanner}. {@code scan}
 * opens the library's full-screen CameraX + ML Kit scanner Activity; the
 * Activity owns the CAMERA runtime permission request and reports denials as
 * a {@code permissionDenied} outcome. {@code scanFromImage} decodes a local
 * image URI (for example an {@code AlbumUtils.pick()} result) with the same
 * bundled ML Kit model, so it needs no camera at all.
 */
@LynxNativeModule(name = ScannerModule.NAME)
public final class ScannerModule extends LynxContextModule {
    public static final String NAME = "Scanner";

    private final Context applicationContext;
    private final ExecutorService executor = Executors.newFixedThreadPool(1);

    public ScannerModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void scan(Callback callback) {
        if (!ScannerCallbackStore.begin(callback)) {
            callback.invoke(ScannerCallbackStore.outcomeJSON(
                    "busy", null, null, "Another scanner request is already active"));
            return;
        }
        Context context = applicationContext;
        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                Intent intent = new Intent(context, ScannerActivity.class);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
                context.startActivity(intent);
            } catch (Throwable error) {
                ScannerCallbackStore.fail(error, "Unable to open the scanner");
            }
        });
    }

    @LynxMethod
    public void scanFromImage(String uriString, Callback callback) {
        final Uri uri;
        try {
            uri = parseURI(uriString);
        } catch (IllegalArgumentException error) {
            ScannerCallbackStore.fail(error.getMessage());
            return;
        }
        executor.execute(() -> decodeImage(uri, callback));
    }

    @Override
    public void destroy() {
        executor.shutdownNow();
    }

    @WorkerThread
    private void decodeImage(Uri uri, Callback callback) {
        BarcodeScanner scanner = BarcodeScanning.getClient();
        try {
            InputImage image = InputImage.fromFilePath(applicationContext, uri);
            List<Barcode> barcodes = Tasks.await(scanner.process(image));
            if (barcodes.isEmpty()) {
                callback.invoke(ScannerCallbackStore.outcomeJSON(
                        "noCodeFound", null, null, "No code was found in the image"));
                return;
            }
            Barcode barcode = barcodes.get(0);
            String content = barcode.getRawValue();
            if (content == null) {
                content = barcode.getDisplayValue();
            }
            callback.invoke(ScannerCallbackStore.outcomeJSON(
                    "success",
                    content == null ? "" : content,
                    formatName(barcode.getFormat()),
                    ""));
        } catch (Throwable error) {
            ScannerCallbackStore.fail(error, "Unable to decode the image");
        } finally {
            scanner.close();
        }
    }

    private static Uri parseURI(String uriString) {
        if (uriString == null || uriString.trim().isEmpty()) {
            throw new IllegalArgumentException("Image URI must not be empty");
        }
        Uri uri = Uri.parse(uriString.trim());
        String scheme = uri.getScheme();
        if (!ContentResolver.SCHEME_CONTENT.equals(scheme)
                && !ContentResolver.SCHEME_FILE.equals(scheme)) {
            throw new IllegalArgumentException("Scanner supports content:// and file:// URIs");
        }
        return uri;
    }

    /** Maps ML Kit format constants onto the cross-platform format names. */
    static String formatName(int format) {
        switch (format) {
            case Barcode.FORMAT_QR_CODE: return "qr_code";
            case Barcode.FORMAT_AZTEC: return "aztec";
            case Barcode.FORMAT_CODABAR: return "codabar";
            case Barcode.FORMAT_CODE_39: return "code39";
            case Barcode.FORMAT_CODE_93: return "code93";
            case Barcode.FORMAT_CODE_128: return "code128";
            case Barcode.FORMAT_DATA_MATRIX: return "data_matrix";
            case Barcode.FORMAT_EAN_8: return "ean_8";
            case Barcode.FORMAT_EAN_13: return "ean_13";
            case Barcode.FORMAT_ITF: return "itf";
            case Barcode.FORMAT_PDF417: return "pdf417";
            case Barcode.FORMAT_UPC_A: return "upc_a";
            case Barcode.FORMAT_UPC_E: return "upc_e";
            default: return "unknown";
        }
    }
}
