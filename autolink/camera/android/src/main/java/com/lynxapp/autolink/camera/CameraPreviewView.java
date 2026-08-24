package com.lynxapp.autolink.camera;

import android.Manifest;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.PackageManager;
import android.util.Range;
import android.util.Rational;
import android.view.Surface;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ExposureState;
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.Preview;
import androidx.camera.core.ZoomState;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.fragment.app.FragmentActivity;

import com.google.common.util.concurrent.ListenableFuture;

import java.io.File;
import java.io.IOException;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/** CameraX-backed inline preview owned by one Lynx custom element. */
final class CameraPreviewView extends FrameLayout {
    interface Listener {
        void onReady(Map<String, Object> detail);
        void onStateChanged(String state);
        void onError(String code, String message);
        void onCapture(CameraPhoto photo);
    }

    interface OperationCallback<T> {
        void onSuccess(T value);
        void onFailure(String message);
    }

    private final PreviewView previewView;
    private final Listener listener;

    @Nullable private ProcessCameraProvider cameraProvider;
    @Nullable private Preview preview;
    @Nullable private ImageCapture imageCapture;
    @Nullable private Camera camera;

    private boolean active = true;
    private boolean permissionRequestInFlight;
    private boolean permissionDenied;
    private boolean providerRequestInFlight;
    private boolean capturing;
    private String lens = "back";
    private float requestedZoom = 1f;
    private boolean torchEnabled;
    private int flashMode = ImageCapture.FLASH_MODE_AUTO;
    private float exposureCompensation;
    private int photoQuality = 92;
    private boolean mirrorPhoto = true;
    private String state = "stopped";

