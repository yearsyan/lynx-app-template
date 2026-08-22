package com.lynxapp.autolink.device;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.res.Resources;
import android.graphics.Point;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.BatteryManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.DisplayMetrics;
import android.view.Display;
import android.view.Surface;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.Nullable;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.tasm.LynxView;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Device, safe-area, status-bar, display, battery and motion-sensor APIs
 * exported to Lynx as Device. All geometry values are read on demand so
 * configuration changes (locale, multi-window) are reflected without a
 * restart; widths are reported in Lynx logical pixels (physical px divided
 * by the current density), matching the unit Lynx layout consumes.
 *
 * Sensor readings flow back through the module's {@link LynxContext} as
 * `sensors` global events — the same channel the WebSocket module uses —
 * so no callback is held beyond a command ack. The JS bridge refcounts
 * listeners and only keeps a sensor registered while at least one observer
 * is attached. Accelerometer reports m/s^2 including gravity on every
 * platform. Compass reports the magnetic azimuth in degrees (0-360) with
 * an accuracy estimate in degrees (-1 when unreliable), preferring the
 * rotation-vector sensor and falling back to accelerometer + magnetometer
 * fusion.
 */
@LynxNativeModule(name = DeviceModule.NAME)
public final class DeviceModule extends LynxContextModule implements SensorEventListener {
    public static final String NAME = "Device";
    public static final String EVENT_NAME = "sensors";

    private static final String TYPE_ACCELEROMETER = "accelerometer";
    private static final String TYPE_COMPASS = "compass";
    private static final int TABLET_MIN_SMALLEST_WIDTH_DP = 600;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final List<Sensor> registered = new ArrayList<>();
    private final float[] rotationMatrix = new float[9];
    private final float[] remappedMatrix = new float[9];
    private final float[] orientation = new float[3];
    private final float[] gravity = new float[3];
    private final float[] geomagnetic = new float[3];

    private SensorManager sensorManager;
    private volatile boolean destroyed = false;
    private boolean accelerometerActive = false;
    private boolean compassActive = false;
    private boolean compassFusion = false;
    private boolean gravitySet = false;
    private boolean geomagneticSet = false;
    private volatile int compassSensorAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE;

    public DeviceModule(LynxContext context) {
        super(context);
    }

    // ------------------------------------------------------------------
    // Device facts, safe area and status bar
    // ------------------------------------------------------------------

    @LynxMethod
    public void getInfo(Callback callback) {
        Context context = hostContext();
        if (context == null) {
            callback.invoke(error("Device has no host context"));
            return;
        }
        try {
            JSONObject value = new JSONObject();
            value.put("model", Build.MODEL != null ? Build.MODEL : "");
            value.put("manufacturer", Build.MANUFACTURER != null ? Build.MANUFACTURER : "");
            value.put("osVersion", Build.VERSION.RELEASE != null ? Build.VERSION.RELEASE : "");
            value.put("osApiLevel", Build.VERSION.SDK_INT);
            putAppVersion(value, context);
            value.put("density", context.getResources().getDisplayMetrics().density);
            value.put("locale", Locale.getDefault().toLanguageTag());
            value.put("isTablet", isTablet(context));
            value.put("isFoldable", isFoldable(context));
            callback.invoke(result(value));
        } catch (Throwable failure) {
            callback.invoke(error(messageOf(failure, "Unable to read device information")));
        }
    }

    @LynxMethod
    public void getSafeAreaInsets(Callback callback) {
        LynxView lynxView = mLynxContext != null ? mLynxContext.getLynxView() : null;
        if (lynxView == null) {
            callback.invoke(error("Device has no attached LynxView"));
            return;
        }
        lynxView.post(() -> {
            try {
                WindowInsetsCompat windowInsets = ViewCompat.getRootWindowInsets(lynxView);
                if (windowInsets == null) {
                    callback.invoke(error("Device has no window insets"));
                    return;
                }
                Insets nativeInsets = windowInsets.getInsets(
                        WindowInsetsCompat.Type.systemBars()
                                | WindowInsetsCompat.Type.displayCutout());
                float density = lynxView.getResources().getDisplayMetrics().density;
                if (density <= 0) {
                    density = 1;
                }
                JSONObject value = new JSONObject();
                value.put("top", nativeInsets.top / (double) density);
                value.put("right", nativeInsets.right / (double) density);
                value.put("bottom", nativeInsets.bottom / (double) density);
                value.put("left", nativeInsets.left / (double) density);
                callback.invoke(result(value));
            } catch (Throwable failure) {
                callback.invoke(error(messageOf(failure, "Unable to read safe-area insets")));
            }
        });
    }

