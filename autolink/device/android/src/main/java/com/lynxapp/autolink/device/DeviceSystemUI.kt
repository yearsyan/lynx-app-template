package com.lynxapp.autolink.device

import android.app.Activity
import android.content.res.Configuration
import android.os.Build
import androidx.core.view.WindowCompat

/** System-UI operations shared by the autolink module and its host adapter. */
object DeviceSystemUI {
    const val STATUS_BAR_STYLE_DARK_CONTENT = "dark-content"
    const val STATUS_BAR_STYLE_LIGHT_CONTENT = "light-content"

    @JvmStatic
    fun isStatusBarStyle(value: String): Boolean =
        value == STATUS_BAR_STYLE_DARK_CONTENT || value == STATUS_BAR_STYLE_LIGHT_CONTENT

    @JvmStatic
    fun systemStatusBarStyle(activity: Activity): String =
        if (isDarkMode(activity.resources.configuration)) {
            STATUS_BAR_STYLE_LIGHT_CONTENT
        } else {
            STATUS_BAR_STYLE_DARK_CONTENT
        }

    @JvmStatic
    @JvmOverloads
    fun enableEdgeToEdge(
        activity: Activity,
        statusBarStyle: String = STATUS_BAR_STYLE_DARK_CONTENT,
    ) {
        WindowCompat.setDecorFitsSystemWindows(activity.window, false)
        WindowCompat.getInsetsController(activity.window, activity.window.decorView).apply {
            isAppearanceLightStatusBars = statusBarStyle == STATUS_BAR_STYLE_DARK_CONTENT
            isAppearanceLightNavigationBars = !isDarkMode(activity.resources.configuration)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            activity.window.isStatusBarContrastEnforced = false
            activity.window.isNavigationBarContrastEnforced = false
        }
    }

    @JvmStatic
    fun setStatusBarStyle(activity: Activity, statusBarStyle: String) {
        WindowCompat.getInsetsController(activity.window, activity.window.decorView)
            .isAppearanceLightStatusBars = statusBarStyle == STATUS_BAR_STYLE_DARK_CONTENT
    }

    private fun isDarkMode(configuration: Configuration): Boolean =
        configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
}
