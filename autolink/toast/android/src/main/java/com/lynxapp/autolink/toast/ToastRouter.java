package com.lynxapp.autolink.toast;

import android.app.Activity;
import android.view.View;

import androidx.annotation.NonNull;

/**
 * Picks the presentation channel for a toast and owns the replace semantics
 * across channels: a new toast always cancels whatever is on screen, no
 * matter which channel drew the previous one.
 *
 * Preferred channel is the system toast window (NotificationManagerService
 * token + TYPE_TOAST), which floats free of every Activity window; the
 * in-app presenter with Activity re-anchoring serves as the fallback.
 */
final class ToastRouter {
    private ToastRouter() {}

    /** Must be called on the main thread. */
    static void show(@NonNull Activity activity, @NonNull View bubble, long durationMs) {
        SystemToastPresenter.cancelCurrent();
        InAppToastPresenter.dismissCurrent();
        if (SystemToastPresenter.canUse(activity, durationMs)) {
            SystemToastPresenter.show(
                    activity,
                    bubble,
                    durationMs,
                    (view, remainingMs) ->
                            InAppToastPresenter.show(activity, view, remainingMs));
            return;
        }
        InAppToastPresenter.show(activity, bubble, durationMs);
    }
}
