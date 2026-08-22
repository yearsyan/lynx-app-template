package com.lynxapp.autolink.toast;

import android.content.Context;
import android.graphics.PixelFormat;
import android.os.Binder;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.Parcel;
import android.os.RemoteException;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;
import java.lang.reflect.Proxy;

/**
 * System-channel toast: replicates what the framework's Toast.TN does, but
 * with the app's custom bubble. The view is added as a TYPE_TOAST window
 * backed by a window token that NotificationManagerService (system_server)
 * hands out, so the window belongs to no Activity: page exit transitions
 * never carry the toast away, and it stays fixed on screen exactly like the
 * window-level toasts on iOS/HarmonyOS.
 *
 * INotificationManager / ITransientNotification are non-SDK interfaces, so
 * every step is reflective and any failure degrades to the in-app presenter
 * via {@link Handover}. Known signature differences across releases
 * (Android 12 added an IBinder windowToken parameter; newer releases added
 * isUiContext/displayId) are absorbed by matching parameter types instead
 * of a fixed signature.
 *
 * Limits of the channel, all covered by the fallback: NMS refuses toasts
 * while the app is backgrounded or the package is suspended (enqueueToast
 * then returns false — detected and handed over), and it only offers SHORT
 * (2s) / LONG (3.5s) windows, so durations beyond LONG stay in-app.
 */
final class SystemToastPresenter {
    private static final String TAG = "LynxSystemToast";
    private static final String TN_DESCRIPTOR = "android.app.ITransientNotification";
    /** AIDL transaction codes: show() is method #1, hide() is method #2. */
    private static final int TRANSACTION_SHOW = IBinder.FIRST_CALL_TRANSACTION;
    private static final int TRANSACTION_HIDE = IBinder.FIRST_CALL_TRANSACTION + 1;

    private static final int LENGTH_SHORT = 0;
    private static final int LENGTH_LONG = 1;
    /** NMS auto-hide delays behind LENGTH_SHORT / LENGTH_LONG. */
    private static final long SHORT_DELAY_MS = 2000L;
    private static final long LONG_DELAY_MS = 3500L;

    private static final long FADE_IN_MS = 200L;
    private static final int BOTTOM_MARGIN_DP = 72;

    private enum ChannelState { UNKNOWN, AVAILABLE, UNAVAILABLE }

    private static final Handler MAIN = new Handler(Looper.getMainLooper());

    private static ChannelState state = ChannelState.UNKNOWN;
    @Nullable private static Object notificationManager;
    @Nullable private static Method enqueueToastMethod;
    @Nullable private static Method cancelToastMethod;
    @Nullable private static Class<?> tnInterface;

    /** The one toast visible at a time; a new show replaces it. */
    @Nullable private static View currentView;
    @Nullable private static WindowManager currentWindowManager;
    @Nullable private static Object currentCallback;
    @Nullable private static IBinder currentServiceToken;
    @Nullable private static String currentPackage;
    @Nullable private static Runnable currentDismiss;
    @Nullable private static Handover currentHandover;
    private static long currentShownAtMs;
    private static long currentDurationMs;

    private SystemToastPresenter() {}

    /**
     * Called when the system channel fails after show() already returned
     * success (no token, WMS rejection). Ownership of the view moves to the
     * in-app presenter, which re-anchors it for the remaining duration.
     */
    interface Handover {
        void onSystemChannelFailed(@NonNull View view, long remainingMs);
    }

    static synchronized boolean canUse(@NonNull Context context, long durationMs) {
        if (durationMs > LONG_DELAY_MS) {
            // NMS only offers 2s/3.5s windows; longer toasts stay in-app so
            // the duration contract keeps millisecond accuracy.
            return false;
        }
        if (state == ChannelState.UNKNOWN) {
            state = prepare() ? ChannelState.AVAILABLE : ChannelState.UNAVAILABLE;
        }
        return state == ChannelState.AVAILABLE;
    }

