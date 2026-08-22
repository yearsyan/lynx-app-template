package com.lynxapp.component

import android.app.Activity
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/**
 * Full-window overlay for OTA downloads that block a navigation step. It
 * swallows touches but not back: the underlying flow always completes and
 * then proceeds with the best available bundle.
 */
internal object LoadingOverlay {
    private const val OVERLAY_TAG = "lynx-loading-overlay"

    fun show(activity: Activity, text: String) {
        activity.runOnUiThread {
            val decor = activity.window.decorView as? ViewGroup ?: return@runOnUiThread
            if (decor.findViewWithTag<View>(OVERLAY_TAG) != null) return@runOnUiThread

            val density = activity.resources.displayMetrics.density
            val content = LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
            }
            content.addView(
                ProgressBar(activity),
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
            content.addView(
                TextView(activity).apply {
                    this.text = text
                    setTextColor(Color.WHITE)
                    textSize = 14f
                    setPadding(0, (12 * density).toInt(), 0, 0)
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )

            val overlay = FrameLayout(activity).apply {
                tag = OVERLAY_TAG
                setBackgroundColor(0x99000000.toInt())
                isClickable = true
            }
            overlay.addView(
                content,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    FrameLayout.LayoutParams.WRAP_CONTENT,
                    Gravity.CENTER,
                ),
            )
            decor.addView(
                overlay,
                ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT,
                ),
            )
        }
    }

    fun hide(activity: Activity) {
        activity.runOnUiThread {
            val decor = activity.window.decorView as? ViewGroup ?: return@runOnUiThread
            val overlay = decor.findViewWithTag<View>(OVERLAY_TAG) ?: return@runOnUiThread
            decor.removeView(overlay)
        }
    }
}
