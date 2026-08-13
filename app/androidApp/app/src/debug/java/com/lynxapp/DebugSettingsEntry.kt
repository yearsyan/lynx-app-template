package com.lynxapp

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.lynxapp.activity.DebugSettingsActivity

/** Adds the native settings affordance to Debug builds only. */
object DebugSettingsEntry {
    fun attach(activity: Activity, root: FrameLayout) {
        val density = activity.resources.displayMetrics.density
        val horizontalPadding = (12 * density).toInt()
        val verticalPadding = (7 * density).toInt()
        val margin = (12 * density).toInt()
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
        val layoutParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END,
        ).apply {
            topMargin = margin
            marginEnd = margin
        }
        root.addView(button, layoutParams)
        ViewCompat.setOnApplyWindowInsetsListener(button) { view, insets ->
            val systemBars = insets.getInsets(
                WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout(),
            )
            (view.layoutParams as FrameLayout.LayoutParams).also { params ->
                params.topMargin = systemBars.top + margin
                params.marginEnd = systemBars.right + margin
                view.layoutParams = params
            }
            insets
        }
        ViewCompat.requestApplyInsets(button)
    }
}