    /** Resolves the notification service and the toast methods reflectively. */
    private static boolean prepare() {
        try {
            Class<?> serviceManager = Class.forName("android.os.ServiceManager");
            IBinder binder = (IBinder) serviceManager
                    .getMethod("getService", String.class)
                    .invoke(null, "notification");
            if (binder == null) {
                return false;
            }
            Class<?> stub = Class.forName("android.app.INotificationManager$Stub");
            Object service = stub.getMethod("asInterface", IBinder.class).invoke(null, binder);
            if (service == null) {
                return false;
            }
            Class<?> nmInterface = Class.forName("android.app.INotificationManager");
            tnInterface = Class.forName(TN_DESCRIPTOR);
            Method enqueue = null;
            Method cancel = null;
            for (Method method : nmInterface.getMethods()) {
                if (enqueue == null
                        && method.getName().equals("enqueueToast")
                        && canFillEnqueue(method.getParameterTypes())) {
                    enqueue = method;
                }
                if (cancel == null
                        && method.getName().equals("cancelToast")
                        && canFillCancel(method.getParameterTypes())) {
                    cancel = method;
                }
            }
            if (enqueue == null) {
                return false;
            }
            notificationManager = service;
            enqueueToastMethod = enqueue;
            cancelToastMethod = cancel; // May stay null; cancellation is best-effort hygiene.
            return true;
        } catch (Throwable error) {
            Log.w(TAG, "System toast channel unavailable", error);
            return false;
        }
    }

    /**
     * enqueueToast(String, [IBinder], ITransientNotification, int duration,
     * [boolean isUiContext, int displayId] on newer releases).
     */
    private static boolean canFillEnqueue(Class<?>[] types) {
        boolean hasString = false;
        boolean hasCallback = false;
        boolean hasDuration = false;
        for (Class<?> type : types) {
            if (type == String.class) {
                hasString = true;
            } else if (type == IBinder.class) {
                // Caller-side window token (Android 12+); filled with a Binder.
            } else if (tnInterface.isAssignableFrom(type)) {
                hasCallback = true;
            } else if (type == int.class) {
                // duration, displayId, ... — extra ints are filled with 0
                // (DEFAULT_DISPLAY); the duration must come first.
                if (!hasDuration) {
                    hasDuration = true;
                }
            } else if (type == boolean.class) {
                // isUiContext: the toast always originates from a UI context.
            } else {
                return false; // Unknown parameter type: leave this overload alone.
            }
        }
        return hasString && hasCallback && hasDuration;
    }

    /** cancelToast(String, [IBinder or ITransientNotification]). */
    private static boolean canFillCancel(Class<?>[] types) {
        boolean hasString = false;
        for (Class<?> type : types) {
            if (type == String.class) {
                hasString = true;
            } else if (type == IBinder.class) {
                // Caller-side token (Android 12+) or plain client binder.
            } else if (tnInterface.isAssignableFrom(type)) {
                // Legacy releases match the record by callback object.
            } else {
                return false;
            }
        }
        return hasString;
    }

    private static Object[] buildArgs(
            @NonNull Method method,
            @NonNull String pkg,
            @Nullable IBinder serviceToken,
            @Nullable Object callbackProxy,
            int lengthParam) {
        Class<?>[] types = method.getParameterTypes();
        Object[] args = new Object[types.length];
        boolean stringSeen = false;
        boolean durationSeen = false;
        for (int i = 0; i < types.length; i++) {
            Class<?> type = types[i];
            if (type == String.class) {
                // First String is the package; a second one (attribution tag)
                // is nullable.
                args[i] = stringSeen ? null : pkg;
                stringSeen = true;
            } else if (type == IBinder.class) {
                args[i] = serviceToken;
            } else if (tnInterface != null && tnInterface.isAssignableFrom(type)) {
                args[i] = callbackProxy;
            } else if (type == int.class) {
                // The first int is the duration (LENGTH_SHORT/LONG); any
                // further ints (displayId, ...) get 0 = DEFAULT_DISPLAY.
                args[i] = durationSeen ? 0 : lengthParam;
                durationSeen = true;
            } else if (type == boolean.class) {
                // isUiContext: the toast always originates from a UI context.
                args[i] = Boolean.TRUE;
            }
        }
        return args;
    }

