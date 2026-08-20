package com.lynxapp.activity

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import android.util.Log
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import com.google.gson.Gson
import com.lynx.tasm.LynxView
import com.lynxapp.LynxBundleRepository
import com.lynxapp.component.NativeEnvironmentBridge
import com.lynxapp.component.STATUS_BAR_STYLE_DARK_CONTENT
import com.lynxapp.component.createLynxView
import com.lynxapp.component.enableLynxEdgeToEdge
import com.lynxapp.autolink.router.RouterModule
import com.lynxapp.nativemodule.NativeBackController

/**
 * Hosts a secondary embedded Lynx bundle as an opaque page or transparent overlay.
 *
 * Extends FragmentActivity (not plain Activity) so the autolinked Biometric
 * module can host its BiometricPrompt on the activity that owns the LynxView.
 */
open class LynxPageActivity : FragmentActivity() {
    private lateinit var lynxView: LynxView
    private lateinit var nativeEnvironmentBridge: NativeEnvironmentBridge
    private lateinit var bundleRepository: LynxBundleRepository
    private lateinit var nativeBackController: NativeBackController
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
            ?: STATUS_BAR_STYLE_DARK_CONTENT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (isTransparent) {
            window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            window.decorView.setBackgroundColor(Color.TRANSPARENT)
        }
        enableLynxEdgeToEdge(statusBarStyle)
        bundleRepository = LynxBundleRepository(this)
        nativeBackController = NativeBackController(this)
        lynxView = createLynxView(
            bundleRepository,
            nativeBackController,
            bundleName,
            onBundleLoadFailure = ::fallBackToEmbeddedBundle,
        ).apply {
            setBackgroundColor(if (isTransparent) Color.TRANSPARENT else PAGE_BACKGROUND)
        }
        nativeBackController.attach(lynxView)
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
        nativeBackController.destroy()
        nativeEnvironmentBridge.detach()
        lynxView.destroy()
        super.onDestroy()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!nativeBackController.handleLegacyBack()) {
            super.onBackPressed()
        }
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
        nativeBackController.destroy()
        root.removeView(lynxView)
        lynxView.destroy()

        nativeBackController = NativeBackController(this)
        lynxView = createLynxView(
            bundleRepository,
            nativeBackController,
            bundleName,
            groupUrl = embedded,
        ).apply {
            setBackgroundColor(if (isTransparent) Color.TRANSPARENT else PAGE_BACKGROUND)
        }
        nativeBackController.attach(lynxView)
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
