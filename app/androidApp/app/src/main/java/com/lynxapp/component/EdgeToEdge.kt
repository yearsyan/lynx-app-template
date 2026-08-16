package com.lynxapp.component

import android.app.Activity
import android.os.Build
import androidx.core.view.WindowCompat

internal const val STATUS_BAR_STYLE_DARK_CONTENT = "dark-content"
internal const val STATUS_BAR_STYLE_LIGHT_CONTENT = "light-content"

internal fun isLynxStatusBarStyle(value: String): Boolean =
    value == STATUS_BAR_STYLE_DARK_CONTENT || value == STATUS_BAR_STYLE_LIGHT_CONTENT

internal fun Activity.enableLynxEdgeToEdge(
    statusBarStyle: String = STATUS_BAR_STYLE_DARK_CONTENT,
) {
    WindowCompat.setDecorFitsSystemWindows(window, false)
    WindowCompat.getInsetsController(window, window.decorView).apply {
        isAppearanceLightStatusBars = statusBarStyle == STATUS_BAR_STYLE_DARK_CONTENT
        isAppearanceLightNavigationBars = true
    }

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        window.isStatusBarContrastEnforced = false
        window.isNavigationBarContrastEnforced = false
    }
}

internal fun Activity.setLynxStatusBarStyle(statusBarStyle: String) {
    WindowCompat.getInsetsController(window, window.decorView)
        .isAppearanceLightStatusBars = statusBarStyle == STATUS_BAR_STYLE_DARK_CONTENT
}