    /** Enqueues the bubble through NMS. Runs on the main thread. */
    static synchronized void show(
            @NonNull Context context,
            @NonNull View view,
            long durationMs,
            @NonNull Handover handover) {
        Context app = context.getApplicationContext();
        cancelCurrent();

        currentView = view;
        currentWindowManager = (WindowManager) app.getSystemService(Context.WINDOW_SERVICE);
        currentHandover = handover;
        currentPackage = app.getPackageName();
        currentDurationMs = durationMs;
        currentShownAtMs = SystemClock.uptimeMillis();
        currentServiceToken = new Binder();

        FakeBinder fakeBinder = new FakeBinder(view);
        Object proxy = Proxy.newProxyInstance(
                tnInterface.getClassLoader(),
                new Class<?>[] {tnInterface, android.os.IInterface.class},
                new CallbackProxyHandler(fakeBinder));
        currentCallback = proxy;

        // The NMS window only needs to outlive the requested duration; our
        // own timer removes the view at exactly durationMs.
        int lengthParam = durationMs <= SHORT_DELAY_MS ? LENGTH_SHORT : LENGTH_LONG;
        currentDismiss = () -> removeCurrent(true);
        MAIN.postDelayed(currentDismiss, durationMs);

        try {
            Object[] args = buildArgs(
                    enqueueToastMethod, currentPackage, currentServiceToken, proxy, lengthParam);
            Object result = enqueueToastMethod.invoke(notificationManager, args);
            if (Boolean.FALSE.equals(result)) {
                // NMS refused the toast: package suspended, app backgrounded,
                // or queue overflow. Hand the view to the in-app channel.
                Log.w(TAG, "NotificationManagerService refused the toast");
                failAndHandover();
                return;
            }
        } catch (Throwable error) {
            Log.w(TAG, "enqueueToast failed", error);
            failAndHandover();
        }
    }

    /** Cancels the visible system toast, if any. Safe no-op otherwise. */
    static synchronized void cancelCurrent() {
        if (currentView != null || currentCallback != null) {
            removeCurrent(true);
        }
    }

    /** NMS delivered the window token; attach the bubble above everything. */
    private static synchronized void onShow(@NonNull FakeBinder source, @Nullable IBinder token) {
        View view = currentView;
        if (view == null || source.view != view) {
            return; // Stale callback from a replaced toast.
        }
        WindowManager windowManager = currentWindowManager;
        if (token == null || windowManager == null) {
            failAndHandover();
            return;
        }
        float density = view.getResources().getDisplayMetrics().density;
        WindowManager.LayoutParams layout = new WindowManager.LayoutParams();
        layout.type = WindowManager.LayoutParams.TYPE_TOAST;
        layout.token = token;
        layout.format = PixelFormat.TRANSLUCENT;
        layout.flags = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL;
        layout.gravity = Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL;
        layout.y = ToastBubble.dp(density, BOTTOM_MARGIN_DP);
        layout.width = WindowManager.LayoutParams.WRAP_CONTENT;
        layout.height = WindowManager.LayoutParams.WRAP_CONTENT;
        layout.packageName = currentPackage;
        try {
            windowManager.addView(view, layout);
            view.animate().alpha(1f).setDuration(FADE_IN_MS).start();
        } catch (Throwable error) {
            Log.w(TAG, "Unable to attach the system toast window", error);
            failAndHandover();
        }
    }

    /** NMS hid the toast (timeout or explicit cancel); the view goes with it. */
    private static synchronized void onHide(@NonNull FakeBinder source) {
        if (currentView == null || source.view != currentView) {
            return;
        }
        removeCurrent(false);
    }

