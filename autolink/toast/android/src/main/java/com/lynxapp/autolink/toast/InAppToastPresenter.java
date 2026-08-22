package com.lynxapp.autolink.toast;

import android.app.Activity;
import android.app.Application;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.lang.ref.WeakReference;

/**
 * In-app fallback toast: the bubble is drawn inside the host Activity's own
 * window (never through the system Toast service), so it keeps the app's
 * custom styling in every system theme and still shows when the app has no
 * notification permission.
 *
 * Unlike an iOS UIWindow or a HarmonyOS OverlayManager, an Android Activity
 * window dies with the Activity, so a bubble anchored to one decor view
 * would ride out with that page's exit animation. To match the sibling
 * platforms this presenter re-anchors the bubble onto whichever Activity is
 * resumed: when the hosting page finishes, the incoming Activity adopts the
 * bubble as the transition begins, so the toast stays fixed on screen while
 * the old page animates away underneath.
 */
final class InAppToastPresenter implements Application.ActivityLifecycleCallbacks {
    private static final long FADE_IN_MS = 200L;
    private static final int BOTTOM_MARGIN_DP = 72;

    @Nullable private static InAppToastPresenter shared;

    private final Handler main = new Handler(Looper.getMainLooper());

    @Nullable private View bubble;
    @Nullable private FrameLayout.LayoutParams layout;
    @Nullable private WeakReference<Activity> host;
    private final Runnable dismissRunnable = this::dismiss;

    private InAppToastPresenter(Application application) {
        application.registerActivityLifecycleCallbacks(this);
    }

    /** Dismisses the visible bubble, if any, without touching the registration. */
    static synchronized void dismissCurrent() {
        if (shared != null) {
            shared.dismiss();
        }
    }

    /** Replaces any visible bubble and anchors the new one to the given Activity. */
    static synchronized void show(
            @NonNull Activity activity, @NonNull View newBubble, long durationMs) {
        if (activity.isDestroyed()) {
            return;
        }
        if (shared == null) {
            shared = new InAppToastPresenter(activity.getApplication());
        }
        shared.showInternal(activity, newBubble, durationMs);
    }

    private void showInternal(Activity activity, View newBubble, long durationMs) {
        dismiss();
        float density = activity.getResources().getDisplayMetrics().density;
        FrameLayout.LayoutParams layoutParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        layoutParams.bottomMargin = ToastBubble.dp(density, BOTTOM_MARGIN_DP);
        bubble = newBubble;
        layout = layoutParams;
        host = new WeakReference<>(activity);
        decor(activity).addView(newBubble, layoutParams);
        newBubble.animate().alpha(1f).setDuration(FADE_IN_MS).start();
        main.postDelayed(dismissRunnable, Math.max(durationMs, 0L));
    }

    /** Removes the active bubble immediately, wherever it is attached. */
    void dismiss() {
        main.removeCallbacks(dismissRunnable);
        View current = bubble;
        bubble = null;
        layout = null;
        host = null;
        if (current != null) {
            current.animate().cancel();
            ViewGroup parent = (ViewGroup) current.getParent();
            if (parent != null) {
                parent.removeView(current);
            }
        }
    }

    /**
     * The resumed Activity adopts the visible bubble. When the previous host
     * is finishing, its window still plays the exit transition; re-anchoring
     * here keeps the toast pinned to the screen while the old page animates
     * away underneath. The dismiss timer is untouched: the duration counts
     * from show(), as on iOS.
     */
    @Override
    public void onActivityResumed(@NonNull Activity activity) {
        View current = bubble;
        if (current == null) {
            return;
        }
        Activity hostActivity = host != null ? host.get() : null;
        if (hostActivity == activity) {
            return;
        }
        ViewGroup parent = (ViewGroup) current.getParent();
        if (parent != null) {
            parent.removeView(current);
        }
        current.animate().cancel();
        current.setAlpha(1f);
        host = new WeakReference<>(activity);
        FrameLayout.LayoutParams layoutParams =
                layout != null ? layout : defaultLayout(activity);
        decor(activity).addView(current, layoutParams);
    }

    /** The host died without a successor adopting the bubble (app exit). */
    @Override
    public void onActivityDestroyed(@NonNull Activity activity) {
        Activity hostActivity = host != null ? host.get() : null;
        if (hostActivity == activity) {
            dismiss();
        }
    }

    @Override
    public void onActivityCreated(@NonNull Activity activity, @Nullable Bundle state) {}

    @Override
    public void onActivityStarted(@NonNull Activity activity) {}

    @Override
    public void onActivityPaused(@NonNull Activity activity) {}

    @Override
    public void onActivityStopped(@NonNull Activity activity) {}

    @Override
    public void onActivitySaveInstanceState(@NonNull Activity activity, @NonNull Bundle state) {}

    private static FrameLayout.LayoutParams defaultLayout(Activity activity) {
        float density = activity.getResources().getDisplayMetrics().density;
        FrameLayout.LayoutParams layoutParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        layoutParams.bottomMargin = ToastBubble.dp(density, BOTTOM_MARGIN_DP);
        return layoutParams;
    }

    private static FrameLayout decor(Activity activity) {
        return (FrameLayout) activity.getWindow().getDecorView();
    }
}
