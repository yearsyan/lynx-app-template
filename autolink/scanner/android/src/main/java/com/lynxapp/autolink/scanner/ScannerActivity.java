package com.lynxapp.autolink.scanner;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;

import androidx.activity.ComponentActivity;
import androidx.annotation.MainThread;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.ImageProxy;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.content.ContextCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;
import com.google.mlkit.vision.common.InputImage;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Full-screen scanner owned by the Autolink library: a CameraX preview with
 * an ML Kit barcode analyzer on top. It requests the CAMERA runtime
 * permission itself and delivers exactly one outcome through
 * {@link ScannerCallbackStore} before finishing.
 */
public final class ScannerActivity extends ComponentActivity {
    private static final int REQUEST_CAMERA_PERMISSION = 7201;
    private static final int FRAME_COLOR = 0xFFFFFFFF;
    private static final int DIM_COLOR = 0x99000000;

    private PreviewView previewView;
    private ScannerOverlayView overlayView;
    private TextView hintLabel;
    private TextView torchButton;
    private View closeButton;
    private Camera camera;
    private ExecutorService analysisExecutor;
    private BarcodeScanner barcodeScanner;
    private boolean delivered;
    private boolean torchOn;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root = new FrameLayout(this);
        previewView = new PreviewView(this);
        previewView.setLayoutParams(matchParent());
        root.addView(previewView);

        overlayView = new ScannerOverlayView(this);
        overlayView.setLayoutParams(matchParent());
        root.addView(overlayView);

        closeButton = buildCloseButton();
        root.addView(closeButton);

