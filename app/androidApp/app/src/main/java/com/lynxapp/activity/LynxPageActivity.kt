package com.lynxapp.activity

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.widget.FrameLayout
import androidx.activity.BackEventCompat
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.FragmentActivity
import com.google.gson.Gson
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewClient
import com.lynxapp.LynxBundleRepository
import com.lynxapp.LynxTemplateApplication
import com.lynxapp.autolink.device.DeviceSystemUI
import com.lynxapp.autolink.device.NativeEnvironmentBridge
import com.lynxapp.component.createLynxView
import com.lynxapp.autolink.navigation.NavigationModule

/**
 * Hosts an embedded Lynx bundle as an opaque page. `animation: 'present'`
 * routes layer a [PresentBackdrop] — a snapshot of the previous page — behind
 * a transparent-background LynxView and play the present choreography from
 * the content's first screen (see [PresentBackdrop] for the timing).
 *
 * The app root (MainActivity) subclasses this: a pushed page reads its route
 * from intent extras, the root states its configuration via overrides.
 *
 * Extends FragmentActivity (not plain Activity) so the autolinked Back and
 * Biometric modules can use AndroidX lifecycle-aware host APIs.
 */
open class LynxPageActivity : FragmentActivity() {
    private lateinit var lynxView: LynxView
    private lateinit var nativeEnvironmentBridge: NativeEnvironmentBridge
    protected lateinit var bundleRepository: LynxBundleRepository
    protected lateinit var root: FrameLayout
    private var fellBackToEmbedded = false
    private var presentBackdrop: PresentBackdrop? = null
    private var predictiveBackDismissStarted = false

    private val androidPredictiveBackDownEnabled: Boolean
        get() = intent.getBooleanExtra(EXTRA_PRESENT_ANDROID_PREDICTIVE_BACK_DOWN, false)

    /** Root routes answer `router.close()` by leaving the app instead of finishing. */
    internal open val isRootRoute: Boolean
        get() = false

    /** Bundle to host. Pushed routes read it from route extras; roots state it. */
    protected open val bundleName: String
        get() = intent.getStringExtra(EXTRA_BUNDLE) ?: DEFAULT_BUNDLE

    internal val routeAnimation: String
        get() = intent.getStringExtra(EXTRA_ANIMATION)
            ?: NavigationModule.ANIMATION_DEFAULT

    private val statusBarStyle: String
        get() = intent.getStringExtra(EXTRA_STATUS_BAR_STYLE)
            ?: DeviceSystemUI.STATUS_BAR_STYLE_DARK_CONTENT

    /** Reveals the content over the backdrop once its first screen is painted. */
    private val presentScreenClient = object : LynxViewClient() {
        override fun onFirstScreen() {
            presentBackdrop?.playPresent(lynxView)
        }
    }

