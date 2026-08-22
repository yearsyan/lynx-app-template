package com.lynxapp.autolink.navigation;

import android.animation.Animator;
import android.animation.AnimatorListenerAdapter;
import android.animation.TimeInterpolator;
import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.view.MotionEvent;
import android.view.VelocityTracker;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.view.animation.DecelerateInterpolator;
import android.view.animation.PathInterpolator;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.lynx.tasm.behavior.LynxContext;
import com.lynx.tasm.behavior.LynxElement;
import com.lynx.tasm.behavior.LynxProp;
import com.lynx.tasm.behavior.ui.view.AndroidView;
import com.lynx.tasm.behavior.ui.view.UIView;
import com.lynx.tasm.event.LynxCustomEvent;
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
        overlayView =
                new PredictiveBackOverlayView(
                        context,
                        new PredictiveBackOverlayView.Listener() {
                            @Override
                            public void onTransitionEnd(boolean presented) {
                                emitTransitionEnd(presented);
                            }

                            @Override
                            public void onDragDismiss() {
                                emitDragDismiss();
                            }

                            @Override
                            public void onBackdropPress() {
                                emitBackdropPress();
                            }
                        });
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

    @LynxProp(name = "presented", defaultBoolean = false)
    public void setPresented(boolean presented) {
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.setPresented(presented);
        }
    }

    @LynxProp(name = "animate-presence", defaultBoolean = true)
    public void setAnimatePresence(boolean animated) {
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.setAnimatePresence(animated);
        }
    }

    @LynxProp(name = "drag-to-dismiss", defaultBoolean = false)
    public void setDragToDismiss(boolean enabled) {
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.setDragToDismiss(enabled);
        }
    }

    @LynxProp(name = "drag-dismiss-threshold", defaultFloat = 0.22f)
    public void setDragDismissThreshold(float threshold) {
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.setDragDismissThreshold(threshold);
        }
    }

    @LynxProp(name = "content-height-ratio", defaultFloat = 0f)
    public void setContentHeightRatio(float ratio) {
        PredictiveBackOverlayView view = overlayView;
        if (view != null) {
            view.setContentHeightRatio(ratio);
        }
    }

    private void emitTransitionEnd(boolean presented) {
        Map<String, Object> detail = new HashMap<>();
        detail.put("presented", presented);
        getLynxContext()
                .getEventEmitter()
                .sendCustomEvent(new LynxCustomEvent(getSign(), "overlaytransitionend", detail));
    }

    private void emitDragDismiss() {
        Map<String, Object> detail = new HashMap<>();
        getLynxContext()
                .getEventEmitter()
                .sendCustomEvent(new LynxCustomEvent(getSign(), "dragdismiss", detail));
    }

    private void emitBackdropPress() {
        Map<String, Object> detail = new HashMap<>();
        getLynxContext()
                .getEventEmitter()
                .sendCustomEvent(new LynxCustomEvent(getSign(), "backdroppress", detail));
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

    // onCreateView runs inside the LynxBaseUI constructor, before this
    // class's field initializers, so targetId can still be null here.
    private void registerTarget() {
        PredictiveBackOverlayView view = overlayView;
        if (view == null || targetId == null || targetId.isEmpty()) {
            return;
        }
        synchronized (TARGETS) {
            TARGETS.computeIfAbsent(getLynxContext(), ignored -> new HashMap<>())
                    .put(targetId, new WeakReference<>(view));
        }
    }

    private void unregisterTarget() {
        PredictiveBackOverlayView view = overlayView;
        if (view == null || targetId == null || targetId.isEmpty()) {
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
        private static final long ENTER_DURATION_MS = 340L;
        private static final long EXIT_DURATION_MS = 260L;
        private static final long SETTLE_DURATION_MS = 220L;
        private static final TimeInterpolator ENTER_INTERPOLATOR =
                new PathInterpolator(0.16f, 1f, 0.3f, 1f);
        private static final TimeInterpolator EXIT_INTERPOLATOR =
                new PathInterpolator(0.4f, 0f, 1f, 1f);
        private static final TimeInterpolator SETTLE_INTERPOLATOR =
                new DecelerateInterpolator();

        interface Listener {
            void onTransitionEnd(boolean presented);

            void onDragDismiss();

            void onBackdropPress();
        }

        @NonNull private final Listener listener;
        private final int touchSlop;
        private final float minimumDismissVelocity;
        private final Runnable applyPendingPresentation = this::applyPendingPresentation;
        private int backdropColor = 0x73000000;
        @NonNull private String motion = "sheet";
        @NonNull private String edge = "left";
        private float progress = 1f;
        private float contentTranslationX;
        private float contentTranslationY;
        private boolean animatePresence = true;
        private boolean dragToDismiss;
        private float dragDismissThreshold = 0.22f;
        private float contentHeightRatio;
        private boolean presented;
        private boolean presentationResolved;
        private boolean presentationPending;
        private boolean dragCandidate;
        private boolean dragging;
        private boolean backdropTracking;
        private boolean backdropPressCandidate;
        private int backdropPointerId = MotionEvent.INVALID_POINTER_ID;
        private float backdropDownX;
        private float backdropDownY;
        private int activePointerId = MotionEvent.INVALID_POINTER_ID;
        private float dragDownX;
        private float dragDownY;
        @Nullable private VelocityTracker velocityTracker;
        @Nullable private ValueAnimator animator;
        @Nullable private Runnable animationCompletion;

        PredictiveBackOverlayView(Context context, @NonNull Listener listener) {
            super(context);
            this.listener = listener;
            ViewConfiguration configuration = ViewConfiguration.get(context);
            touchSlop = configuration.getScaledTouchSlop();
            minimumDismissVelocity = 900f * context.getResources().getDisplayMetrics().density;
            applyProgress(1f);
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

        void setPresented(boolean value) {
            if (presentationResolved && presented == value) {
                return;
            }
            presentationResolved = true;
            presented = value;
            cancelTouchTracking();
            presentationPending = true;
            removeCallbacks(applyPendingPresentation);
            post(applyPendingPresentation);
        }

        void setAnimatePresence(boolean value) {
            animatePresence = value;
        }

        void setDragToDismiss(boolean value) {
            dragToDismiss = value;
            if (!value) {
                cancelDragTracking();
            }
        }

        void setDragDismissThreshold(float value) {
            dragDismissThreshold = Math.max(0.05f, Math.min(0.9f, value));
        }

        void setContentHeightRatio(float value) {
            contentHeightRatio = Math.max(0f, Math.min(1f, value));
            applyProgress(progress);
            if (presentationPending && contentHeightRatio > 0f) {
                removeCallbacks(applyPendingPresentation);
                post(applyPendingPresentation);
            }
        }

        void begin(@NonNull String gestureEdge) {
            cancelTouchTracking();
            cancelAnimation(false);
            edge = gestureEdge;
            applyProgress(0f);
        }

        void update(float value, @NonNull String gestureEdge) {
            edge = gestureEdge;
            applyProgress(value);
        }

        void cancel() {
            cancelAnimation(false);
            animateTo(0f, SETTLE_DURATION_MS, SETTLE_INTERPOLATOR, null);
        }

        void commit(@NonNull Runnable completion) {
            animateTo(1f, SETTLE_DURATION_MS, SETTLE_INTERPOLATOR, completion);
        }

        void dispose() {
            removeCallbacks(applyPendingPresentation);
            cancelTouchTracking();
            cancelAnimation(true);
            applyProgress(0f);
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            if (presentationPending) {
                removeCallbacks(applyPendingPresentation);
                post(applyPendingPresentation);
            }
        }

        @Override
        protected void onSizeChanged(int width, int height, int oldWidth, int oldHeight) {
            super.onSizeChanged(width, height, oldWidth, oldHeight);
            applyProgress(progress);
            if (presentationPending && width > 0 && height > 0) {
                removeCallbacks(applyPendingPresentation);
                post(applyPendingPresentation);
            }
        }

        @Override
        protected void dispatchDraw(@NonNull Canvas canvas) {
            int checkpoint = canvas.save();
            canvas.translate(contentTranslationX, contentTranslationY);
            super.dispatchDraw(canvas);
            canvas.restoreToCount(checkpoint);
        }

        @Override
        public boolean dispatchTouchEvent(MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    cancelTouchTracking();
                    if (canHandleBackdropPress() && !isTouchInsideContent(event.getY())) {
                        beginBackdropPress(event);
                        return true;
                    }
                    if (canDragToDismiss()) {
                        beginDragCandidate(event);
                    }
                    return super.dispatchTouchEvent(event) || dragCandidate;
                case MotionEvent.ACTION_POINTER_DOWN:
                    if (backdropTracking) {
                        handleBackdropTouch(event);
                        return true;
                    }
                    if (dragging) {
                        addVelocityMovement(event);
                        return true;
                    }
                    return super.dispatchTouchEvent(event) || dragCandidate;
                case MotionEvent.ACTION_POINTER_UP:
                    if (backdropTracking) {
                        handleBackdropTouch(event);
                        return true;
                    }
                    if (dragCandidate || dragging) {
                        addVelocityMovement(event);
                        replaceActivePointerIfNeeded(event);
                    }
                    return dragging || super.dispatchTouchEvent(event) || dragCandidate;
                case MotionEvent.ACTION_MOVE:
                    if (backdropTracking) {
                        handleBackdropTouch(event);
                        return true;
                    }
                    if (dragging) {
                        addVelocityMovement(event);
                        updateDrag(event);
                        return true;
                    }
                    if (!dragCandidate) {
                        return super.dispatchTouchEvent(event);
                    }
                    int pointerIndex = event.findPointerIndex(activePointerId);
                    if (pointerIndex < 0) {
                        cancelDragTracking();
                        return super.dispatchTouchEvent(event);
                    }
                    float deltaX = event.getX(pointerIndex) - dragDownX;
                    float deltaY = event.getY(pointerIndex) - dragDownY;
                    if (deltaY > touchSlop
                            && deltaY > Math.abs(deltaX) * 1.05f
                            && !touchedDescendantCanScrollUp(dragDownX, dragDownY)) {
                        dragging = true;
                        cancelAnimation(false);
                        cancelChildrenTouch(event);
                        ViewParentCompat.disallowIntercept(this, true);
                        addVelocityMovement(event);
                        updateDrag(event);
                        return true;
                    }
                    if (Math.abs(deltaX) > touchSlop || deltaY < -touchSlop) {
                        cancelDragTracking();
                    }
                    return super.dispatchTouchEvent(event) || dragCandidate;
                case MotionEvent.ACTION_UP:
                    if (backdropTracking) {
                        handleBackdropTouch(event);
                        return true;
                    }
                    if (dragging) {
                        addVelocityMovement(event);
                        updateDrag(event);
                        finishDrag(false);
                        return true;
                    }
                    cancelDragTracking();
                    return super.dispatchTouchEvent(event);
                case MotionEvent.ACTION_CANCEL:
                    if (backdropTracking) {
                        handleBackdropTouch(event);
                        return true;
                    }
                    if (dragging) {
                        addVelocityMovement(event);
                        finishDrag(true);
                        return true;
                    }
                    cancelDragTracking();
                    return super.dispatchTouchEvent(event);
                default:
                    return dragging || super.dispatchTouchEvent(event);
            }
        }

        private void cancelChildrenTouch(@NonNull MotionEvent source) {
            MotionEvent cancelEvent = MotionEvent.obtain(source);
            cancelEvent.setAction(MotionEvent.ACTION_CANCEL);
            super.dispatchTouchEvent(cancelEvent);
            cancelEvent.recycle();
        }

        private void applyPendingPresentation() {
            if (!presentationPending
                    || !isAttachedToWindow()
                    || getWidth() <= 0
                    || getHeight() <= 0
                    || ("sheet".equals(motion) && contentHeightRatio <= 0f)) {
                return;
            }
            presentationPending = false;
            cancelAnimation(false);
            final boolean targetPresented = presented;
            float target = targetPresented ? 0f : 1f;
            if (targetPresented && progress >= 0.999f) {
                applyProgress(1f);
            }
            Runnable completion = () -> listener.onTransitionEnd(targetPresented);
            if (!animatePresence) {
                applyProgress(target);
                completion.run();
                return;
            }
            animateTo(
                    target,
                    targetPresented ? ENTER_DURATION_MS : EXIT_DURATION_MS,
                    targetPresented ? ENTER_INTERPOLATOR : EXIT_INTERPOLATOR,
                    completion);
        }

        private void animateTo(
                float target,
                long fullDuration,
                @NonNull TimeInterpolator interpolator,
                @Nullable Runnable completion) {
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
            nextAnimator.setDuration(
                    Math.max(80L, Math.round(fullDuration * Math.abs(target - start))));
            nextAnimator.setInterpolator(interpolator);
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

        private boolean canDragToDismiss() {
            return dragToDismiss
                    && "sheet".equals(motion)
                    && presented
                    && progress <= 0.001f
                    && animator == null;
        }

        private boolean canHandleBackdropPress() {
            return presented && progress <= 0.001f && animator == null;
        }

        private void beginBackdropPress(@NonNull MotionEvent event) {
            backdropTracking = true;
            backdropPressCandidate = true;
            backdropPointerId = event.getPointerId(0);
            backdropDownX = event.getX(0);
            backdropDownY = event.getY(0);
            ViewParentCompat.disallowIntercept(this, true);
        }

        private void handleBackdropTouch(@NonNull MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_MOVE:
                    int pointerIndex = event.findPointerIndex(backdropPointerId);
                    if (pointerIndex < 0
                            || Math.abs(event.getX(pointerIndex) - backdropDownX) > touchSlop
                            || Math.abs(event.getY(pointerIndex) - backdropDownY) > touchSlop) {
                        backdropPressCandidate = false;
                    }
                    break;
                case MotionEvent.ACTION_POINTER_DOWN:
                case MotionEvent.ACTION_POINTER_UP:
                    backdropPressCandidate = false;
                    break;
                case MotionEvent.ACTION_UP:
                    boolean shouldEmit = backdropPressCandidate;
                    cancelBackdropTracking();
                    if (shouldEmit) {
                        listener.onBackdropPress();
                    }
                    break;
                case MotionEvent.ACTION_CANCEL:
                    cancelBackdropTracking();
                    break;
                default:
                    break;
            }
        }

        private void beginDragCandidate(@NonNull MotionEvent event) {
            cancelDragTracking();
            if (!isTouchInsideContent(event.getY())) {
                return;
            }
            dragCandidate = true;
            activePointerId = event.getPointerId(0);
            dragDownX = event.getX(0);
            dragDownY = event.getY(0);
            velocityTracker = VelocityTracker.obtain();
            velocityTracker.addMovement(event);
        }

        private void updateDrag(@NonNull MotionEvent event) {
            int pointerIndex = event.findPointerIndex(activePointerId);
            if (pointerIndex < 0) {
                return;
            }
            float distance = Math.max(0f, event.getY(pointerIndex) - dragDownY);
            applyProgress(distance / Math.max(contentTravelHeight(), 1f));
        }

        private void finishDrag(boolean cancelled) {
            float velocityY = 0f;
            VelocityTracker tracker = velocityTracker;
            if (tracker != null) {
                tracker.computeCurrentVelocity(1000);
                velocityY = tracker.getYVelocity(activePointerId);
            }
            boolean shouldDismiss =
                    !cancelled
                            && (progress >= dragDismissThreshold
                                    || (progress >= 0.04f
                                            && velocityY >= minimumDismissVelocity));
            cancelDragTracking();
            if (shouldDismiss) {
                animateTo(
                        1f,
                        EXIT_DURATION_MS,
                        EXIT_INTERPOLATOR,
                        listener::onDragDismiss);
            } else {
                animateTo(0f, SETTLE_DURATION_MS, SETTLE_INTERPOLATOR, null);
            }
        }

        private void replaceActivePointerIfNeeded(@NonNull MotionEvent event) {
            int actionIndex = event.getActionIndex();
            if (event.getPointerId(actionIndex) != activePointerId) {
                return;
            }
            int replacementIndex = actionIndex == 0 ? 1 : 0;
            if (replacementIndex >= event.getPointerCount()) {
                return;
            }
            float currentDistance = Math.max(0f, progress * contentTravelHeight());
            activePointerId = event.getPointerId(replacementIndex);
            dragDownX = event.getX(replacementIndex);
            dragDownY = event.getY(replacementIndex) - currentDistance;
        }

        private void addVelocityMovement(@NonNull MotionEvent event) {
            VelocityTracker tracker = velocityTracker;
            if (tracker != null) {
                tracker.addMovement(event);
            }
        }

        private void cancelDragTracking() {
            dragCandidate = false;
            dragging = false;
            activePointerId = MotionEvent.INVALID_POINTER_ID;
            VelocityTracker tracker = velocityTracker;
            velocityTracker = null;
            if (tracker != null) {
                tracker.recycle();
            }
            ViewParentCompat.disallowIntercept(this, false);
        }

        private void cancelBackdropTracking() {
            backdropTracking = false;
            backdropPressCandidate = false;
            backdropPointerId = MotionEvent.INVALID_POINTER_ID;
            ViewParentCompat.disallowIntercept(this, false);
        }

        private void cancelTouchTracking() {
            cancelDragTracking();
            cancelBackdropTracking();
        }

        private boolean isTouchInsideContent(float y) {
            float contentHeight = contentTravelHeight();
            return y >= Math.max(0f, getHeight() - contentHeight);
        }

        private boolean touchedDescendantCanScrollUp(float x, float y) {
            return descendantCanScrollUp(this, x, y);
        }

        private static boolean descendantCanScrollUp(
                @NonNull ViewGroup parent, float x, float y) {
            for (int index = parent.getChildCount() - 1; index >= 0; index -= 1) {
                View child = parent.getChildAt(index);
                if (child.getVisibility() != View.VISIBLE
                        || x < child.getLeft()
                        || x >= child.getRight()
                        || y < child.getTop()
                        || y >= child.getBottom()) {
                    continue;
                }
                float childX = x - child.getLeft() + child.getScrollX();
                float childY = y - child.getTop() + child.getScrollY();
                if (child instanceof ViewGroup
                        && descendantCanScrollUp((ViewGroup) child, childX, childY)) {
                    return true;
                }
                if (child.canScrollVertically(-1)) {
                    return true;
                }
            }
            return false;
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
            if (contentHeightRatio > 0f) {
                return getHeight() * contentHeightRatio;
            }
            int contentHeight = 0;
            for (int index = 0; index < getChildCount(); index += 1) {
                contentHeight = Math.max(contentHeight, getChildAt(index).getHeight());
            }
            return contentHeight > 0 ? contentHeight : getHeight();
        }

        /** Avoids importing a support helper just to talk to the current parent. */
        private static final class ViewParentCompat {
            private ViewParentCompat() {}

            static void disallowIntercept(@NonNull View view, boolean disallow) {
                if (view.getParent() != null) {
                    view.getParent().requestDisallowInterceptTouchEvent(disallow);
                }
            }
        }
    }
}
