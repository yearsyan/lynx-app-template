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
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.tasm.behavior.LynxContext;

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
                value.putBoolean("charging", status == BatteryManager.BATTERY_STATUS_CHARGING
                        || status == BatteryManager.BATTERY_STATUS_FULL);
            }
            JavaOnlyMap result = new JavaOnlyMap();
            result.putMap("value", value);
            callback.invoke(result);
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

    private static JavaOnlyMap error(String message) {
        JavaOnlyMap result = new JavaOnlyMap();
        result.putString("error", message);
        return result;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }
}