    private static void failAndHandover() {
        Handover handover = currentHandover;
        View view = currentView;
        long elapsed = SystemClock.uptimeMillis() - currentShownAtMs;
        long remaining = currentDurationMs - elapsed;
        removeCurrent(true);
        if (handover != null && view != null && remaining > 0L) {
            handover.onSystemChannelFailed(view, remaining);
        }
    }

    private static void removeCurrent(boolean cancelInService) {
        View view = currentView;
        WindowManager windowManager = currentWindowManager;
        Object callback = currentCallback;
        IBinder serviceToken = currentServiceToken;
        String pkg = currentPackage;
        Runnable dismiss = currentDismiss;

        currentView = null;
        currentWindowManager = null;
        currentCallback = null;
        currentServiceToken = null;
        currentPackage = null;
        currentDismiss = null;
        currentHandover = null;

        if (dismiss != null) {
            MAIN.removeCallbacks(dismiss);
        }
        if (view != null) {
            view.animate().cancel();
            if (view.getParent() != null && windowManager != null) {
                try {
                    windowManager.removeViewImmediate(view);
                } catch (Throwable ignored) {
                    // The token may already be gone; the view dies with it.
                }
            }
        }
        if (cancelInService && callback != null && cancelToastMethod != null) {
            try {
                Object[] args = buildArgs(cancelToastMethod, pkg, serviceToken, callback, 0);
                cancelToastMethod.invoke(notificationManager, args);
            } catch (Throwable ignored) {
                // The record times out on its own shortly.
            }
        }
    }

    /**
     * Stands in for the hidden ITransientNotification.Stub: NMS calls back
     * into this binder, and we only care about show(IBinder) and hide().
     */
    private static final class FakeBinder extends Binder {
        final View view;

        FakeBinder(View view) {
            this.view = view;
        }

        @Override
        protected boolean onTransact(
                int code, @NonNull Parcel data, @Nullable Parcel reply, int flags)
                throws RemoteException {
            try {
                if (code == TRANSACTION_SHOW) {
                    data.enforceInterface(TN_DESCRIPTOR);
                    final IBinder token = readWindowToken(data);
                    MAIN.post(() -> onShow(this, token));
                    return true;
                }
                if (code == TRANSACTION_HIDE) {
                    MAIN.post(() -> onHide(this));
                    return true;
                }
            } catch (Throwable ignored) {
                // Fall through to the default handling.
            }
            return super.onTransact(code, data, reply, flags);
        }
    }

    /** show(IBinder) marshals the NMS window token; old releases omit it. */
    @Nullable
    private static IBinder readWindowToken(Parcel data) {
        try {
            return data.readStrongBinder();
        } catch (Throwable ignored) {
            return null;
        }
    }

    /**
     * Lets a dynamic proxy pose as ITransientNotification during marshalling:
     * Parcel.writeStrongInterface only needs asBinder() (and the descriptor).
     */
    private static final class CallbackProxyHandler implements InvocationHandler {
        private final IBinder binder;

        CallbackProxyHandler(IBinder binder) {
            this.binder = binder;
        }

        @Override
        public Object invoke(Object proxy, Method method, Object[] args) {
            switch (method.getName()) {
                case "asBinder":
                    return binder;
                case "getInterfaceDescriptor":
                    return TN_DESCRIPTOR;
                case "toString":
                    return "LynxSystemToastCallback";
                case "hashCode":
                    return System.identityHashCode(proxy);
                case "equals":
                    return proxy == args[0];
                default:
                    Class<?> returnType = method.getReturnType();
                    if (returnType == boolean.class) {
                        return false;
                    }
                    if (returnType == int.class) {
                        return 0;
                    }
                    if (returnType == long.class) {
                        return 0L;
                    }
                    return null;
            }
        }
    }
}
