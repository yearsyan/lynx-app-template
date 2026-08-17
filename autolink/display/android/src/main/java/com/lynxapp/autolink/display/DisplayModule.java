package com.lynxapp.autolink.display;

import android.app.Activity;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.res.Resources;
import android.graphics.Point;
import android.os.Build;
import android.util.DisplayMetrics;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.LynxView;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * On-demand display metrics exported to Lynx as Display. All widths are
 * reported in Lynx logical pixels (physical px divided by the current
 * density), matching the unit Lynx layout consumes.
 */
@LynxNativeModule(name = DisplayModule.NAME)
public final class DisplayModule extends LynxContextModule {
    public static final String NAME = "Display";

    public DisplayModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void screenWidth(Callback callback) {
        DisplayMetrics metrics = screenMetrics();
        if (metrics == null) {
            callback.invoke(error("Display has no host context"));
            return;
        }
        callback.invoke(value(metrics.widthPixels / metrics.density));
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
        callback.invoke(value(widthPx / density));
    }

    @LynxMethod
    public void lynxViewWidth(Callback callback) {
        if (mLynxContext == null) {
            callback.invoke(error("Display has no host context"));
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
        callback.invoke(value(view.getWidth() / density));
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
        return null;
    }

    private static String value(double width) {
        try {
            JSONObject result = new JSONObject();
            result.put("value", width);
            return result.toString();
        } catch (JSONException ignored) {
            return "{\"error\":\"Display serialization failed\"}";
        }
    }

    private static String error(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message);
            return result.toString();
        } catch (JSONException ignored) {
            return "{\"error\":\"Display serialization failed\"}";
        }
    }
}
