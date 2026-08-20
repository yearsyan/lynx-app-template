package com.lynxapp.autolink.back;

import android.content.Context;
import android.content.ContextWrapper;
import android.os.Handler;
import android.os.Looper;

import androidx.activity.BackEventCompat;
import androidx.activity.OnBackPressedCallback;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.fragment.app.FragmentActivity;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.tasm.LynxView;
import com.lynx.tasm.behavior.LynxContext;

/**
 * Lifecycle-bound system Back dispatcher for the current LynxView.
 *
 * The host only needs to build the view from a FragmentActivity. AndroidX
 * owns legacy and predictive platform registration; JavaScript synchronously
 * opts this callback in or out before the next system gesture begins.
 */
@LynxNativeModule(name = BackModule.NAME)
public final class BackModule extends LynxContextModule {
    public static final String NAME = "Back";
    private static final String EVENT_NAME = "back";

    private static final String PLATFORM_ANDROID = "android";
    private static final String PHASE_START = "start";
    private static final String PHASE_PROGRESS = "progress";
    private static final String PHASE_CANCEL = "cancel";
    private static final String PHASE_COMMIT = "commit";
    private static final String SOURCE_SYSTEM = "system";
    private static final String SOURCE_GESTURE = "gesture";
    private static final String EDGE_LEFT = "left";
    private static final String EDGE_RIGHT = "right";
    private static final String EDGE_NONE = "none";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    @Nullable private final FragmentActivity activity;
    private boolean registered;
    private boolean destroyed;
    private boolean gestureStarted;
    private double lastProgress;
    private double lastTouchX;
    private double lastTouchY;
    @NonNull private String lastEdge = EDGE_NONE;

    private final OnBackPressedCallback backCallback =
            new OnBackPressedCallback(false) {
                @Override
                public void handleOnBackStarted(@NonNull BackEventCompat event) {
                    gestureStarted = true;
                    updateGesture(event);
                    emitCurrent(PHASE_START);
                }

                @Override
                public void handleOnBackProgressed(@NonNull BackEventCompat event) {
                    if (!gestureStarted) {
                        gestureStarted = true;
                        updateGesture(event);
                        emitCurrent(PHASE_START);
                    } else {
                        updateGesture(event);
                    }
                    emitCurrent(PHASE_PROGRESS);
                }

                @Override
                public void handleOnBackCancelled() {
                    cancelGesture();
                }

                @Override
                public void handleOnBackPressed() {
                    if (gestureStarted) {
                        emit(PHASE_COMMIT, 1, SOURCE_GESTURE, lastEdge,
                                lastTouchX, lastTouchY);
                        resetGesture();
                    } else {
                        emitDiscreteBack();
                    }
                }
            };

    public BackModule(LynxContext context) {
        super(context);
        activity = resolveFragmentActivity(context);
    }

    /** Enables this view's callback; a disabled callback falls through normally. */
    @LynxMethod
    public void setEnabled(boolean enabled, Callback callback) {
        mainHandler.post(() -> {
            if (destroyed) {
                callback.invoke("Back has already been destroyed");
                return;
            }
            FragmentActivity host = activity;
            if (host == null || host.isFinishing() || host.isDestroyed()) {
                callback.invoke("Back requires a usable FragmentActivity host");
                return;
            }
            if (!registered) {
                host.getOnBackPressedDispatcher().addCallback(host, backCallback);
                registered = true;
            }
            if (!enabled) {
                cancelGesture();
            }
            backCallback.setEnabled(enabled);
            callback.invoke("");
        });
    }

    @Override
    public void destroy() {
        destroyed = true;
        mainHandler.post(() -> {
            cancelGesture();
            backCallback.setEnabled(false);
            backCallback.remove();
            registered = false;
        });
    }

    private void emitDiscreteBack() {
        emit(PHASE_START, 0, SOURCE_SYSTEM, EDGE_NONE, 0, 0);
        emit(PHASE_COMMIT, 1, SOURCE_SYSTEM, EDGE_NONE, 0, 0);
    }

    private void updateGesture(BackEventCompat event) {
        lastProgress = clamp(event.getProgress());
        lastTouchX = event.getTouchX();
        lastTouchY = event.getTouchY();
        switch (event.getSwipeEdge()) {
            case BackEventCompat.EDGE_LEFT:
                lastEdge = EDGE_LEFT;
                break;
            case BackEventCompat.EDGE_RIGHT:
                lastEdge = EDGE_RIGHT;
                break;
            default:
                lastEdge = EDGE_NONE;
                break;
        }
    }

    private void emitCurrent(String phase) {
        emit(phase, lastProgress, SOURCE_GESTURE, lastEdge, lastTouchX, lastTouchY);
    }

    private void cancelGesture() {
        if (!gestureStarted) {
            return;
        }
        emitCurrent(PHASE_CANCEL);
        resetGesture();
    }

    private void resetGesture() {
        gestureStarted = false;
        lastProgress = 0;
        lastTouchX = 0;
        lastTouchY = 0;
        lastEdge = EDGE_NONE;
    }

    private void emit(
            String phase,
            double progress,
            String source,
            String edge,
            double touchX,
            double touchY) {
        LynxView lynxView = mLynxContext == null ? null : mLynxContext.getLynxView();
        if (lynxView == null) {
            return;
        }
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putString("platform", PLATFORM_ANDROID);
        payload.putString("phase", phase);
        payload.putDouble("progress", clamp(progress));
        payload.putString("source", source);
        payload.putString("edge", edge);
        payload.putDouble("touchX", touchX);
        payload.putDouble("touchY", touchY);
        lynxView.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload));
    }

    private static double clamp(double value) {
        return Math.max(0, Math.min(value, 1));
    }

    @Nullable
    private static FragmentActivity resolveFragmentActivity(@Nullable Context context) {
        Context current = context;
        while (current instanceof ContextWrapper) {
            if (current instanceof FragmentActivity) {
                return (FragmentActivity) current;
            }
            current = ((ContextWrapper) current).getBaseContext();
        }
        return current instanceof FragmentActivity ? (FragmentActivity) current : null;
    }
}
