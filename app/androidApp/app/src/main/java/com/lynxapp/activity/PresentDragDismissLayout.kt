package com.lynxapp.activity

import android.content.Context
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

/**
 * Gives child content first refusal of a touch sequence, then locks an
 * unclaimed downward pan to the native present dismissal until UP/CANCEL.
 *
 * Normal ViewGroup interception semantics are intentional: a child that has
 * claimed the interaction can call requestDisallowInterceptTouchEvent(true).
 * If no child claims it, crossing touch slop downward sends ACTION_CANCEL to
 * the child and this parent consumes every remaining movement in the stream.
 */
internal class PresentDragDismissLayout(context: Context) : FrameLayout(context) {
    interface Listener {
        fun onDragStart(): Boolean
        fun onDragProgress(progress: Float)
        fun onDragEnd(progress: Float, velocityY: Float)
        fun onDragCancel()
    }

    var dragDismissEnabled: Boolean = false
    var dragDismissListener: Listener? = null

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private val minimumFlingVelocity =
        ViewConfiguration.get(context).scaledMinimumFlingVelocity.toFloat()
    private var activePointerId = MotionEvent.INVALID_POINTER_ID
    private var downX = 0f
    private var downY = 0f
    private var dragging = false
    private var rejected = false
    private var velocityTracker: VelocityTracker? = null

    override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
        if (!dragDismissEnabled) {
            return super.onInterceptTouchEvent(event)
        }
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                resetTracking()
                activePointerId = event.getPointerId(0)
                downX = event.x
                downY = event.y
                velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
            }

            MotionEvent.ACTION_MOVE -> {
                velocityTracker?.addMovement(event)
                if (dragging) return true
                if (rejected) return false
                val index = event.findPointerIndex(activePointerId)
                if (index < 0) {
                    rejected = true
                    return false
                }
                val dx = event.getX(index) - downX
                val dy = event.getY(index) - downY
                if (dy > touchSlop && abs(dy) > abs(dx)) {
                    if (dragDismissListener?.onDragStart() == true) {
                        dragging = true
                        parent?.requestDisallowInterceptTouchEvent(true)
                        return true
                    }
                    rejected = true
                } else if (abs(dx) > touchSlop || dy < -touchSlop) {
                    // Direction is decided once. An upward or horizontal
                    // sequence stays with the page for its entire lifetime.
                    rejected = true
                }
            }

            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (!dragging) resetTracking()
            }
        }
        return false
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (!dragging) return super.onTouchEvent(event)
        velocityTracker?.addMovement(event)
        when (event.actionMasked) {
            MotionEvent.ACTION_MOVE -> {
                dragDismissListener?.onDragProgress(progressFor(event))
            }

            MotionEvent.ACTION_UP -> {
                val progress = progressFor(event)
                velocityTracker?.computeCurrentVelocity(1000)
                val velocityY = velocityTracker?.getYVelocity(activePointerId) ?: 0f
                dragDismissListener?.onDragEnd(
                    progress,
                    if (abs(velocityY) >= minimumFlingVelocity) velocityY else 0f,
                )
                resetTracking()
            }

            MotionEvent.ACTION_CANCEL -> {
                dragDismissListener?.onDragCancel()
                resetTracking()
            }

            MotionEvent.ACTION_POINTER_UP -> {
                val pointerIndex = event.actionIndex
                if (event.getPointerId(pointerIndex) == activePointerId) {
                    dragDismissListener?.onDragCancel()
                    resetTracking()
                }
            }
        }
        return true
    }

    private fun progressFor(event: MotionEvent): Float {
        val index = event.findPointerIndex(activePointerId)
        if (index < 0) return 0f
        val distance = (event.getY(index) - downY).coerceAtLeast(0f)
        return (distance / height.coerceAtLeast(1).toFloat()).coerceIn(0f, 1f)
    }

    private fun resetTracking() {
        velocityTracker?.recycle()
        velocityTracker = null
        activePointerId = MotionEvent.INVALID_POINTER_ID
        dragging = false
        rejected = false
    }
}