        hintLabel = new TextView(this);
        hintLabel.setText("Align the code inside the frame");
        hintLabel.setTextColor(0xE6FFFFFF);
        hintLabel.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        hintLabel.setGravity(Gravity.CENTER);
        hintLabel.setLayoutParams(new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL | Gravity.TOP));
        root.addView(hintLabel);
        overlayView.bindHintLabel(hintLabel);

        torchButton = buildTorchButton();
        root.addView(torchButton);

        setContentView(root);
        applyInsetPaddings(root);

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
                == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            requestPermissions(
                    new String[] { Manifest.permission.CAMERA },
                    REQUEST_CAMERA_PERMISSION);
        }
    }

    @Override
    public void onRequestPermissionsResult(
            int requestCode,
            @NonNull String[] permissions,
            @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode != REQUEST_CAMERA_PERMISSION) {
            return;
        }
        if (grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            startCamera();
        } else {
            deliver("permissionDenied", null, null, "Camera permission was not granted");
        }
    }

    @Override
    protected void onDestroy() {
        if (!delivered) {
            // The Activity died without a user-visible outcome (for example a
            // system kill); release the pending JavaScript promise as a cancel.
            deliver("userCancel", null, null, "");
        }
        if (analysisExecutor != null) {
            analysisExecutor.shutdownNow();
        }
        if (barcodeScanner != null) {
            barcodeScanner.close();
        }
        super.onDestroy();
    }

    private void startCamera() {
        if (analysisExecutor == null) {
            analysisExecutor = Executors.newSingleThreadExecutor();
        }
        if (barcodeScanner == null) {
            barcodeScanner = BarcodeScanning.getClient();
        }
        ListenableFuture<ProcessCameraProvider> providerFuture =
                ProcessCameraProvider.getInstance(this);
        providerFuture.addListener(() -> {
            if (isFinishing() || isDestroyed()) {
                return;
            }
            try {
                ProcessCameraProvider provider = providerFuture.get();
                Preview preview = new Preview.Builder().build();
                preview.setSurfaceProvider(previewView.getSurfaceProvider());

                ImageAnalysis analysis = new ImageAnalysis.Builder()
                        .setBackpressureStrategy(
                                ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build();
                analysis.setAnalyzer(analysisExecutor, this::analyzeFrame);

                provider.unbindAll();
                camera = provider.bindToLifecycle(
                        this,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        analysis);
                boolean hasFlash =
                        camera != null && camera.getCameraInfo().hasFlashUnit();
                torchButton.setVisibility(hasFlash ? View.VISIBLE : View.GONE);
            } catch (Throwable error) {
                deliver("unavailable", null, null,
                        "The camera is unavailable: " + messageOf(error));
            }
        }, ContextCompat.getMainExecutor(this));
    }

    @SuppressLint("UnsafeOptInUsageError")
    private void analyzeFrame(ImageProxy proxy) {
        try {
            int rotation = proxy.getImageInfo().getRotationDegrees();
            InputImage image;
            if (proxy.getImage() != null) {
                image = InputImage.fromMediaImage(proxy.getImage(), rotation);
            } else {
                image = InputImage.fromBitmap(proxy.toBitmap(), rotation);
            }
            barcodeScanner.process(image)
                    .addOnSuccessListener(barcodes -> {
                        Barcode barcode = firstReadable(barcodes);
                        if (barcode != null) {
                            String raw = barcode.getRawValue();
                            String content = raw != null
                                    ? raw
                                    : barcode.getDisplayValue();
                            final String value = content == null ? "" : content;
                            runOnUiThread(() -> deliver(
                                    "success",
                                    value,
                                    ScannerModule.formatName(barcode.getFormat()),
                                    ""));
                        }
                    })
                    .addOnCompleteListener(task -> proxy.close());
        } catch (Throwable error) {
            proxy.close();
        }
    }

    private static Barcode firstReadable(List<Barcode> barcodes) {
        for (Barcode barcode : barcodes) {
            String value = barcode.getRawValue();
            if (value == null) {
                value = barcode.getDisplayValue();
            }
            if (value != null && !value.isEmpty()) {
                return barcode;
            }
        }
        return null;
    }

    @MainThread
    private void deliver(String code, String content, String format, String message) {
        if (delivered) {
            return;
        }
        delivered = true;
        ScannerCallbackStore.completeOutcome(code, content, format, message);
        finish();
        overridePendingTransition(0, 0);
    }

    private View buildCloseButton() {
        TextView button = new TextView(this);
        button.setText("✕");
        button.setTextColor(Color.WHITE);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        button.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                dp(44), dp(44), Gravity.START | Gravity.TOP);
        params.leftMargin = dp(8);
        params.topMargin = dp(8);
        button.setLayoutParams(params);
        button.setBackground(roundBackground(0x33000000));
        button.setOnClickListener(view ->
                deliver("userCancel", null, null, ""));
        return button;
    }

    private TextView buildTorchButton() {
        TextView button = new TextView(this);
        button.setText("Torch");
        button.setTextColor(Color.WHITE);
        button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        button.setGravity(Gravity.CENTER);
        button.setPadding(dp(20), dp(10), dp(20), dp(10));
        button.setTypeface(Typeface.DEFAULT_BOLD);
        FrameLayout.LayoutParams params = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM);
        params.bottomMargin = dp(48);
        button.setLayoutParams(params);
        button.setBackground(roundBackground(0x33000000));
        button.setVisibility(View.GONE);
        button.setOnClickListener(view -> {
            if (camera == null) {
                return;
            }
            torchOn = !torchOn;
            camera.getCameraControl().enableTorch(torchOn);
            button.setAlpha(torchOn ? 1f : 0.6f);
        });
        button.setAlpha(0.6f);
        return button;
    }

    private void applyInsetPaddings(FrameLayout root) {
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            WindowInsetsCompat compat = WindowInsetsCompat.toWindowInsetsCompat(insets);
            int top = compat.getInsets(WindowInsetsCompat.Type.systemBars()).top;
            int bottom = compat.getInsets(WindowInsetsCompat.Type.systemBars()).bottom;
            FrameLayout.LayoutParams closeParams =
                    (FrameLayout.LayoutParams) closeButton.getLayoutParams();
            closeParams.topMargin = top + dp(8);
            closeButton.setLayoutParams(closeParams);
            FrameLayout.LayoutParams torchParams =
                    (FrameLayout.LayoutParams) torchButton.getLayoutParams();
            torchParams.bottomMargin = bottom + dp(48);
            torchButton.setLayoutParams(torchParams);
            return insets.consumeSystemWindowInsets();
        });
    }

    private static GradientDrawable roundBackground(int color) {
        GradientDrawable drawable = new GradientDrawable();
        drawable.setColor(color);
        drawable.setCornerRadius(22);
        return drawable;
    }

    private static String messageOf(Throwable error) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty()
                ? error.getClass().getSimpleName()
                : message;
    }

    private FrameLayout.LayoutParams matchParent() {
        return new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT);
    }

    private int dp(int value) {
        return (int) TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value,
                getResources().getDisplayMetrics());
    }

    /** Dims everything outside the centered square frame and draws corners. */
    private static final class ScannerOverlayView extends View {
        private static final float FRAME_RATIO = 0.62f;
        private static final float FRAME_VERTICAL_POSITION = 0.4f;
        private static final int CORNER_LENGTH = 24;
        private static final int CORNER_STROKE = 4;

        private final Paint dimPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint framePaint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private View hintLabel;

        ScannerOverlayView(Context context) {
            super(context);
            dimPaint.setColor(DIM_COLOR);
            framePaint.setColor(FRAME_COLOR);
            framePaint.setStyle(Paint.Style.STROKE);
            framePaint.setStrokeWidth(CORNER_STROKE);
        }

        void bindHintLabel(View hintLabel) {
            this.hintLabel = hintLabel;
        }

        Rect frameRect() {
            int width = getWidth();
            int height = getHeight();
            int size = Math.round(Math.min(width, height) * FRAME_RATIO);
            int left = (width - size) / 2;
            int top = Math.round((height - size) * FRAME_VERTICAL_POSITION);
            return new Rect(left, top, left + size, top + size);
        }

        @Override
        protected void onSizeChanged(int w, int h, int oldw, int oldh) {
            super.onSizeChanged(w, h, oldw, oldh);
            if (hintLabel != null && w > 0 && h > 0) {
                Rect frame = frameRect();
                FrameLayout.LayoutParams params =
                        (FrameLayout.LayoutParams) hintLabel.getLayoutParams();
                params.width = w;
                params.topMargin = frame.bottom + dp(28);
                hintLabel.setLayoutParams(params);
            }
        }

        @Override
        protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            Rect frame = frameRect();
            canvas.drawRect(0, 0, getWidth(), frame.top, dimPaint);
            canvas.drawRect(0, frame.bottom, getWidth(), getHeight(), dimPaint);
            canvas.drawRect(0, frame.top, frame.left, frame.bottom, dimPaint);
            canvas.drawRect(frame.right, frame.top, getWidth(), frame.bottom, dimPaint);
            drawCorner(canvas, frame.left, frame.top, 1, 1);
            drawCorner(canvas, frame.right, frame.top, -1, 1);
            drawCorner(canvas, frame.left, frame.bottom, 1, -1);
            drawCorner(canvas, frame.right, frame.bottom, -1, -1);
        }

        private void drawCorner(Canvas canvas, int x, int y, int dx, int dy) {
            int length = dp(CORNER_LENGTH);
            int stroke = CORNER_STROKE / 2;
            RectF horizontal = new RectF(
                    x + (dx > 0 ? -stroke : -length + stroke),
                    y - stroke,
                    x + (dx > 0 ? length - stroke : stroke),
                    y + stroke);
            RectF vertical = new RectF(
                    x - stroke,
                    y + (dy > 0 ? -stroke : -length + stroke),
                    x + stroke,
                    y + (dy > 0 ? length - stroke : stroke));
            canvas.drawRect(horizontal, framePaint);
            canvas.drawRect(vertical, framePaint);
        }

        private int dp(int value) {
            return (int) TypedValue.applyDimension(
                    TypedValue.COMPLEX_UNIT_DIP,
                    value,
                    getResources().getDisplayMetrics());
        }
    }
}
