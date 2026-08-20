package com.lynxapp.autolink.pressableview;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewParent;
import android.view.ViewTreeObserver;

import com.lynx.tasm.behavior.LynxContext;
import com.lynx.tasm.behavior.LynxElement;
import com.lynx.tasm.behavior.LynxProp;
import com.lynx.tasm.behavior.ui.list.container.NestedScrollContainerView;
import com.lynx.tasm.behavior.ui.scroll.AndroidScrollView;
import com.lynx.tasm.behavior.ui.view.AndroidView;
import com.lynx.tasm.behavior.ui.view.UIView;
import com.lynx.tasm.event.LynxCustomEvent;
import com.lynx.tasm.utils.ColorUtils;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/** Native child-hosting press target with scroll-aware opacity feedback. */
@LynxElement(name = PressableViewElement.NAME)
public final class PressableViewElement extends UIView {
    public static final String NAME = "pressable-view";
    private static final float DEFAULT_ACTIVE_OPACITY = 0.7f;

    private PressableAndroidView pressableView;

    public PressableViewElement(LynxContext context) {
        super(context);
    }

    public PressableViewElement(LynxContext context, Object params) {
        super(context, params);
    }

    @Override
    protected AndroidView onCreateView(Context context) {
        pressableView = new PressableAndroidView(context, this::emitPress);
        return pressableView;
    }

    @LynxProp(name = "active-opacity", defaultFloat = DEFAULT_ACTIVE_OPACITY)
    public void setActiveOpacity(float activeOpacity) {
        if (pressableView != null) {
            pressableView.setActiveOpacity(activeOpacity);
        }
    }

    @LynxProp(name = "pressed-overlay-color")
    public void setPressedOverlayColor(String color) {
        if (pressableView != null) {
            int parsedColor = color != null && ColorUtils.isValid(color)
                    ? ColorUtils.parse(color)
                    : Color.TRANSPARENT;
            pressableView.setPressedOverlayColor(parsedColor);
        }
    }

    @LynxProp(name = "disabled", defaultBoolean = false)
    public void setDisabled(boolean disabled) {
        if (pressableView != null) {
            pressableView.setEnabled(!disabled);
        }
    }

    private void emitPress() {
        // Lynx augments the detail map with event metadata before dispatching,
        // so it must be mutable even when the custom payload is empty.
        Map<String, Object> detail = new HashMap<>();
        getLynxContext()
                .getEventEmitter()
                .sendCustomEvent(new LynxCustomEvent(getSign(), "press", detail));
    }

    @Override
    public void destroy() {
        if (pressableView != null) {
            pressableView.disposePressState();
        }
        super.destroy();
    }

    private interface PressListener {
        void onPress();
    }

    /**
     * Intercepts descendants as one semantic target, while leaving every
     * ancestor free to intercept the sequence when scrolling wins.
     */
    private static final class PressableAndroidView extends AndroidView {
        private static final long MIN_TAP_FLASH_MS = 72L;

        private final PressListener listener;
        private final int touchSlop;
        private final long scrollCooldownMs;
        private final ScrollAncestorTracker scrollTracker;
        private final Runnable showPressedRunnable = this::showPressedIfEligible;
        private final Runnable clearTapFlashRunnable = this::clearTapFlashIfIdle;

        private float activeOpacity = DEFAULT_ACTIVE_OPACITY;
        private float baseAlpha = 1f;
        private float pressAlphaMultiplier = 1f;
        private boolean tracking;
        private boolean blocked;
        private boolean pressVisualVisible;
        private int activePointerId = MotionEvent.INVALID_POINTER_ID;
        private float downX;
        private float downY;

        PressableAndroidView(Context context, PressListener listener) {
            super(context);
            this.listener = listener;
            ViewConfiguration configuration = ViewConfiguration.get(context);
            touchSlop = configuration.getScaledTouchSlop();
            scrollCooldownMs = Math.max(64L, ViewConfiguration.getTapTimeout());
            scrollTracker = new ScrollAncestorTracker(this::blockForAncestorScroll);
            setClickable(true);
            setFocusable(true);
        }

        void setActiveOpacity(float value) {
            activeOpacity = Math.max(0f, Math.min(1f, value));
            if (pressVisualVisible) {
                applyCombinedAlpha();
            }
        }

        void setPressedOverlayColor(int color) {
            if (Color.alpha(color) == 0) {
                setForeground(null);
                return;
            }
            // Android's native pressed treatment is a bounded ripple drawn as
            // a foreground state layer, rather than fading all descendants.
            setForeground(
                    new RippleDrawable(
                            ColorStateList.valueOf(color),
                            null,
                            new ColorDrawable(Color.WHITE)));
        }

