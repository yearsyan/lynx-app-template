package com.lynxapp.autolink.device

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

    fun initialData(): TemplateData = templateData(safeAreaInsets)

    /** Call immediately after a load/render request so later inset changes are incremental. */
    fun onTemplateLoadStarted() {
        canUpdateTemplate = true
        publish(safeAreaInsets)
    }

    private fun accept(windowInsets: WindowInsetsCompat) {
        val nativeInsets = windowInsets.getInsets(
            WindowInsetsCompat.Type.systemBars() or
                WindowInsetsCompat.Type.displayCutout(),
        )
        val density = lynxView.resources.displayMetrics.density
            .takeIf { it > 0f } ?: 1f
        val next = SafeAreaInsets(
            top = nativeInsets.top / density.toDouble(),
            right = nativeInsets.right / density.toDouble(),
            bottom = nativeInsets.bottom / density.toDouble(),
            left = nativeInsets.left / density.toDouble(),
        )
        val changed = next != safeAreaInsets
        safeAreaInsets = next

        if (!hasReceivedInitialInsets) {
            hasReceivedInitialInsets = true
            onInitialInsetsReady?.invoke()
            onInitialInsetsReady = null
            return
        }

        if (changed && canUpdateTemplate) {
            publish(next)
        }
    }

    private fun publish(insets: SafeAreaInsets) {
        val updateMeta = LynxUpdateMeta.Builder()
            .setUpdatedData(templateData(insets))
            .build()
        lynxView.updateMetaData(updateMeta)
    }

    private fun templateData(insets: SafeAreaInsets): TemplateData {
        val data = mutableMapOf<String, Any>(
            "nativeEnvironment" to mapOf(
                "schemaVersion" to 1,
                "unit" to "px",
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
