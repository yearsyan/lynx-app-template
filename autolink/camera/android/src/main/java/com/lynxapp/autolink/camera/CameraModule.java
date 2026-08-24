package com.lynxapp.autolink.camera;

import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

/** Opens the user-visible platform camera and returns a cache JPEG. */
@LynxNativeModule(name = CameraModule.NAME)
public final class CameraModule extends LynxContextModule {
    public static final String NAME = "Camera";

    private final Context applicationContext;

    public CameraModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void takePhoto(ReadableMap options, Callback callback) {
        String lens = options == null ? "back" : options.getString("lens", "back");
        if (!"back".equals(lens) && !"front".equals(lens)) {
            callback.invoke(CameraCallbackStore.errorJSON("Camera lens must be back or front"));
            return;
        }
        if (!CameraCallbackStore.begin(callback)) {
            callback.invoke(CameraCallbackStore.outcomeJSON(
                    "busy", null, "Another system camera request is already active"));
            return;
        }

        new Handler(Looper.getMainLooper()).post(() -> {
            try {
                Intent intent = new Intent(applicationContext, CameraCaptureActivity.class);
                intent.putExtra(CameraCaptureActivity.EXTRA_LENS, lens);
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
                applicationContext.startActivity(intent);
            } catch (Throwable error) {
                CameraCallbackStore.fail(error, "Unable to open the system camera");
            }
        });
    }
}