    @LynxMethod
    public void setStatusBarStyle(String style, Callback callback) {
        if (!DeviceSystemUI.isStatusBarStyle(style)) {
            callback.invoke("Invalid status bar style: " + style);
            return;
        }
        Activity activity = hostActivity();
        if (activity == null) {
            callback.invoke("Device has no Activity host");
            return;
        }
        activity.runOnUiThread(() -> {
            try {
                DeviceSystemUI.setStatusBarStyle(activity, style);
                callback.invoke("");
            } catch (Throwable failure) {
                callback.invoke(messageOf(failure, "Unable to style the status bar"));
            }
        });
    }

    // ------------------------------------------------------------------
    // Display metrics
    // ------------------------------------------------------------------

    @LynxMethod
    public void screenWidth(Callback callback) {
        DisplayMetrics metrics = screenMetrics();
        if (metrics == null) {
            callback.invoke(error("Device has no host context"));
            return;
        }
        callback.invoke(result(metrics.widthPixels / metrics.density));
    }

    @LynxMethod
    public void windowWidth(Callback callback) {
        Activity activity = hostActivity();
        if (activity == null) {
            // Without an Activity the window is the full screen.
            screenWidth(callback);
            return;
        }
        float density = activity.getResources().getDisplayMetrics().density;
        int widthPx;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            widthPx = activity.getWindowManager()
                    .getCurrentWindowMetrics()
                    .getBounds()
                    .width();
        } else {
            Point size = new Point();
            activity.getWindowManager().getDefaultDisplay().getSize(size);
            widthPx = size.x;
        }
        callback.invoke(result(widthPx / density));
    }

    @LynxMethod
    public void lynxViewWidth(Callback callback) {
        if (mLynxContext == null) {
            callback.invoke(error("Device has no host context"));
            return;
        }
        LynxView view = mLynxContext.getLynxView();
        if (view == null) {
            callback.invoke(error("LynxView is not attached yet"));
            return;
        }
        // Zero means the view has not been laid out yet; it is reported
        // as-is so callers can distinguish it from an unavailable view.
        float density = view.getResources().getDisplayMetrics().density;
        callback.invoke(result(view.getWidth() / density));
    }

    /**
     * Window brightness when the app has overridden it, otherwise the system
     * brightness normalized to 0..1. Brightness is window-scoped: it applies
     * while the app is visible and needs no permission.
     */
    @LynxMethod
    public void getBrightness(Callback callback) {
        Activity activity = hostActivity();
        Runnable read = () -> {
            try {
                float windowBrightness;
                if (activity != null) {
                    windowBrightness = activity.getWindow().getAttributes().screenBrightness;
                    if (windowBrightness >= 0) {
                        callback.invoke(result(windowBrightness));
                        return;
                    }
                }
                ContentResolver contentResolver = resolver();
                if (contentResolver == null) {
                    callback.invoke(error("Device has no host context"));
                    return;
                }
                int system = Settings.System.getInt(
                        contentResolver, Settings.System.SCREEN_BRIGHTNESS);
                callback.invoke(result(system / 255.0));
            } catch (Throwable failure) {
                callback.invoke(error(messageOf(failure, "Unable to read the screen brightness")));
            }
        };
        if (activity != null) {
            // Window attributes may be mutated concurrently by the UI thread.
            activity.runOnUiThread(read);
        } else {
            read.run();
        }
    }

    @LynxMethod
    public void setBrightness(double value, Callback callback) {
        if (Double.isNaN(value) || value < 0 || value > 1) {
            callback.invoke("Brightness must be between 0 and 1");
            return;
        }
        Activity activity = hostActivity();
        if (activity == null) {
            callback.invoke("Device has no host activity");
            return;
        }
        // Lynx invokes native-module methods on its JS thread. Mutating window
        // attributes must happen on the thread that owns the view hierarchy,
        // otherwise ViewRootImpl.checkThread throws CalledFromWrongThreadException
        // whenever the framework takes the synchronous update path.
        activity.runOnUiThread(() -> {
            try {
                Window window = activity.getWindow();
                WindowManager.LayoutParams attrs = window.getAttributes();
                attrs.screenBrightness = (float) value;
                window.setAttributes(attrs);
                callback.invoke("");
            } catch (Throwable failure) {
                callback.invoke(messageOf(failure, "Unable to set the screen brightness"));
            }
        });
    }

    @LynxMethod
    public void setKeepScreenOn(boolean enabled, Callback callback) {
        Activity activity = hostActivity();
        if (activity == null) {
            callback.invoke("Device has no host activity");
            return;
        }
        // FLAG_KEEP_SCREEN_ON toggles go through PhoneWindow.setFlags, which
        // synchronously updates the view hierarchy — main thread required.
        activity.runOnUiThread(() -> {
            try {
                if (enabled) {
                    activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
                callback.invoke("");
            } catch (Throwable failure) {
                callback.invoke(messageOf(failure, "Unable to change keep-screen-on"));
            }
        });
    }

    // ------------------------------------------------------------------
    // Battery
    // ------------------------------------------------------------------

    /**
     * On-demand battery state. Reads the sticky ACTION_BATTERY_CHANGED
     * broadcast so no receiver registration or permission is needed and
     * every call reflects the current state.
     */
    @LynxMethod
    public void getBatteryInfo(Callback callback) {
        Context context = hostContext();
        if (context == null) {
            callback.invoke(errorMap("Device has no host context"));
            return;
        }
        Intent battery = context.registerReceiver(
                null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        try {
            JavaOnlyMap value = new JavaOnlyMap();
            if (battery == null) {
                value.putNull("level");
                value.putBoolean("charging", false);
            } else {
                int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                if (level >= 0 && scale > 0) {
                    value.putDouble("level", Math.min(1.0, level / (double) scale));
                } else {
                    value.putNull("level");
                }
                int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
                value.putBoolean("charging",
                        status == BatteryManager.BATTERY_STATUS_CHARGING
                                || status == BatteryManager.BATTERY_STATUS_FULL);
            }
            JavaOnlyMap envelope = new JavaOnlyMap();
            envelope.putMap("value", value);
            callback.invoke(envelope);
        } catch (Throwable failure) {
            callback.invoke(errorMap(messageOf(failure, "Unable to read battery information")));
        }
    }

    // ------------------------------------------------------------------
    // Motion sensors
    // ------------------------------------------------------------------

    @LynxMethod
    public void isAvailable(String type, Callback callback) {
        try {
            callback.invoke(result(isAvailableSensor(type)));
        } catch (JSONException failure) {
            callback.invoke(valueError());
        }
    }

    @LynxMethod
    public void start(String type, Callback callback) {
        callback.invoke(startSensor(type));
    }

    @LynxMethod
    public void stop(String type, Callback callback) {
        callback.invoke(stopSensor(type));
    }

    @Override
    public void destroy() {
        destroyed = true;
        SensorManager manager = manager();
        if (manager != null) {
            manager.unregisterListener(this);
        }
        synchronized (registered) {
            registered.clear();
        }
        accelerometerActive = false;
        compassActive = false;
        gravitySet = false;
        geomagneticSet = false;
    }

    private String startSensor(String type) {
        if (destroyed) {
            return "Device host has been destroyed";
        }
        if (TYPE_ACCELEROMETER.equals(type)) {
            if (accelerometerActive) {
                return "";
            }
            if (!isAvailableSensor(TYPE_ACCELEROMETER)) {
                return "Accelerometer is unavailable";
            }
            accelerometerActive = true;
            reconcileRegistrations();
            return "";
        }
        if (TYPE_COMPASS.equals(type)) {
            if (compassActive) {
                return "";
            }
            if (!isAvailableSensor(TYPE_COMPASS)) {
                return "Compass is unavailable";
            }
            compassActive = true;
            reconcileRegistrations();
            return "";
        }
        return "Unknown sensor type: " + (type == null ? "" : type);
    }

    private String stopSensor(String type) {
        if (TYPE_ACCELEROMETER.equals(type)) {
            if (!accelerometerActive) {
                return "";
            }
            accelerometerActive = false;
            reconcileRegistrations();
            return "";
        }
        if (TYPE_COMPASS.equals(type)) {
            if (!compassActive) {
                return "";
            }
            compassActive = false;
            gravitySet = false;
            geomagneticSet = false;
            reconcileRegistrations();
            return "";
        }
        return "Unknown sensor type: " + (type == null ? "" : type);
    }

    private boolean isAvailableSensor(String type) {
        SensorManager manager = manager();
        if (manager == null) {
            return false;
        }
        if (TYPE_ACCELEROMETER.equals(type)) {
            return manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null;
        }
        if (TYPE_COMPASS.equals(type)) {
            return manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null
                    || (manager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD) != null
                            && manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) != null);
        }
        return false;
    }

    /**
     * Registers exactly the union of sensors the active features need. The
     * accelerometer can serve both features at once, so start/stop simply
     * re-registers the union instead of tracking per-feature ownership.
     */
    private void reconcileRegistrations() {
        SensorManager manager = manager();
        if (manager == null) {
            return;
        }
        List<Sensor> desired = new ArrayList<>();
        if (accelerometerActive) {
            Sensor sensor = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
            if (sensor != null) {
                desired.add(sensor);
            }
        }
        boolean fusion = false;
        if (compassActive) {
            Sensor rotationVector = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR);
            if (rotationVector != null) {
                desired.add(rotationVector);
            } else {
                fusion = true;
                Sensor magnetic = manager.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD);
                Sensor accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER);
                if (magnetic != null && accelerometer != null) {
                    desired.add(accelerometer);
                    desired.add(magnetic);
                }
            }
        }
        compassFusion = fusion;
        manager.unregisterListener(this);
        synchronized (registered) {
            registered.clear();
            for (Sensor sensor : desired) {
                if (manager.registerListener(this, sensor,
                        SensorManager.SENSOR_DELAY_UI, mainHandler)) {
                    registered.add(sensor);
                }
            }
        }
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        if (destroyed) {
            return;
        }
        switch (event.sensor.getType()) {
            case Sensor.TYPE_ACCELEROMETER:
                if (accelerometerActive) {
                    emitAccelerometer(event.values[0], event.values[1], event.values[2]);
                }
                if (compassFusion) {
                    System.arraycopy(event.values, 0, gravity, 0, 3);
                    gravitySet = true;
                    computeFusedCompass();
                }
                break;
            case Sensor.TYPE_MAGNETIC_FIELD:
                if (compassFusion) {
                    System.arraycopy(event.values, 0, geomagnetic, 0, 3);
                    geomagneticSet = true;
                    computeFusedCompass();
                }
                break;
            case Sensor.TYPE_ROTATION_VECTOR:
                if (compassActive && !compassFusion) {
                    SensorManager.getRotationMatrixFromVector(rotationMatrix, event.values);
                    emitCompass(azimuthOf(rotationMatrix));
                }
                break;
            default:
                break;
        }
    }

    @Override
    public void onAccuracyChanged(Sensor sensor, int accuracy) {
        if (sensor != null
                && (sensor.getType() == Sensor.TYPE_ROTATION_VECTOR
                        || sensor.getType() == Sensor.TYPE_MAGNETIC_FIELD)) {
            compassSensorAccuracy = accuracy;
        }
    }

    private void computeFusedCompass() {
        if (!gravitySet || !geomagneticSet) {
            return;
        }
        if (SensorManager.getRotationMatrix(rotationMatrix, null, gravity, geomagnetic)) {
            emitCompass(azimuthOf(rotationMatrix));
        }
    }

    /** Azimuth in degrees (0-360) relative to magnetic north, in the display's frame. */
    private float azimuthOf(float[] matrix) {
        int xAxis = SensorManager.AXIS_X;
        int yAxis = SensorManager.AXIS_Y;
        switch (displayRotation()) {
            case Surface.ROTATION_90:
                xAxis = SensorManager.AXIS_Y;
                yAxis = SensorManager.AXIS_MINUS_X;
                break;
            case Surface.ROTATION_180:
                xAxis = SensorManager.AXIS_MINUS_X;
                yAxis = SensorManager.AXIS_MINUS_Y;
                break;
            case Surface.ROTATION_270:
                xAxis = SensorManager.AXIS_MINUS_Y;
                yAxis = SensorManager.AXIS_X;
                break;
            case Surface.ROTATION_0:
            default:
                break;
        }
        SensorManager.remapCoordinateSystem(matrix, xAxis, yAxis, remappedMatrix);
        SensorManager.getOrientation(remappedMatrix, orientation);
        float azimuth = (float) Math.toDegrees(orientation[0]);
        return azimuth < 0 ? azimuth + 360f : azimuth;
    }

    private int displayRotation() {
        Activity activity = hostActivity();
        if (activity == null) {
            return Surface.ROTATION_0;
        }
        Display display;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display = activity.getDisplay();
        } else {
            display = activity.getWindowManager().getDefaultDisplay();
        }
        return display != null ? display.getRotation() : Surface.ROTATION_0;
    }

    private void emitAccelerometer(double x, double y, double z) {
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putString("type", TYPE_ACCELEROMETER);
        payload.putDouble("x", x);
        payload.putDouble("y", y);
        payload.putDouble("z", z);
        payload.putDouble("timestamp", System.currentTimeMillis());
        emit(payload);
    }

    private void emitCompass(double heading) {
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putString("type", TYPE_COMPASS);
        payload.putDouble("heading", heading);
        payload.putDouble("accuracy", accuracyDegrees(compassSensorAccuracy));
        payload.putDouble("timestamp", System.currentTimeMillis());
        emit(payload);
    }

    private void emit(JavaOnlyMap payload) {
        if (destroyed) {
            return;
        }
        mainHandler.post(() -> {
            if (destroyed) {
                return;
            }
            LynxContext context = mLynxContext;
            if (context != null) {
                context.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload));
            }
        });
    }

    @Nullable
    private SensorManager manager() {
        if (sensorManager != null) {
            return sensorManager;
        }
        Context context = mLynxContext != null ? mLynxContext : mContext;
        Context appContext = context != null ? context.getApplicationContext() : null;
        if (appContext == null) {
            return null;
        }
        sensorManager = (SensorManager) appContext.getSystemService(Context.SENSOR_SERVICE);
        return sensorManager;
    }

    // ------------------------------------------------------------------
    // Shared helpers
    // ------------------------------------------------------------------

    private void putAppVersion(JSONObject value, Context context) throws JSONException {
        try {
            PackageManager pm = context.getPackageManager();
            PackageInfo info;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                info = pm.getPackageInfo(
                        context.getPackageName(), PackageManager.PackageInfoFlags.of(0));
            } else {
                info = pm.getPackageInfo(context.getPackageName(), 0);
            }
            value.put("appVersion", info.versionName != null ? info.versionName : "");
            long build = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                    ? info.getLongVersionCode()
                    : info.versionCode;
            value.put("appBuild", String.valueOf(build));
        } catch (Throwable failure) {
            value.put("appVersion", "");
            value.put("appBuild", "");
        }
    }

    private boolean isTablet(Context context) {
        int smallestWidth = context.getResources().getConfiguration().smallestScreenWidthDp;
        return smallestWidth >= TABLET_MIN_SMALLEST_WIDTH_DP;
    }

    private boolean isFoldable(Context context) {
        // The hinge-angle sensor feature is the broadest foldable proxy that
        // does not pull in Jetpack WindowManager.
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                && context.getPackageManager()
                        .hasSystemFeature(PackageManager.FEATURE_SENSOR_HINGE_ANGLE);
    }

    @Nullable
    private DisplayMetrics screenMetrics() {
        if (mLynxContext != null) {
            DisplayMetrics metrics = mLynxContext.getScreenMetrics();
            if (metrics != null) {
                return metrics;
            }
        }
        Context context = mLynxContext != null ? mLynxContext : mContext;
        return context != null
                ? context.getResources().getDisplayMetrics()
                : Resources.getSystem().getDisplayMetrics();
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
        return context instanceof Activity ? (Activity) context : null;
    }

    @Nullable
    private Context hostContext() {
        // LynxContext is a MutableContextWrapper, so resolve the application
        // context before touching system services.
        if (mLynxContext != null) {
            return mLynxContext.getApplicationContext();
        }
        return mContext != null ? mContext.getApplicationContext() : null;
    }

    @Nullable
    private ContentResolver resolver() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        return context != null ? context.getContentResolver() : null;
    }

    private static String messageOf(Throwable failure, String fallback) {
        String message = failure.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }

    /** Estimated azimuth uncertainty in degrees; -1 when the reading is unreliable. */
    private static double accuracyDegrees(int sensorAccuracy) {
        switch (sensorAccuracy) {
            case SensorManager.SENSOR_STATUS_ACCURACY_HIGH:
                return 15;
            case SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM:
                return 30;
            case SensorManager.SENSOR_STATUS_ACCURACY_LOW:
                return 45;
            case SensorManager.SENSOR_STATUS_UNRELIABLE:
            default:
                return -1;
        }
    }

    private static String result(JSONObject value) throws JSONException {
        JSONObject envelope = new JSONObject();
        envelope.put("value", value);
        return envelope.toString();
    }

    private static String result(double value) {
        try {
            JSONObject envelope = new JSONObject();
            envelope.put("value", value);
            return envelope.toString();
        } catch (JSONException ignored) {
            return valueError();
        }
    }

    private static String result(boolean value) throws JSONException {
        JSONObject envelope = new JSONObject();
        envelope.put("value", value);
        return envelope.toString();
    }

    private static String error(String message) {
        try {
            JSONObject envelope = new JSONObject();
            envelope.put("error", message);
            return envelope.toString();
        } catch (JSONException ignored) {
            return valueError();
        }
    }

    private static JavaOnlyMap errorMap(String message) {
        JavaOnlyMap envelope = new JavaOnlyMap();
        envelope.putString("error", message);
        return envelope;
    }

    private static String valueError() {
        return "{\"error\":\"Device serialization failed\"}";
    }
}
