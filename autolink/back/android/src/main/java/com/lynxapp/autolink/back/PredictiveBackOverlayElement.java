package com.lynxapp.autolink.back;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.view.animation.DecelerateInterpolator;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.lynx.tasm.behavior.LynxContext;
import com.lynx.tasm.behavior.LynxElement;
import com.lynx.tasm.behavior.LynxProp;
import com.lynx.tasm.behavior.ui.view.AndroidView;
import com.lynx.tasm.behavior.ui.view.UIView;
import com.lynx.tasm.utils.ColorUtils;

import java.lang.ref.WeakReference;
import java.util.HashMap;
import java.util.Map;
import java.util.WeakHashMap;

/** Child-hosting target updated directly by Android's predictive Back callback. */
@LynxElement(name = PredictiveBackOverlayElement.NAME)
public final class PredictiveBackOverlayElement extends UIView {
    public static final String NAME = "predictive-back-overlay";

    private static final Map<LynxContext, Map<String, WeakReference<PredictiveBackOverlayView>>>
            TARGETS = new WeakHashMap<>();

    @Nullable private PredictiveBackOverlayView overlayView;
    @NonNull private String targetId = "";

    public PredictiveBackOverlayElement(LynxContext context) {
        super(context);
    }

    public PredictiveBackOverlayElement(LynxContext context, Object params) {
        super(context, params);
    }

    @Override
    protected AndroidView onCreateView(Context context) {
        overlayView = new PredictiveBackOverlayView(context);
        registerTarget();
        return overlayView;
    }

    @LynxProp(name = "target-id")
    public void setTargetId(@Nullable String value) {
        unregisterTarget();
        targetId = value == null ? "" : value;
        registerTarget();
    }

    @LynxProp(name = "backdrop-color")
    public void setBackdropColor(@Nullable String value) {
        PredictiveBackOverlayView view = overlayView;
        if (view == null) {
            return;
        }
        int color = 0x73000000;
        if (value != null && ColorUtils.isValid(value)) {
            color = ColorUtils.parse(value);
        }
        view.setBackdropColor(color);
    }

