package com.lynxapp.autolink.camera;

import android.content.Context;

import androidx.annotation.NonNull;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;
import com.lynx.tasm.behavior.LynxElement;
import com.lynx.tasm.behavior.LynxProp;
import com.lynx.tasm.behavior.LynxUIMethod;
import com.lynx.tasm.behavior.LynxUIMethodConstants;
import com.lynx.tasm.behavior.ui.LynxUI;
import com.lynx.tasm.event.LynxCustomEvent;

import java.util.HashMap;
import java.util.Map;

/** Lynx custom element that renders a live CameraX preview. */
@LynxElement(name = CameraViewElement.NAME)
public final class CameraViewElement extends LynxUI<CameraPreviewView> {
    public static final String NAME = "x-camera-view";

    public CameraViewElement(LynxContext context) {
        super(context);
    }

    public CameraViewElement(LynxContext context, Object params) {
        super(context, params);
    }

    @Override
    protected CameraPreviewView createView(Context context) {
        return new CameraPreviewView(context, new CameraPreviewView.Listener() {
            @Override
            public void onReady(Map<String, Object> detail) {
                emit("ready", detail);
            }

            @Override
            public void onStateChanged(String state) {
                Map<String, Object> detail = new HashMap<>();
                detail.put("state", state);
                emit("statechange", detail);
            }

            @Override
            public void onError(String code, String message) {
                Map<String, Object> detail = new HashMap<>();
                detail.put("code", code);
                detail.put("message", message);
                emit("error", detail);
            }

            @Override
            public void onCapture(CameraPhoto photo) {
                Map<String, Object> detail = new HashMap<>();
                detail.put("photo", photo.toMap());
                emit("capture", detail);
            }
        });
    }

    @LynxProp(name = "active", defaultBoolean = true)
    public void setActive(boolean active) {
        getView().setActive(active);
    }

    @LynxProp(name = "lens")
    public void setLens(String lens) {
        getView().setLens(lens);
    }

    @LynxProp(name = "zoom", defaultFloat = 1f)
    public void setZoom(float zoom) {
        getView().setZoom(zoom);
    }

    @LynxProp(name = "torch")
    public void setTorch(String torch) {
        getView().setTorch(torch);
    }

    @LynxProp(name = "flash")
    public void setFlash(String flash) {
        getView().setFlash(flash);
    }

    @LynxProp(name = "exposure-compensation", defaultFloat = 0f)
    public void setExposureCompensation(float value) {
        getView().setExposureCompensation(value);
    }

    @LynxProp(name = "photo-quality", defaultInt = 92)
    public void setPhotoQuality(int value) {
        getView().setPhotoQuality(value);
    }

    @LynxProp(name = "mirror-photo", defaultBoolean = true)
    public void setMirrorPhoto(boolean value) {
        getView().setMirrorPhoto(value);
    }

    @LynxProp(name = "preview-fit")
    public void setPreviewFit(String value) {
        getView().setPreviewFit(value);
    }

    @LynxUIMethod
    public void capture(ReadableMap params, Callback callback) {
        getView().capture(new CameraPreviewView.OperationCallback<CameraPhoto>() {
            @Override
            public void onSuccess(CameraPhoto photo) {
                callback.invoke(LynxUIMethodConstants.SUCCESS, photo.toMap());
            }

            @Override
            public void onFailure(String message) {
                callback.invoke(LynxUIMethodConstants.INVALID_STATE_ERROR, message);
            }
        });
    }

    @LynxUIMethod
    public void focusAtPoint(ReadableMap params, Callback callback) {
        if (params == null
                || !params.hasKey("x")
                || !params.hasKey("y")) {
            callback.invoke(
                    LynxUIMethodConstants.PARAM_INVALID,
                    "focusAtPoint requires normalized x and y values");
            return;
        }
        float x = (float) params.getDouble("x", -1);
        float y = (float) params.getDouble("y", -1);
        if (!Float.isFinite(x) || !Float.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) {
            callback.invoke(
                    LynxUIMethodConstants.PARAM_INVALID,
                    "Camera focus coordinates must be in [0, 1]");
            return;
        }
        getView().focusAtPoint(x, y, new CameraPreviewView.OperationCallback<Void>() {
            @Override
            public void onSuccess(Void ignored) {
                callback.invoke(LynxUIMethodConstants.SUCCESS, new JavaOnlyMap());
            }

            @Override
            public void onFailure(String message) {
                callback.invoke(LynxUIMethodConstants.INVALID_STATE_ERROR, message);
            }
        });
    }

    private void emit(String name, @NonNull Map<String, Object> detail) {
        getLynxContext().getEventEmitter().sendCustomEvent(
                new LynxCustomEvent(getSign(), name, detail));
    }

    @Override
    public void destroy() {
        getView().dispose();
        super.destroy();
    }
}
