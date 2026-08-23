package com.lynxapp.autolink.device

import android.content.res.Configuration
import androidx.core.os.ConfigurationCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import com.lynx.tasm.LynxUpdateMeta
import com.lynx.tasm.LynxView
import com.lynx.tasm.TemplateData

/**
 * Publishes native window geometry using Lynx logical px (Android dp).
 * Keyboard/IME insets are deliberately excluded from the safe-area contract.
 */
class NativeEnvironmentBridge(
    private val lynxView: LynxView,
    private val additionalData: Map<String, Any> = emptyMap(),
) {
    private data class SafeAreaInsets(
        val top: Double = 0.0,
        val right: Double = 0.0,
        val bottom: Double = 0.0,
        val left: Double = 0.0,
    )

    private var safeAreaInsets = SafeAreaInsets()
    private var statusBarInsetTop = 0.0
    private var navigationBarInsetBottom = 0.0
    private var hasReceivedInitialInsets = false
    private var canUpdateTemplate = false
    private var onInitialInsetsReady: (() -> Unit)? = null

    fun attach(onInitialInsetsReady: () -> Unit) {
        this.onInitialInsetsReady = onInitialInsetsReady
        ViewCompat.setOnApplyWindowInsetsListener(lynxView) { _, windowInsets ->
            accept(windowInsets)
            windowInsets
        }
        // setContentView() does not guarantee that root insets are already available.
        // Wait until the LynxView is attached so the first template receives real
        // geometry instead of rendering once with a zero safe area.
        lynxView.post {
            ViewCompat.getRootWindowInsets(lynxView)?.let(::accept)
            ViewCompat.requestApplyInsets(lynxView)
        }
    }

    fun detach() {
        onInitialInsetsReady = null
        ViewCompat.setOnApplyWindowInsetsListener(lynxView, null)
    }

    fun initialData(): TemplateData = templateData(
        safeAreaInsets,
        statusBarInsetTop,
        navigationBarInsetBottom,
    )

    /** Call immediately after a load/render request so later inset changes are incremental. */
    fun onTemplateLoadStarted() {
        canUpdateTemplate = true
        publish(safeAreaInsets, statusBarInsetTop, navigationBarInsetBottom)
    }

    private fun accept(windowInsets: WindowInsetsCompat) {
        val nativeInsets = windowInsets.getInsets(
            WindowInsetsCompat.Type.systemBars() or
                WindowInsetsCompat.Type.displayCutout(),
        )
        val statusBarInsets = windowInsets.getInsets(WindowInsetsCompat.Type.statusBars())
        val navigationBarInsets = windowInsets.getInsetsIgnoringVisibility(
            WindowInsetsCompat.Type.navigationBars(),
        )
        val density = lynxView.resources.displayMetrics.density
            .takeIf { it > 0f } ?: 1f
        val next = SafeAreaInsets(
            top = nativeInsets.top / density.toDouble(),
            right = nativeInsets.right / density.toDouble(),
            bottom = nativeInsets.bottom / density.toDouble(),
            left = nativeInsets.left / density.toDouble(),
        )
        val statusBarHeightResource = lynxView.resources.getIdentifier(
            "status_bar_height",
            "dimen",
            "android",
        )
        val statusBarHeightPixels = if (statusBarHeightResource > 0) {
            lynxView.resources.getDimensionPixelSize(statusBarHeightResource)
        } else {
            statusBarInsets.top
        }
        val nextStatusBarInsetTop = statusBarHeightPixels / density.toDouble()
        val navigationBarHeightResource = lynxView.resources.getIdentifier(
            "navigation_bar_height",
            "dimen",
            "android",
        )
        val navigationBarHeightPixels = if (navigationBarHeightResource > 0) {
            lynxView.resources.getDimensionPixelSize(navigationBarHeightResource)
        } else {
            navigationBarInsets.bottom
        }
        val nextNavigationBarInsetBottom = navigationBarHeightPixels / density.toDouble()
        val changed = next != safeAreaInsets ||
            nextStatusBarInsetTop != statusBarInsetTop ||
            nextNavigationBarInsetBottom != navigationBarInsetBottom
        safeAreaInsets = next
        statusBarInsetTop = nextStatusBarInsetTop
        navigationBarInsetBottom = nextNavigationBarInsetBottom

        if (!hasReceivedInitialInsets) {
            hasReceivedInitialInsets = true
            onInitialInsetsReady?.invoke()
            onInitialInsetsReady = null
            return
        }

        if (changed && canUpdateTemplate) {
            publish(next, nextStatusBarInsetTop, nextNavigationBarInsetBottom)
        }
    }

    private fun publish(
        insets: SafeAreaInsets,
        statusBarInsetTop: Double,
        navigationBarInsetBottom: Double,
    ) {
        val updateMeta = LynxUpdateMeta.Builder()
            .setUpdatedData(
                templateData(insets, statusBarInsetTop, navigationBarInsetBottom),
            )
            .build()
        lynxView.updateMetaData(updateMeta)
    }

    private fun templateData(
        insets: SafeAreaInsets,
        statusBarInsetTop: Double,
        navigationBarInsetBottom: Double,
    ): TemplateData {
        val configuration = lynxView.resources.configuration
        val colorScheme = if (
            configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        ) {
            "dark"
        } else {
            "light"
        }
        val locales = ConfigurationCompat.getLocales(configuration)
        val locale = if (locales.isEmpty) {
            "en"
        } else {
            locales[0]?.toLanguageTag() ?: "en"
        }
        val data = mutableMapOf<String, Any>(
            "nativeEnvironment" to mapOf(
                "schemaVersion" to 2,
                "unit" to "px",
                "statusBarInsetTop" to statusBarInsetTop,
                "navigationBarInsetBottom" to navigationBarInsetBottom,
                "colorScheme" to colorScheme,
                "locale" to locale,
                "safeAreaInsets" to mapOf(
                    "top" to insets.top,
                    "right" to insets.right,
                    "bottom" to insets.bottom,
                    "left" to insets.left,
                ),
            ),
        )
        data.putAll(additionalData)
        return TemplateData.fromMap(data)
    }
}
