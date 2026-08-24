package com.lynxapp.autolink.camera;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.provider.MediaStore;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import java.io.File;
import java.io.IOException;
import java.util.UUID;

/** Transparent proxy that owns camera permission and an ACTION_IMAGE_CAPTURE result. */
public final class CameraCaptureActivity extends Activity {
    static final String EXTRA_LENS = "lynx.camera.lens";

    private static final int REQUEST_PERMISSION = 8201;
    private static final int REQUEST_CAPTURE = 8202;
    private static final String STATE_FILE = "lynx.camera.outputFile";
    private static final String STATE_LAUNCHED = "lynx.camera.launched";

    @Nullable private File outputFile;
    private boolean launched;
    private boolean completed;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (savedInstanceState != null) {
            String path = savedInstanceState.getString(STATE_FILE);
            outputFile = path == null ? null : new File(path);
            launched = savedInstanceState.getBoolean(STATE_LAUNCHED, false);
        }
        if (!launched) {
            ensurePermissionAndLaunch();
        }
    }

    @Override
    protected void onSaveInstanceState(@NonNull Bundle outState) {
        super.onSaveInstanceState(outState);
        if (outputFile != null) {
            outState.putString(STATE_FILE, outputFile.getAbsolutePath());
        }
        outState.putBoolean(STATE_LAUNCHED, launched);
    }

    private void ensurePermissionAndLaunch() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            launchSystemCamera();
            return;
        }
        ActivityCompat.requestPermissions(
                this,
                new String[] {Manifest.permission.CAMERA},
                REQUEST_PERMISSION);
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_PERMISSION) {
            return;
        }
        if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            launchSystemCamera();
        } else {
            finishWithOutcome("permissionDenied", null, "Camera permission was denied");
        }
    }

    private void launchSystemCamera() {
        try {
            Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            if (intent.resolveActivity(getPackageManager()) == null) {
                finishWithOutcome("unavailable", null, "No system camera application is available");
                return;
            }

            outputFile = createOutputFile();
            Uri outputUri = FileProvider.getUriForFile(
                    this,
                    getPackageName() + ".lynx.camera.fileprovider",
                    outputFile);
            intent.putExtra(MediaStore.EXTRA_OUTPUT, outputUri);
            intent.setClipData(ClipData.newRawUri("Lynx camera output", outputUri));
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION
                    | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
            applyPreferredLens(intent);
            launched = true;
            startActivityForResult(intent, REQUEST_CAPTURE);
        } catch (Throwable error) {
            deleteOutput();
            finishWithOutcome(
                    "unavailable",
                    null,
                    messageOf(error, "Unable to open the system camera"));
        }
    }

    private void applyPreferredLens(Intent intent) {
        boolean front = "front".equals(getIntent().getStringExtra(EXTRA_LENS));
        // ACTION_IMAGE_CAPTURE has no standardized lens selector. These widely
        // recognized hints are best-effort; unsupported camera apps ignore them.
        intent.putExtra("android.intent.extras.CAMERA_FACING", front ? 1 : 0);
        intent.putExtra("android.intent.extra.USE_FRONT_CAMERA", front);
        intent.putExtra("android.intent.extra.CAMERA_FACING", front ? 1 : 0);
    }

    private File createOutputFile() throws IOException {
        File directory = new File(getCacheDir(), "LynxCamera");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Unable to create the camera cache directory");
        }
        return new File(directory, "system-" + UUID.randomUUID() + ".jpg");
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_CAPTURE) {
            return;
        }
        if (resultCode != RESULT_OK) {
            deleteOutput();
            finishWithOutcome("userCancel", null, "The user cancelled the camera");
            return;
        }
        try {
            if (outputFile == null) {
                throw new IOException("The camera output file is missing");
            }
            finishWithOutcome("success", CameraPhoto.fromFile(outputFile), "");
        } catch (Throwable error) {
            deleteOutput();
            finishWithOutcome(
                    "unavailable",
                    null,
                    messageOf(error, "Unable to read the captured photo"));
        }
    }

    @Override
    public void onBackPressed() {
        deleteOutput();
        finishWithOutcome("userCancel", null, "The user cancelled the camera");
    }

    private void finishWithOutcome(String code, @Nullable CameraPhoto photo, String message) {
        if (completed) {
            return;
        }
        completed = true;
        CameraCallbackStore.completeOutcome(code, photo, message);
        finish();
        overridePendingTransition(0, 0);
    }

    private void deleteOutput() {
        if (outputFile != null && outputFile.isFile()) {
            //noinspection ResultOfMethodCallIgnored
            outputFile.delete();
        }
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
