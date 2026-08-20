package com.lynxapp.activity

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.util.Log
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import com.google.gson.Gson
import com.lynx.tasm.LynxView
import com.lynxapp.autolink.deviceinfo.DeviceSystemUI
import com.lynxapp.autolink.deviceinfo.NativeEnvironmentBridge
import com.lynxapp.LynxBundleRepository
import com.lynxapp.component.createLynxView
import com.lynxapp.autolink.router.RouterModule

/**
 * Hosts a secondary embedded Lynx bundle as an opaque page or transparent overlay.
 *
 * Extends FragmentActivity (not plain Activity) so the autolinked Back and
 * Biometric modules can use AndroidX lifecycle-aware host APIs.
 */
open class LynxPageActivity : FragmentActivity() {
    private lateinit var lynxView: LynxView
    private lateinit var nativeEnvironmentBridge: NativeEnvironmentBridge
    private lateinit var bundleRepository: LynxBundleRepository
    private lateinit var root: FrameLayout
    private var fellBackToEmbedded = false

    internal val routePresentation: String
        get() = intent.getStringExtra(EXTRA_PRESENTATION)
            ?: RouterModule.PRESENTATION_PUSH

    internal val routeAnimation: String
        get() = intent.getStringExtra(EXTRA_ANIMATION)
            ?: RouterModule.ANIMATION_DEFAULT

    private val bundleName: String
        get() = intent.getStringExtra(EXTRA_BUNDLE) ?: DEFAULT_BUNDLE

    private val isTransparent: Boolean
        get() = intent.getBooleanExtra(EXTRA_TRANSPARENT, false)

    private val statusBarStyle: String
        get() = intent.getStringExtra(EXTRA_STATUS_BAR_STYLE)
            ?: DeviceSystemUI.STATUS_BAR_STYLE_DARK_CONTENT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isTransparent) {
            window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            window.decorView.setBackgroundColor(Color.TRANSPARENT)
        }
        DeviceSystemUI.enableEdgeToEdge(this, statusBarStyle)
        bundleRepository = LynxBundleRepository(this)
        lynxView = createLynxView(
            bundleRepository,
            bundleName,
            onBundleLoadFailure = ::fallBackToEmbeddedBundle,
        ).apply {
            setBackgroundColor(if (isTransparent) Color.TRANSPARENT else PAGE_BACKGROUND)
        }
        root = FrameLayout(this).apply {
            addView(
                lynxView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        setContentView(root)
        nativeEnvironmentBridge = NativeEnvironmentBridge(
            lynxView = lynxView,
            additionalData = routeData(),
        )
        nativeEnvironmentBridge.attach(::loadBundle)
    }

    override fun onDestroy() {
        nativeEnvironmentBridge.detach()
        lynxView.destroy()
        super.onDestroy()
    }

    private fun loadBundle() {
        renderBundle(bundleRepository.urlForBundle(bundleName))
    }

    private fun renderBundle(url: String) {
        lynxView.renderTemplateUrl(url, nativeEnvironmentBridge.initialData())
        nativeEnvironmentBridge.onTemplateLoadStarted()
    }

    private fun fallBackToEmbeddedBundle() {
        if (fellBackToEmbedded) return
        fellBackToEmbedded = true
        val embedded = bundleRepository.embeddedUrlForBundle(bundleName)
        Log.w(TAG, "Bundle $bundleName failed to load; falling back to $embedded")

        nativeEnvironmentBridge.detach()
        root.removeView(lynxView)
        lynxView.destroy()

        lynxView = createLynxView(
            bundleRepository,
            bundleName,
            groupUrl = embedded,
        ).apply {
            setBackgroundColor(if (isTransparent) Color.TRANSPARENT else PAGE_BACKGROUND)
        }
        root.addView(
            lynxView,
            0,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        nativeEnvironmentBridge = NativeEnvironmentBridge(
            lynxView = lynxView,
            additionalData = routeData(),
        )
        nativeEnvironmentBridge.attach { renderBundle(embedded) }
    }

    private fun routeData(): Map<String, Any> {
        val paramsJSON = intent.getStringExtra(EXTRA_PARAMS_JSON) ?: "{}"
        val params = runCatching {
            @Suppress("UNCHECKED_CAST")
            Gson().fromJson(paramsJSON, Map::class.java) as Map<String, Any>
        }.getOrDefault(emptyMap())
        return mapOf(
            "route" to mapOf(
                "bundle" to bundleName,
                "presentation" to routePresentation,
                "animation" to routeAnimation,
                "transparent" to isTransparent,
                "statusBarStyle" to statusBarStyle,
                "params" to params,
            ),
        )
    }

    companion object {
        const val EXTRA_BUNDLE = "lynx.route.bundle"
        const val EXTRA_PRESENTATION = "lynx.route.presentation"
        const val EXTRA_ANIMATION = "lynx.route.animation"
        const val EXTRA_TRANSPARENT = "lynx.route.transparent"
        const val EXTRA_STATUS_BAR_STYLE = "lynx.route.statusBarStyle"
        const val EXTRA_PARAMS_JSON = "lynx.route.params"
        private const val TAG = "LynxPageActivity"
        private const val DEFAULT_BUNDLE = "main"
        private const val PAGE_BACKGROUND = 0xFFF7F7FB.toInt()
    }
}
