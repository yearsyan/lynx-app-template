package com.lynxapp.autolink.navigation;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.net.Uri;
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
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.LynxView;
import com.lynx.tasm.behavior.LynxContext;

/**
 * Route navigation and Back interception exported to Lynx as Navigation.
 *
 * open/close delegate to the host-installed {@link LynxRouteHandler};
 * openURL resolves the URL through the system (any app that registered the
 * scheme can handle it, including this app's own scheme pages). setEnabled
 * and configure drive the lifecycle-bound Back dispatcher with an optional
 * native animation target.
 */
@LynxNativeModule(name = NavigationModule.NAME)
public final class NavigationModule extends LynxContextModule {
    public static final String NAME = "Navigation";
    public static final String ANIMATION_DEFAULT = "default";
    public static final String ANIMATION_FADE = "fade";
    public static final String ANIMATION_NONE = "none";
    public static final String ANIMATION_PRESENT = "present";
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

    private static volatile LynxRouteHandler routeHandler;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    @Nullable private final FragmentActivity activity;
    private boolean registered;
    private boolean destroyed;
    private boolean desiredEnabled;
    private long configuredRevision;
    @NonNull private String configuredInterceptorId = "";
    @NonNull private String configuredTargetId = "";

    private boolean gestureStarted;
    private boolean gestureFinishing;
    private long nextGestureId;
    private long gestureId;
    @NonNull private String gestureInterceptorId = "";
    @Nullable
    private PredictiveBackOverlayElement.PredictiveBackOverlayView gestureTarget;
    private double lastProgress;
    private double lastTouchX;
    private double lastTouchY;
    @NonNull private String lastEdge = EDGE_NONE;

    private final OnBackPressedCallback backCallback =
            new OnBackPressedCallback(false) {
                @Override
                public void handleOnBackStarted(@NonNull BackEventCompat event) {
                    if (gestureStarted || gestureFinishing) {
                        return;
                    }
                    updateGesture(event);
                    beginGesture(SOURCE_GESTURE);
                }

                @Override
                public void handleOnBackProgressed(@NonNull BackEventCompat event) {
                    if (gestureFinishing) {
                        return;
                    }
                    updateGesture(event);
                    if (!gestureStarted) {
                        beginGesture(SOURCE_GESTURE);
                    }
                    PredictiveBackOverlayElement.PredictiveBackOverlayView target =
                            gestureTarget;
                    if (target != null) {
                        target.update((float) lastProgress, lastEdge);
                    } else {
                        emitCurrent(PHASE_PROGRESS, SOURCE_GESTURE);
                    }
                }

                @Override
                public void handleOnBackCancelled() {
                    cancelGesture(true);
                }

                @Override
                public void handleOnBackPressed() {
                    if (gestureStarted) {
                        commitGesture(SOURCE_GESTURE);
                    } else {
                        emitDiscreteBack();
                    }
                }
            };

    public NavigationModule(LynxContext context) {
        super(context);
        activity = resolveFragmentActivity(context);
    }

    /** Installs the host navigation delegate used by {@code open}/{@code close}. */
    public static void setRouteHandler(@Nullable LynxRouteHandler handler) {
        routeHandler = handler;
    }

    public static boolean isLynxRouteAnimation(String value) {
        return ANIMATION_DEFAULT.equals(value) || ANIMATION_FADE.equals(value)
                || ANIMATION_NONE.equals(value) || ANIMATION_PRESENT.equals(value);
    }

    @LynxMethod
    public void open(ReadableMap options, Callback callback) {
        LynxRouteHandler handler = routeHandler;
        Activity host = resolveActivity();
        if (handler == null || host == null) {
            callback.invoke("Navigation has no Activity host");
            return;
        }
        handler.open(host, options, callback);
    }

    @LynxMethod
    public void close(Callback callback) {
        LynxRouteHandler handler = routeHandler;
        Activity host = resolveActivity();
        if (handler == null || host == null) {
            callback.invoke("Navigation has no Activity host");
            return;
        }
        handler.close(host, callback);
    }

    @LynxMethod
    public void openForResult(ReadableMap options, Callback callback) {
        LynxRouteHandler handler = routeHandler;
        Activity host = resolveActivity();
        if (handler == null || host == null) {
            callback.invoke(LynxRouteHandler.RouteResultEnvelope.error(
                    "Navigation has no Activity host"));
            return;
        }
        handler.openForResult(host, options, callback);
    }

    @LynxMethod
    public void closeWithResult(ReadableMap result, Callback callback) {
        LynxRouteHandler handler = routeHandler;
        Activity host = resolveActivity();
        if (handler == null || host == null) {
            callback.invoke("Navigation has no Activity host");
            return;
        }
        handler.closeWithResult(host, result, callback);
    }