    CameraPreviewView(Context context, Listener listener) {
        super(context);
        this.listener = listener;
        previewView = new PreviewView(context);
        previewView.setImplementationMode(PreviewView.ImplementationMode.COMPATIBLE);
        previewView.setScaleType(PreviewView.ScaleType.FILL_CENTER);
        addView(previewView, new LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT));
        setClipToPadding(true);
        setClipChildren(true);
    }

    @Override
    protected void onAttachedToWindow() {
        super.onAttachedToWindow();
        startIfPossible();
    }

    @Override
    protected void onDetachedFromWindow() {
        stopCamera();
        super.onDetachedFromWindow();
    }

    void dispose() {
        active = false;
        stopCamera();
    }

    void setActive(boolean value) {
        if (active == value) {
            return;
        }
        active = value;
        if (active) {
            startIfPossible();
        } else {
            stopCamera();
        }
    }

    void setLens(@Nullable String value) {
        String normalized = "front".equals(value) ? "front" : "back";
        if (lens.equals(normalized)) {
            return;
        }
        lens = normalized;
        rebindCamera();
    }

    void setZoom(float value) {
        requestedZoom = Math.max(1f, value);
        applyZoom();
    }

    void setTorch(@Nullable String value) {
        torchEnabled = "on".equals(value);
        applyTorch();
    }

    void setFlash(@Nullable String value) {
        if ("on".equals(value)) {
            flashMode = ImageCapture.FLASH_MODE_ON;
        } else if ("off".equals(value)) {
            flashMode = ImageCapture.FLASH_MODE_OFF;
        } else {
            flashMode = ImageCapture.FLASH_MODE_AUTO;
        }
        if (imageCapture != null) {
            imageCapture.setFlashMode(flashMode);
        }
    }

    void setExposureCompensation(float value) {
        exposureCompensation = value;
        applyExposureCompensation();
    }

    void setPhotoQuality(int value) {
        int normalized = Math.max(1, Math.min(100, value));
        if (photoQuality == normalized) {
            return;
        }
        photoQuality = normalized;
        rebindCamera();
    }

    void setMirrorPhoto(boolean value) {
        mirrorPhoto = value;
    }

    void setPreviewFit(@Nullable String value) {
        previewView.setScaleType("contain".equals(value)
                ? PreviewView.ScaleType.FIT_CENTER
                : PreviewView.ScaleType.FILL_CENTER);
    }

    void capture(OperationCallback<CameraPhoto> callback) {
        ImageCapture currentCapture = imageCapture;
        if (currentCapture == null || camera == null || !"ready".equals(state)) {
            callback.onFailure("Camera is not ready");
            return;
        }
        if (capturing) {
            callback.onFailure("A photo capture is already in progress");
            return;
        }

        final File file;
        try {
            file = createOutputFile();
        } catch (IOException error) {
            callback.onFailure(messageOf(error, "Unable to create a camera output file"));
            return;
        }

        capturing = true;
        currentCapture.setFlashMode(flashMode);
        ImageCapture.Metadata metadata = new ImageCapture.Metadata();
        metadata.setReversedHorizontal(mirrorPhoto && "front".equals(lens));
        ImageCapture.OutputFileOptions options = new ImageCapture.OutputFileOptions.Builder(file)
                .setMetadata(metadata)
                .build();
        currentCapture.takePicture(
                options,
                ContextCompat.getMainExecutor(getContext()),
                new ImageCapture.OnImageSavedCallback() {
                    @Override
                    public void onImageSaved(
                            @NonNull ImageCapture.OutputFileResults outputFileResults) {
                        capturing = false;
                        try {
                            CameraPhoto photo = CameraPhoto.fromFile(file);
                            listener.onCapture(photo);
                            callback.onSuccess(photo);
                        } catch (Throwable error) {
                            //noinspection ResultOfMethodCallIgnored
                            file.delete();
                            reportCaptureFailure(error, callback);
                        }
                    }

                    @Override
                    public void onError(@NonNull ImageCaptureException exception) {
                        capturing = false;
                        //noinspection ResultOfMethodCallIgnored
                        file.delete();
                        reportCaptureFailure(exception, callback);
                    }
                });
    }

    void focusAtPoint(float normalizedX, float normalizedY, OperationCallback<Void> callback) {
        Camera currentCamera = camera;
        if (currentCamera == null || !"ready".equals(state)) {
            callback.onFailure("Camera is not ready");
            return;
        }
        if (previewView.getWidth() <= 0 || previewView.getHeight() <= 0) {
            callback.onFailure("Camera preview has no layout size");
            return;
        }
        MeteringPoint point = previewView.getMeteringPointFactory().createPoint(
                normalizedX * previewView.getWidth(),
                normalizedY * previewView.getHeight());
        FocusMeteringAction action = new FocusMeteringAction.Builder(
                point,
                FocusMeteringAction.FLAG_AF | FocusMeteringAction.FLAG_AE)
                .setAutoCancelDuration(3, TimeUnit.SECONDS)
                .build();
        ListenableFuture<?> future = currentCamera.getCameraControl().startFocusAndMetering(action);
        future.addListener(() -> {
            try {
                future.get();
                callback.onSuccess(null);
            } catch (Throwable error) {
                callback.onFailure(messageOf(error, "Unable to focus the camera"));
            }
        }, ContextCompat.getMainExecutor(getContext()));
    }

    private void startIfPossible() {
        if (!active || !isAttachedToWindow()) {
            return;
        }
        if (ContextCompat.checkSelfPermission(getContext(), Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            requestPermission();
            return;
        }
        permissionDenied = false;
        requestCameraProvider();
    }

    private void requestPermission() {
        if (permissionRequestInFlight || permissionDenied) {
            return;
        }
        FragmentActivity activity = findFragmentActivity(getContext());
        if (activity == null) {
            listener.onError(
                    "configurationFailed",
                    "x-camera-view must be hosted by an AndroidX FragmentActivity");
            return;
        }
        permissionRequestInFlight = true;
        updateState("requestingPermission");
        CameraPermissionPrompt.request(activity, granted -> {
            permissionRequestInFlight = false;
            permissionDenied = !granted;
            if (granted) {
                startIfPossible();
            } else {
                updateState("stopped");
                listener.onError("permissionDenied", "Camera permission was denied");
            }
        });
    }

    private void requestCameraProvider() {
        if (cameraProvider != null) {
            bindCamera();
            return;
        }
        if (providerRequestInFlight) {
            return;
        }
        providerRequestInFlight = true;
        updateState("starting");
        ListenableFuture<ProcessCameraProvider> future =
                ProcessCameraProvider.getInstance(getContext());
        future.addListener(() -> {
            providerRequestInFlight = false;
            try {
                cameraProvider = future.get();
                if (active && isAttachedToWindow()) {
                    bindCamera();
                }
            } catch (Throwable error) {
                updateState("stopped");
                listener.onError(
                        "configurationFailed",
                        messageOf(error, "Unable to initialize CameraX"));
            }
        }, ContextCompat.getMainExecutor(getContext()));
    }

    private void bindCamera() {
        ProcessCameraProvider provider = cameraProvider;
        FragmentActivity activity = findFragmentActivity(getContext());
        if (provider == null || activity == null || !active || !isAttachedToWindow()) {
            return;
        }
        updateState("starting");
        unbindUseCases();

        CameraSelector selector = new CameraSelector.Builder()
                .requireLensFacing("front".equals(lens)
                        ? CameraSelector.LENS_FACING_FRONT
                        : CameraSelector.LENS_FACING_BACK)
                .build();
        try {
            if (!provider.hasCamera(selector)) {
                updateState("stopped");
                listener.onError("unavailable", "The selected camera is unavailable");
                return;
            }

            int rotation = previewView.getDisplay() == null
                    ? Surface.ROTATION_0
                    : previewView.getDisplay().getRotation();
            Preview newPreview = new Preview.Builder()
                    .setTargetRotation(rotation)
                    .build();
            ImageCapture newImageCapture = new ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                    .setJpegQuality(photoQuality)
                    .setTargetRotation(rotation)
                    .build();
            newImageCapture.setFlashMode(flashMode);
            newPreview.setSurfaceProvider(previewView.getSurfaceProvider());

            camera = provider.bindToLifecycle(
                    activity,
                    selector,
                    newPreview,
                    newImageCapture);
            preview = newPreview;
            imageCapture = newImageCapture;
            applyControls();
            updateState("ready");
            emitReady();
        } catch (Throwable error) {
            unbindUseCases();
            updateState("stopped");
            listener.onError(
                    "configurationFailed",
                    messageOf(error, "Unable to start the selected camera"));
        }
    }

    private void rebindCamera() {
        if (active && isAttachedToWindow() && cameraProvider != null) {
            bindCamera();
        }
    }

    private void stopCamera() {
        unbindUseCases();
        capturing = false;
        updateState("stopped");
    }

    private void unbindUseCases() {
        ProcessCameraProvider provider = cameraProvider;
        if (provider != null) {
            if (preview != null) {
                provider.unbind(preview);
            }
            if (imageCapture != null) {
                provider.unbind(imageCapture);
            }
        }
        preview = null;
        imageCapture = null;
        camera = null;
    }

    private void applyControls() {
        applyZoom();
        applyTorch();
        applyExposureCompensation();
    }

    private void applyZoom() {
        Camera current = camera;
        if (current == null) {
            return;
        }
        ZoomState zoomState = current.getCameraInfo().getZoomState().getValue();
        float min = zoomState == null ? 1f : zoomState.getMinZoomRatio();
        float max = zoomState == null ? 1f : zoomState.getMaxZoomRatio();
        float clamped = Math.max(min, Math.min(max, requestedZoom));
        current.getCameraControl().setZoomRatio(clamped);
    }

    private void applyTorch() {
        Camera current = camera;
        if (current == null) {
            return;
        }
        current.getCameraControl().enableTorch(
                torchEnabled && current.getCameraInfo().hasFlashUnit());
    }

    private void applyExposureCompensation() {
        Camera current = camera;
        if (current == null) {
            return;
        }
        ExposureState exposureState = current.getCameraInfo().getExposureState();
        if (!exposureState.isExposureCompensationSupported()) {
            return;
        }
        Rational step = exposureState.getExposureCompensationStep();
        if (step.floatValue() == 0f) {
            return;
        }
        Range<Integer> range = exposureState.getExposureCompensationRange();
        int requestedIndex = Math.round(exposureCompensation / step.floatValue());
        int clamped = Math.max(range.getLower(), Math.min(range.getUpper(), requestedIndex));
        current.getCameraControl().setExposureCompensationIndex(clamped);
    }

    private void emitReady() {
        Camera current = camera;
        if (current == null) {
            return;
        }
        ZoomState zoomState = current.getCameraInfo().getZoomState().getValue();
        ExposureState exposureState = current.getCameraInfo().getExposureState();
        float exposureMin = 0f;
        float exposureMax = 0f;
        if (exposureState.isExposureCompensationSupported()) {
            Rational step = exposureState.getExposureCompensationStep();
            Range<Integer> range = exposureState.getExposureCompensationRange();
            exposureMin = range.getLower() * step.floatValue();
            exposureMax = range.getUpper() * step.floatValue();
        }
        float minZoom = zoomState == null ? 1f : zoomState.getMinZoomRatio();
        float maxZoom = zoomState == null ? 1f : zoomState.getMaxZoomRatio();
        float currentZoom = zoomState == null
                ? Math.max(minZoom, Math.min(maxZoom, requestedZoom))
                : zoomState.getZoomRatio();

        Map<String, Object> detail = new HashMap<>();
        detail.put("lens", lens);
        detail.put("zoom", (double) currentZoom);
        detail.put("minZoom", (double) minZoom);
        detail.put("maxZoom", (double) maxZoom);
        detail.put("torchSupported", current.getCameraInfo().hasFlashUnit());
        detail.put("exposureMin", (double) exposureMin);
        detail.put("exposureMax", (double) exposureMax);
        listener.onReady(detail);
    }

    private void updateState(String next) {
        if (state.equals(next)) {
            return;
        }
        state = next;
        listener.onStateChanged(next);
    }

    private File createOutputFile() throws IOException {
        File directory = new File(getContext().getCacheDir(), "LynxCamera");
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Unable to create the camera cache directory");
        }
        return new File(directory, "inline-" + UUID.randomUUID() + ".jpg");
    }

    private void reportCaptureFailure(
            Throwable error,
            OperationCallback<CameraPhoto> callback) {
        String message = messageOf(error, "Unable to capture a photo");
        listener.onError("captureFailed", message);
        callback.onFailure(message);
    }

    @Nullable
    private static FragmentActivity findFragmentActivity(Context context) {
        Context current = context;
        while (current instanceof ContextWrapper) {
            if (current instanceof FragmentActivity) {
                return (FragmentActivity) current;
            }
            Context base = ((ContextWrapper) current).getBaseContext();
            if (base == current) {
                break;
            }
            current = base;
        }
        return current instanceof FragmentActivity ? (FragmentActivity) current : null;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
