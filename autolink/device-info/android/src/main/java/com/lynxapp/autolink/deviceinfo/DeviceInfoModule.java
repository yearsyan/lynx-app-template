package com.lynxapp.autolink.deviceinfo;

import android.content.Context;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Locale;

/**
 * Static device and application facts exported to Lynx as DeviceInfo.
 * All values are read on demand so configuration changes (locale,
 * multi-window) are reflected without a restart.
 */
@LynxNativeModule(name = DeviceInfoModule.NAME)
public final class DeviceInfoModule extends LynxContextModule {
    public static final String NAME = "DeviceInfo";
    private static final int TABLET_MIN_SMALLEST_WIDTH_DP = 600;

    public DeviceInfoModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void getInfo(Callback callback) {
        Context context = hostContext();
        if (context == null) {
            callback.invoke(error("DeviceInfo has no host context"));
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
            JSONObject result = new JSONObject();
            result.put("value", value);
            callback.invoke(result.toString());
        } catch (Throwable error) {
            callback.invoke(error(messageOf(error, "Unable to read device information")));
        }
    }

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
        } catch (Throwable error) {
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
            return "{\"error\":\"DeviceInfo serialization failed\"}";
        }
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }
}
