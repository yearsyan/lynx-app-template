package com.lynxapp

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.doOnLayout
import com.lynxapp.activity.DebugSettingsActivity
import kotlin.math.hypot

/** Adds the native settings affordance to Debug builds only. */
object DebugSettingsEntry {
    private const val PREFERENCES_NAME = "debug_settings_entry"
    private const val KEY_X = "x"
    private const val KEY_Y = "y"

    /** Draggable pill: taps open the settings activity; drags reposition and persist. */
    @SuppressLint("ClickableViewAccessibility")
    fun attach(activity: Activity, root: FrameLayout) {
        val density = activity.resources.displayMetrics.density
        val horizontalPadding = (12 * density).toInt()
        val verticalPadding = (7 * density).toInt()
        val margin = (12 * density).toInt()
        val preferences = activity.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val touchSlop = ViewConfiguration.get(activity).scaledTouchSlop
        val button = TextView(activity).apply {
            text = "DEV"
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.CENTER
            setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
            background = GradientDrawable().apply {
                cornerRadius = 18 * density
                setColor(0xE62B63F1.toInt())
                setStroke((1 * density).toInt().coerceAtLeast(1), 0x66FFFFFF)
            }
            elevation = 8 * density
            contentDescription = "Open Lynx development settings"
            setOnClickListener {
                activity.startActivity(Intent(activity, DebugSettingsActivity::class.java))
            }
        }
        root.addView(
            button,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.START,
            ),
        )
        var insetLeft = 0
        var insetTop = 0
        var insetRight = 0
        var insetBottom = 0
        fun clampX(value: Float): Float {
            val minX = insetLeft.toFloat()
            val maxX = (root.width - button.width - insetRight).toFloat().coerceAtLeast(minX)
            return value.coerceIn(minX, maxX)
        }
        fun clampY(value: Float): Float {
            val minY = insetTop.toFloat()
            val maxY = (root.height - button.height - insetBottom).toFloat().coerceAtLeast(minY)
            return value.coerceIn(minY, maxY)
        }

        // The pill floats freely within the safe area; the persisted position is
        // re-applied (and clamped) on attach and on inset changes so it survives
        // the CLEAR_TASK reload triggered by "Save & reload".
        fun applyPosition() {
            if (root.width == 0 || button.width == 0) {
                return
            }
            if (preferences.contains(KEY_X) && preferences.contains(KEY_Y)) {
                button.x = clampX(preferences.getFloat(KEY_X, 0f))
                button.y = clampY(preferences.getFloat(KEY_Y, 0f))
            } else {
                button.x = clampX((root.width - button.width - insetRight - margin).toFloat())
                button.y = clampY((insetTop + margin).toFloat())
            }
        }
        var downRawX = 0f
        var downRawY = 0f
        var downX = 0f
        var downY = 0f
        var draggedBeyondSlop = false
        button.setOnTouchListener { view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX
                    downRawY = event.rawY
                    downX = view.x
                    downY = view.y
                    draggedBeyondSlop = false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!draggedBeyondSlop &&
                        hypot(event.rawX - downRawX, event.rawY - downRawY) > touchSlop
                    ) {
                        draggedBeyondSlop = true
                    }
                    if (draggedBeyondSlop) {
                        view.x = clampX(downX + event.rawX - downRawX)
                        view.y = clampY(downY + event.rawY - downRawY)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (draggedBeyondSlop) {
                        preferences.edit()
                            .putFloat(KEY_X, view.x)
                            .putFloat(KEY_Y, view.y)
                            .apply()
                    } else {
                        view.performClick()
                    }
                }
                MotionEvent.ACTION_CANCEL -> applyPosition()
            }
            true
        }
        root.doOnLayout { applyPosition() }
        ViewCompat.setOnApplyWindowInsetsListener(button) { _, insets ->
            val systemBars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            insetLeft = systemBars.left
            insetTop = systemBars.top
            insetRight = systemBars.right
            insetBottom = systemBars.bottom
            applyPosition()
            insets
        }
        ViewCompat.requestApplyInsets(button)
    }
}
