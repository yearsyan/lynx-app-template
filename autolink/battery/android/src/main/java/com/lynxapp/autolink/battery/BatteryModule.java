package com.lynxapp.autolink.battery;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * On-demand battery state exported to Lynx as Battery. Reads the sticky
 * ACTION_BATTERY_CHANGED broadcast so no receiver registration or permission
 * is needed and every call reflects the current state.
 */
@LynxNativeModule(name = BatteryModule.NAME)
public final class BatteryModule extends LynxContextModule {
    public static final String NAME = "Battery";

    public BatteryModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void getInfo(Callback callback) {
        Context context = hostContext();
        if (context == null) {
            callback.invoke(error("Battery has no host context"));
            return;
        }
        Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
        try {
            JSONObject value = new JSONObject();
            if (battery == null) {
                value.put("level", JSONObject.NULL);
                value.put("charging", false);
            } else {
                int level = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                value.put("level", level >= 0 && scale > 0
                        ? Math.min(1.0, level / (double) scale)
                        : JSONObject.NULL);
                int status = battery.getIntExtra(BatteryManager.EXTRA_STATUS, -1);
                value.put("charging", status == BatteryManager.BATTERY_STATUS_CHARGING
                        || status == BatteryManager.BATTERY_STATUS_FULL);
            }
            JSONObject result = new JSONObject();
            result.put("value", value);
            callback.invoke(result.toString());
        } catch (Throwable error) {
            callback.invoke(error(messageOf(error, "Unable to read battery information")));
        }
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

    private static String error(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message);
            return result.toString();
        } catch (JSONException ignored) {
            return "{\"error\":\"Battery serialization failed\"}";
        }
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }
}