        @Override
        public void setAlpha(float alpha) {
            baseAlpha = alpha;
            applyCombinedAlpha();
        }

        private void applyCombinedAlpha() {
            pressAlphaMultiplier = pressVisualVisible ? activeOpacity : 1f;
            super.setAlpha(baseAlpha * pressAlphaMultiplier);
        }

        @Override
        public void setEnabled(boolean enabled) {
            super.setEnabled(enabled);
            setClickable(enabled);
            if (!enabled) {
                cancelSequence();
            }
        }

        @Override
        protected void onAttachedToWindow() {
            super.onAttachedToWindow();
            scrollTracker.attach(this);
        }

        @Override
        protected void onDetachedFromWindow() {
            disposePressState();
            super.onDetachedFromWindow();
        }

        @Override
        public boolean onInterceptTouchEvent(MotionEvent event) {
            // A pressable is one whole-item target. Ancestor interception still
            // runs before this method and remains able to send ACTION_CANCEL.
            return true;
        }

        @Override
        public boolean onTouchEvent(MotionEvent event) {
            switch (event.getActionMasked()) {
                case MotionEvent.ACTION_DOWN:
                    beginSequence(event);
                    return true;
                case MotionEvent.ACTION_MOVE:
                    updateSequence(event);
                    return true;
                case MotionEvent.ACTION_POINTER_UP:
                    if (event.getPointerId(event.getActionIndex()) == activePointerId) {
                        blocked = true;
                        cancelSequence();
                    }
                    return true;
                case MotionEvent.ACTION_UP:
                    endSequence(event);
                    return true;
                case MotionEvent.ACTION_CANCEL:
                    cancelSequence();
                    return true;
                default:
                    return true;
            }
        }

        private void beginSequence(MotionEvent event) {
            removeCallbacks(showPressedRunnable);
            removeCallbacks(clearTapFlashRunnable);
            setPressVisual(false);
            tracking = isEnabled();
            blocked = !tracking || scrollTracker.isScrollingOrRecent(scrollCooldownMs);
            activePointerId = event.getPointerId(0);
            downX = event.getX(0);
            downY = event.getY(0);
            drawableHotspotChanged(downX, downY);
            if (!blocked) {
                postDelayed(showPressedRunnable, ViewConfiguration.getTapTimeout());
            }
        }

        private void updateSequence(MotionEvent event) {
            if (!tracking || blocked) {
                return;
            }
            int pointerIndex = event.findPointerIndex(activePointerId);
            if (pointerIndex < 0) {
                blockCurrentSequence();
                return;
            }
            float x = event.getX(pointerIndex);
            float y = event.getY(pointerIndex);
            drawableHotspotChanged(x, y);
            float deltaX = x - downX;
            float deltaY = y - downY;
            if ((deltaX * deltaX) + (deltaY * deltaY) > touchSlop * touchSlop
                    || !isInsideRetentionBounds(x, y)) {
                blockCurrentSequence();
            }
        }

        private void endSequence(MotionEvent event) {
            int pointerIndex = event.findPointerIndex(activePointerId);
            boolean inside = pointerIndex >= 0
                    && isInsideRetentionBounds(event.getX(pointerIndex), event.getY(pointerIndex));
            boolean accepted = tracking
                    && !blocked
                    && isEnabled()
                    && inside
                    && !scrollTracker.isScrollingOrRecent(scrollCooldownMs);

            removeCallbacks(showPressedRunnable);
            tracking = false;
            activePointerId = MotionEvent.INVALID_POINTER_ID;
            if (accepted) {
                if (!pressVisualVisible) {
                    setPressVisual(true);
                    postDelayed(clearTapFlashRunnable, MIN_TAP_FLASH_MS);
                } else {
                    setPressVisual(false);
                }
                performClick();
            } else {
                setPressVisual(false);
            }
            blocked = false;
        }

        @Override
        public boolean performClick() {
            super.performClick();
            if (!isEnabled()) {
                return false;
            }
            listener.onPress();
            return true;
        }

        private boolean isInsideRetentionBounds(float x, float y) {
            return x >= -touchSlop
                    && y >= -touchSlop
                    && x <= getWidth() + touchSlop
                    && y <= getHeight() + touchSlop;
        }

        private void showPressedIfEligible() {
            if (tracking
                    && !blocked
                    && isEnabled()
                    && !scrollTracker.isScrollingOrRecent(scrollCooldownMs)) {
                setPressVisual(true);
            }
        }