    @LynxMethod
    public void openURL(String url, Callback callback) {
        Uri uri = url == null ? Uri.EMPTY : Uri.parse(url);
        if (url == null || url.trim().isEmpty() || uri.getScheme() == null
                || !url.equals(url.trim())) {
            callback.invoke("Invalid URL: " + url);
            return;
        }
        Activity host = resolveActivity();
        Context context = host != null
                ? host
                : mLynxContext != null ? mLynxContext.getApplicationContext() : mContext;
        if (context == null) {
            callback.invoke("Navigation has no host context");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_VIEW, uri);
        if (host == null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        mainHandler.post(() -> {
            try {
                context.startActivity(intent);
                callback.invoke("");
            } catch (ActivityNotFoundException error) {
                callback.invoke("No activity found for URL: " + url);
            } catch (Throwable error) {
                callback.invoke(error.getMessage() != null
                        ? error.getMessage()
                        : "Unable to open URL");
            }
        });
    }

    /** Compatibility switch for headless consumers that do not use backStack. */
    @LynxMethod
    public void setEnabled(boolean enabled, Callback callback) {
        mainHandler.post(() -> {
            configuredRevision += 1;
            configuredInterceptorId = "";
            configuredTargetId = "";
            desiredEnabled = enabled;
            if (!enabled) {
                cancelGesture(true);
            }
            applyDesiredInterception(callback);
        });
    }

    /** Atomically installs the complete top-of-stack snapshot from TypeScript. */
    @LynxMethod
    public void configure(
            boolean enabled,
            String interceptorId,
            String targetId,
            double revision,
            Callback callback) {
        mainHandler.post(() -> {
            if (destroyed) {
                callback.invoke("Navigation has already been destroyed");
                return;
            }
            long nextRevision = Math.max(0, (long) revision);
            if (nextRevision < configuredRevision) {
                callback.invoke("");
                return;
            }
            configuredRevision = nextRevision;
            desiredEnabled = enabled;
            configuredInterceptorId = interceptorId == null ? "" : interceptorId;
            configuredTargetId = targetId == null ? "" : targetId;
            // Keep the callback installed until the gesture that captured the
            // previous snapshot terminates. The next gesture gets this config.
            if (gestureStarted || gestureFinishing) {
                callback.invoke("");
                return;
            }
            applyDesiredInterception(callback);
        });
    }

    @Override
    public void destroy() {
        destroyed = true;
        mainHandler.post(() -> {
            cancelGesture(false);
            desiredEnabled = false;
            backCallback.setEnabled(false);
            backCallback.remove();
            registered = false;
        });
    }

    private void emitDiscreteBack() {
        lastProgress = 0;
        lastTouchX = 0;
        lastTouchY = 0;
        lastEdge = EDGE_NONE;
        beginGesture(SOURCE_SYSTEM);
        commitGesture(SOURCE_SYSTEM);
    }

    private void beginGesture(@NonNull String source) {
        gestureStarted = true;
        gestureFinishing = false;
        gestureId = ++nextGestureId;
        gestureInterceptorId = configuredInterceptorId;
        gestureTarget = PredictiveBackOverlayElement.findTarget(
                mLynxContext, configuredTargetId);
        PredictiveBackOverlayElement.PredictiveBackOverlayView target = gestureTarget;
        if (target != null) {
            target.begin(lastEdge);
            target.update((float) lastProgress, lastEdge);
        }
        emitCurrent(PHASE_START, source);
    }

    private void commitGesture(@NonNull String source) {
        if (!gestureStarted || gestureFinishing) {
            return;
        }
        PredictiveBackOverlayElement.PredictiveBackOverlayView target = gestureTarget;
        if (target == null) {
            emit(PHASE_COMMIT, 1, source, lastEdge, lastTouchX, lastTouchY);
            resetGesture();
            applyDesiredInterception(null);
            return;
        }

        gestureFinishing = true;
        long finishingGestureId = gestureId;
        target.commit(() -> {
            if (destroyed || !gestureStarted || gestureId != finishingGestureId) {
                return;
            }
            emit(PHASE_COMMIT, 1, source, lastEdge, lastTouchX, lastTouchY);
            resetGesture();
            applyDesiredInterception(null);
        });
    }

    private void cancelGesture(boolean emitEvent) {
        if (!gestureStarted) {
            return;
        }
        PredictiveBackOverlayElement.PredictiveBackOverlayView target = gestureTarget;
        if (target != null) {
            target.cancel();
        }
        if (emitEvent) {
            emitCurrent(PHASE_CANCEL, SOURCE_GESTURE);
        }
        resetGesture();
        if (!destroyed) {
            applyDesiredInterception(null);
        }
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

    private void emitCurrent(@NonNull String phase, @NonNull String source) {
        emit(phase, lastProgress, source, lastEdge, lastTouchX, lastTouchY);
    }

    private void resetGesture() {
        gestureStarted = false;
        gestureFinishing = false;
        gestureTarget = null;
        gestureInterceptorId = "";
        gestureId = 0;
        lastProgress = 0;
        lastTouchX = 0;
        lastTouchY = 0;
        lastEdge = EDGE_NONE;
    }

    private void applyDesiredInterception(@Nullable Callback callback) {
        if (destroyed) {
            if (callback != null) {
                callback.invoke("Navigation has already been destroyed");
            }
            return;
        }
        FragmentActivity host = activity;
        if (host == null || host.isFinishing() || host.isDestroyed()) {
            if (callback != null) {
                callback.invoke("Navigation requires a usable FragmentActivity host");
            }
            return;
        }
        if (!registered) {
            host.getOnBackPressedDispatcher().addCallback(host, backCallback);
            registered = true;
        }
        backCallback.setEnabled(desiredEnabled);
        if (callback != null) {
            callback.invoke("");
        }
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
        payload.putString("interceptorId", gestureInterceptorId);
        payload.putDouble("gestureId", gestureId);
        lynxView.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload));
    }

    private static double clamp(double value) {
        return Math.max(0, Math.min(value, 1));
    }

    /**
     * Walks from the Lynx context to the hosting Activity. A LynxView is
     * built with its Activity as the base context, so the wrapper chain
     * bottomes out there; null means the route cannot be presented.
     */
    @Nullable
    private Activity resolveActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context != null) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            if (!(context instanceof ContextWrapper)) {
                return null;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
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