    // Present routes replay their open choreography in reverse before really
    // finishing. Registered after the autolink Back dispatcher's callbacks, so
    // JS in-page interception still wins over the route dismissal.
    private val presentBackCallback = object : OnBackPressedCallback(false) {
        override fun handleOnBackStarted(backEvent: BackEventCompat) {
            if (!androidPredictiveBackDownEnabled) return
            predictiveBackDismissStarted =
                presentBackdrop?.beginInteractiveDismiss(lynxView) == true
        }

        override fun handleOnBackProgressed(backEvent: BackEventCompat) {
            if (!androidPredictiveBackDownEnabled) return
            if (!predictiveBackDismissStarted) {
                predictiveBackDismissStarted =
                    presentBackdrop?.beginInteractiveDismiss(lynxView) == true
            }
            if (predictiveBackDismissStarted) {
                presentBackdrop?.updateInteractiveDismiss(backEvent.progress, lynxView)
            }
        }

        override fun handleOnBackCancelled() {
            if (!predictiveBackDismissStarted) return
            predictiveBackDismissStarted = false
            presentBackdrop?.cancelInteractiveDismiss(lynxView)
        }

        override fun handleOnBackPressed() {
            if (androidPredictiveBackDownEnabled && predictiveBackDismissStarted) {
                predictiveBackDismissStarted = false
                presentBackdrop?.finishInteractiveDismiss(lynxView, ::finishPresentRoute)
            } else {
                finishWithPresentTransition()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceSystemUI.enableEdgeToEdge(this, statusBarStyle)
        bundleRepository = (application as LynxTemplateApplication).bundleRepository
        presentBackdrop = if (intent.getBooleanExtra(EXTRA_SNAPSHOT, false)) {
            RouteSnapshotStore.consume()?.let { bitmap ->
                PresentBackdrop(
                    activity = this,
                    bitmap = bitmap,
                    scrimColor = intent.getStringExtra(EXTRA_PRESENT_SCRIM_COLOR)
                        ?.let { runCatching { Color.parseColor(it) }.getOrNull() },
                    backdropTransition = intent.getBooleanExtra(EXTRA_PRESENT_BACKDROP_TRANSITION, true),
                    enterAnimation = PresentContentAnimationOptions(
                        opacity = intent.getBooleanExtra(EXTRA_PRESENT_ENTER_OPACITY, false),
                        push = intent.getBooleanExtra(EXTRA_PRESENT_ENTER_PUSH, true),
                    ),
                    exitAnimation = PresentContentAnimationOptions(
                        opacity = intent.getBooleanExtra(EXTRA_PRESENT_EXIT_OPACITY, false),
                        push = intent.getBooleanExtra(EXTRA_PRESENT_EXIT_PUSH, true),
                    ),
                    blurred = intent.getBooleanExtra(EXTRA_PRESENT_BACKDROP_BLUR, false),
                )
            }
        } else {
            null
        }
        lynxView = createLynxView(
            bundleRepository,
            bundleName,
            onBundleLoadFailure = ::fallBackToEmbeddedBundle,
        ).also(::prepareLynxView)
        root = FrameLayout(this).apply {
            presentBackdrop?.let { backdrop ->
                addView(
                    backdrop.view,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
                addView(
                    backdrop.scrim,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                    ),
                )
            }
            addView(
                lynxView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        setContentView(root)
        if (presentBackdrop != null) {
            onBackPressedDispatcher.addCallback(this, presentBackCallback.apply { isEnabled = true })
        }
        nativeEnvironmentBridge = NativeEnvironmentBridge(
            lynxView = lynxView,
            additionalData = routeData(),
        )
        nativeEnvironmentBridge.attach(::loadBundle)
    }

    override fun onDestroy() {
        nativeEnvironmentBridge.detach()
        lynxView.destroy()
        presentBackdrop?.release()
        super.onDestroy()
    }

    private fun loadBundle() {
        renderBundle(bundleRepository.urlForBundle(bundleName))
        onInitialBundleRendered()
    }

    /** Called after the first render request; the root overrides it to apply OTA updates. */
    protected open fun onInitialBundleRendered() {}

    private fun renderBundle(url: String) {
        lynxView.renderTemplateUrl(url, nativeEnvironmentBridge.initialData())
        nativeEnvironmentBridge.onTemplateLoadStarted()
    }

    // A dev server or OTA cache that cannot serve the bundle must not leave a
    // white screen; render the embedded bundle instead. Runs at most once:
    // if the embedded bundle itself fails, the error stays visible. The view
    // is rebuilt because its LynxViewGroup is bound to the failed URL —
    // re-rendering in place would refetch that URL instead of the fallback.
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
        ).also(::prepareLynxView)
        root.addView(
            lynxView,
            if (presentBackdrop != null) 2 else 0,
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

    /**
     * Present routes draw the LynxView with a transparent background over the
     * snapshot backdrop and keep it hidden until the backdrop's choreography
     * reveals it from the first screen.
     */
    private fun prepareLynxView(view: LynxView) {
        val backdrop = presentBackdrop
        view.setBackgroundColor(if (backdrop != null) Color.TRANSPARENT else PAGE_BACKGROUND)
        if (backdrop != null) {
            view.addLynxViewClient(presentScreenClient)
            backdrop.prepareContent(view)
        }
    }

    /** Closes a present route through the reverse choreography, with no system transition. */
    internal fun finishWithPresentTransition() {
        predictiveBackDismissStarted = false
        val backdrop = presentBackdrop
        if (backdrop == null) {
            finish()
            return
        }
        backdrop.playDismiss(lynxView, ::finishPresentRoute)
    }

    private fun finishPresentRoute() {
        finish()
        overridePendingTransition(0, 0)
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
                "animation" to routeAnimation,
                "statusBarStyle" to statusBarStyle,
                "params" to params,
            ),
        )
    }

    companion object {
        const val EXTRA_BUNDLE = "lynx.route.bundle"
        const val EXTRA_ANIMATION = "lynx.route.animation"
        const val EXTRA_SNAPSHOT = "lynx.route.snapshot"
        const val EXTRA_PRESENT_SCRIM_COLOR = "lynx.route.presentScrimColor"
        const val EXTRA_PRESENT_BACKDROP_TRANSITION = "lynx.route.presentBackdropTransition"
        const val EXTRA_PRESENT_ENTER_OPACITY = "lynx.route.presentEnterOpacity"
        const val EXTRA_PRESENT_ENTER_PUSH = "lynx.route.presentEnterPush"
        const val EXTRA_PRESENT_EXIT_OPACITY = "lynx.route.presentExitOpacity"
        const val EXTRA_PRESENT_EXIT_PUSH = "lynx.route.presentExitPush"
        const val EXTRA_PRESENT_BACKDROP_BLUR = "lynx.route.presentBackdropBlur"
        const val EXTRA_PRESENT_ANDROID_PREDICTIVE_BACK_DOWN =
            "lynx.route.presentAndroidPredictiveBackDown"
        const val EXTRA_STATUS_BAR_STYLE = "lynx.route.statusBarStyle"
        const val EXTRA_PARAMS_JSON = "lynx.route.params"
        private const val TAG = "LynxPageActivity"
        private const val DEFAULT_BUNDLE = "main"
        private const val PAGE_BACKGROUND = 0xFFF7F7FB.toInt()
    }
}
