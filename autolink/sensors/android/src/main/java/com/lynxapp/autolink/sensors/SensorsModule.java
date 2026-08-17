package com.lynxapp.autolink.sensors;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.view.Display;
import android.view.Surface;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

/**
 * Streaming motion sensors exported to Lynx as Sensors. Readings flow back
 * through the module's {@link LynxContext} as `sensors` global events — the
 * same channel the WebSocket module uses — so no callback is held beyond a
 * command ack. The JS bridge refcounts listeners and only keeps a sensor
 * registered while at least one observer is attached.
 *
 * Accelerometer reports m/s^2 including gravity on every platform. Compass
 * reports the magnetic azimuth in degrees (0-360) with an accuracy estimate
 * in degrees (-1 when unreliable), preferring the rotation-vector sensor and
 * falling back to accelerometer + magnetometer fusion.
 */
@LynxNativeModule(name = SensorsModule.NAME)
public final class SensorsModule extends LynxContextModule implements SensorEventListener {
    public static final String NAME = "Sensors";
    public static final String EVENT_NAME = "sensors";

    private static final String TYPE_ACCELEROMETER = "accelerometer";
    private static final String TYPE_COMPASS = "compass";

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

    public SensorsModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void isAvailable(String type, Callback callback) {
        try {
            callback.invoke(value(isAvailableSensor(type)));
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
            return "Sensors host has been destroyed";
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

    private void emitError(String type, String message) {
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putString("type", type);
        payload.putString("error", message);
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

    private static String value(boolean available) throws JSONException {
        JSONObject result = new JSONObject();
        result.put("value", available);
        return result.toString();
    }

    private static String valueError() {
        return "{\"error\":\"Sensors serialization failed\"}";
    }
}