    @LynxProp(name = "motion")
    public void setMotion(@Nullable String value) {
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.setMotion(value);
        }
    }

    @Override
    public void destroy() {
        unregisterTarget();
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.dispose();
        }
        overlayView = null;
        super.destroy();
    }

    private void registerTarget() {
        PredictiveBackOverlayView view = overlayView;
        if (view == null || targetId.isEmpty()) {
            return;
        }
        synchronized (TARGETS) {
            TARGETS.computeIfAbsent(getLynxContext(), ignored -> new HashMap<>())
                    .put(targetId, new WeakReference<>(view));
        }
    }

    private void unregisterTarget() {
        PredictiveBackOverlayView view = overlayView;
        if (view == null || targetId.isEmpty()) {
            return;
        }
        synchronized (TARGETS) {
            Map<String, WeakReference<PredictiveBackOverlayView>> contextTargets =
                    TARGETS.get(getLynxContext());
            if (contextTargets == null) {
                return;
            }
            WeakReference<PredictiveBackOverlayView> reference = contextTargets.get(targetId);
            if (reference != null && reference.get() == view) {
                contextTargets.remove(targetId);
            }
            if (contextTargets.isEmpty()) {
                TARGETS.remove(getLynxContext());
            }
        }
    }

    @Nullable
    static PredictiveBackOverlayView findTarget(
            @Nullable LynxContext context, @NonNull String targetId) {
        if (context == null || targetId.isEmpty()) {
            return null;
        }
        synchronized (TARGETS) {
            Map<String, WeakReference<PredictiveBackOverlayView>> contextTargets =
                    TARGETS.get(context);
            WeakReference<PredictiveBackOverlayView> reference =
                    contextTargets == null ? null : contextTargets.get(targetId);
            PredictiveBackOverlayView view = reference == null ? null : reference.get();
            if (view == null && contextTargets != null) {
                contextTargets.remove(targetId);
            }
            return view != null && view.isAttachedToWindow() ? view : null;
        }
    }

    /** Root background remains fixed while dispatchDraw moves all Lynx children. */
    static final class PredictiveBackOverlayView extends AndroidView {
        private static final String MOTION_HORIZONTAL = "horizontal";
        private static final String MOTION_NONE = "none";

        private int backdropColor = 0x73000000;
        @NonNull private String motion = "sheet";
        @NonNull private String edge = "left";
        private float progress;
        private float contentTranslationX;
        private float contentTranslationY;
        @Nullable private ValueAnimator animator;
        @Nullable private Runnable animationCompletion;

        PredictiveBackOverlayView(Context context) {
            super(context);
            applyProgress(0f);
        }

        void setBackdropColor(int color) {
            backdropColor = color;
            applyProgress(progress);
        }

        void setMotion(@Nullable String value) {
            if (MOTION_HORIZONTAL.equals(value) || MOTION_NONE.equals(value)) {
                motion = value;
            } else {
                motion = "sheet";
            }
            applyProgress(progress);
        }

        void begin(@NonNull String gestureEdge) {
            cancelAnimation(true);
            edge = gestureEdge;
            applyProgress(0f);
        }

        void update(float value, @NonNull String gestureEdge) {
            edge = gestureEdge;
            applyProgress(value);
        }

        void cancel() {
            cancelAnimation(false);
            animateTo(0f, null);
        }

        void commit(@NonNull Runnable completion) {
            animateTo(1f, completion);
        }

        void dispose() {
            cancelAnimation(true);
            applyProgress(0f);
        }

        @Override
        protected void dispatchDraw(@NonNull Canvas canvas) {
            int checkpoint = canvas.save();
            canvas.translate(contentTranslationX, contentTranslationY);
            super.dispatchDraw(canvas);
            canvas.restoreToCount(checkpoint);
        }

        private void animateTo(float target, @Nullable Runnable completion) {
            cancelAnimation(false);
            float start = progress;
            if (Math.abs(start - target) < 0.001f) {
                applyProgress(target);
                if (completion != null) {
                    completion.run();
                }
                return;
            }
            animationCompletion = completion;
            ValueAnimator nextAnimator = ValueAnimator.ofFloat(start, target);
            animator = nextAnimator;
            nextAnimator.setDuration((long) (100 + 100 * Math.abs(target - start)));
            nextAnimator.setInterpolator(new DecelerateInterpolator());
            nextAnimator.addUpdateListener(
                    animation -> applyProgress((float) animation.getAnimatedValue()));
            nextAnimator.addListener(
                    new AnimatorListenerAdapter() {
                        private boolean finished;

                        @Override
                        public void onAnimationCancel(Animator animation) {
                            finishOnce(nextAnimator);
                        }

                        @Override
                        public void onAnimationEnd(Animator animation) {
                            finishOnce(nextAnimator);
                        }

                        private void finishOnce(ValueAnimator completedAnimator) {
                            if (finished) {
                                return;
                            }
                            finished = true;
                            if (animator != completedAnimator) {
                                return;
                            }
                            animator = null;
                            Runnable callback = animationCompletion;
                            animationCompletion = null;
                            if (callback != null) {
                                callback.run();
                            }
                        }
                    });
            nextAnimator.start();
        }

        private void cancelAnimation(boolean deliverCompletion) {
            ValueAnimator current = animator;
            if (current == null) {
                return;
            }
            animator = null;
            Runnable callback = animationCompletion;
            animationCompletion = null;
            current.cancel();
            if (deliverCompletion && callback != null) {
                callback.run();
            }
        }

        private void applyProgress(float value) {
            progress = Math.max(0f, Math.min(1f, value));
            if (MOTION_NONE.equals(motion)) {
                contentTranslationX = 0f;
                contentTranslationY = 0f;
            } else if (MOTION_HORIZONTAL.equals(motion)) {
                float direction = "right".equals(edge) ? -1f : 1f;
                contentTranslationX = getWidth() * progress * direction;
                contentTranslationY = 0f;
            } else {
                contentTranslationX = 0f;
                contentTranslationY = contentTravelHeight() * progress;
            }
            int alpha = Math.round(Color.alpha(backdropColor) * (1f - progress));
            setBackgroundColor(
                    Color.argb(
                            alpha,
                            Color.red(backdropColor),
                            Color.green(backdropColor),
                            Color.blue(backdropColor)));
            invalidate();
        }

        private float contentTravelHeight() {
            int contentHeight = 0;
            for (int index = 0; index < getChildCount(); index += 1) {
                contentHeight = Math.max(contentHeight, getChildAt(index).getHeight());
            }
            return contentHeight > 0 ? contentHeight : getHeight();
        }
    }
}