        private void clearTapFlashIfIdle() {
            if (!tracking) {
                setPressVisual(false);
            }
        }

        private void setPressVisual(boolean pressed) {
            if (pressVisualVisible == pressed) {
                return;
            }
            pressVisualVisible = pressed;
            super.setPressed(pressed);
            applyCombinedAlpha();
        }

        private void blockCurrentSequence() {
            blocked = true;
            removeCallbacks(showPressedRunnable);
            setPressVisual(false);
        }

        private void blockForAncestorScroll() {
            if (tracking) {
                blockCurrentSequence();
            }
        }

        private void cancelSequence() {
            tracking = false;
            blocked = false;
            activePointerId = MotionEvent.INVALID_POINTER_ID;
            removeCallbacks(showPressedRunnable);
            removeCallbacks(clearTapFlashRunnable);
            setPressVisual(false);
        }

        void disposePressState() {
            cancelSequence();
            scrollTracker.detach();
        }
    }

    /** Tracks public scroll-state callbacks without reflecting into Lynx internals. */
    private static final class ScrollAncestorTracker {
        private final Runnable onScroll;
        private final List<Runnable> detachActions = new ArrayList<>();
        private final Set<View> scrollingViews =
                Collections.newSetFromMap(new IdentityHashMap<>());
        private long lastScrollActivityMs = Long.MIN_VALUE;

        ScrollAncestorTracker(Runnable onScroll) {
            this.onScroll = onScroll;
        }

        void attach(View host) {
            detach();
            attachViewTreeScrollListener(host);
            ViewParent current = host.getParent();
            while (current instanceof View) {
                View ancestor = (View) current;
                if (ancestor instanceof AndroidScrollView) {
                    attachLynxScrollView((AndroidScrollView) ancestor);
                } else if (ancestor instanceof NestedScrollContainerView) {
                    attachLynxList((NestedScrollContainerView) ancestor);
                }
                current = current.getParent();
            }
        }

        private void attachViewTreeScrollListener(View host) {
            ViewTreeObserver observer = host.getViewTreeObserver();
            ViewTreeObserver.OnScrollChangedListener listener = this::recordActivity;
            observer.addOnScrollChangedListener(listener);
            detachActions.add(() -> {
                if (observer.isAlive()) {
                    observer.removeOnScrollChangedListener(listener);
                }
            });
        }

        private void attachLynxScrollView(AndroidScrollView scrollView) {
            AndroidScrollView.OnScrollListener listener =
                    new AndroidScrollView.OnScrollListener() {
                        @Override
                        public void onScrollStop() {
                            updateState(scrollView, false);
                        }

                        @Override
                        public void onScrollChanged(int left, int top, int oldLeft, int oldTop) {
                            if (left != oldLeft || top != oldTop) {
                                recordActivity();
                            }
                        }

                        @Override
                        public void onScrollStart() {
                            updateState(scrollView, true);
                        }

                        @Override
                        public void onScrollStateChanged(int state) {
                            updateState(scrollView, state != AndroidScrollView.SCROLL_STATE_IDLE);
                        }

                        @Override
                        public void onFling(int velocity) {
                            updateState(scrollView, true);
                        }
                    };
            scrollView.addOnScrollListener(listener);
            detachActions.add(() -> scrollView.removeOnScrollListener(listener));
        }

        private void attachLynxList(NestedScrollContainerView list) {
            NestedScrollContainerView.OnScrollStateChangeListener listener =
                    (view, state) -> updateState(
                            list,
                            state != NestedScrollContainerView.SCROLL_STATE_IDLE);
            list.addOnScrollStateChangeListener(listener);
            detachActions.add(() -> list.removeOnScrollStateChangeListener(listener));
        }

        private void updateState(View view, boolean scrolling) {
            lastScrollActivityMs = SystemClock.uptimeMillis();
            if (scrolling) {
                scrollingViews.add(view);
                onScroll.run();
            } else {
                scrollingViews.remove(view);
            }
        }

        private void recordActivity() {
            lastScrollActivityMs = SystemClock.uptimeMillis();
            onScroll.run();
        }

        boolean isScrollingOrRecent(long cooldownMs) {
            if (!scrollingViews.isEmpty()) {
                return true;
            }
            if (lastScrollActivityMs == Long.MIN_VALUE) {
                return false;
            }
            return SystemClock.uptimeMillis() - lastScrollActivityMs <= cooldownMs;
        }

        void detach() {
            for (Runnable action : detachActions) {
                action.run();
            }
            detachActions.clear();
            scrollingViews.clear();
            lastScrollActivityMs = Long.MIN_VALUE;
        }
    }
}
