package com.lynxapp.autolink.haptics;

import android.content.Context;
import android.os.Build;
import android.os.VibrationEffect;
import android.os.Vibrator;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

/** One-shot impact haptics mapped to predefined vibration effects. */
@LynxNativeModule(name = HapticsModule.NAME)
public final class HapticsModule extends LynxContextModule {
    public static final String NAME = "Haptics";
    private static final String IMPACT_LIGHT = "light";
    private static final String IMPACT_MEDIUM = "medium";
    private static final String IMPACT_HEAVY = "heavy";
    private static final long DURATION_LIGHT_MS = 15L;
    private static final long DURATION_MEDIUM_MS = 30L;
    private static final long DURATION_HEAVY_MS = 60L;

    public HapticsModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void impact(String style, Callback callback) {
        Vibrator vibrator = vibrator();
        if (vibrator == null || !vibrator.hasVibrator()) {
            callback.invoke("Vibrator is not available on this device");
            return;
        }
        if (IMPACT_LIGHT.equals(style)) {
            vibrate(vibrator, VibrationEffect.EFFECT_TICK, DURATION_LIGHT_MS);
        } else if (IMPACT_MEDIUM.equals(style)) {
            vibrate(vibrator, VibrationEffect.EFFECT_CLICK, DURATION_MEDIUM_MS);
        } else if (IMPACT_HEAVY.equals(style)) {
            vibrate(vibrator, VibrationEffect.EFFECT_HEAVY_CLICK, DURATION_HEAVY_MS);
        } else {
            callback.invoke("Invalid haptic impact style: " + style);
            return;
        }
        callback.invoke("");
    }

    @Nullable
    private Vibrator vibrator() {
        // LynxContext is a MutableContextWrapper, so resolve the application
        // context before touching system services.
        Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
        if (context == null) {
            context = mContext != null ? mContext.getApplicationContext() : null;
        }
        if (context == null) {
            return null;
        }
        return (Vibrator) context.getSystemService(Context.VIBRATOR_SERVICE);
    }

    private void vibrate(Vibrator vibrator, int predefinedEffect, long fallbackDurationMs) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            vibrator.vibrate(VibrationEffect.createPredefined(predefinedEffect));
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(
                    VibrationEffect.createOneShot(
                            fallbackDurationMs,
                            VibrationEffect.DEFAULT_AMPLITUDE));
        } else {
            vibrator.vibrate(fallbackDurationMs);
        }
    }
}
