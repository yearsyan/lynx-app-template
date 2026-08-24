package com.lynxapp.activity

import android.graphics.Color
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import androidx.activity.BackEventCompat
import androidx.activity.OnBackPressedCallback
import androidx.fragment.app.FragmentActivity
import com.google.gson.Gson
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewClient
import com.lynxapp.LynxBundleRepository
import com.lynxapp.R
import com.lynxapp.LynxTemplateApplication
import com.lynxapp.autolink.device.DeviceSystemUI
import com.lynxapp.autolink.device.NativeEnvironmentBridge
import com.lynxapp.component.LoadingOverlay
import com.lynxapp.component.createLynxView
import com.lynxapp.autolink.navigation.NavigationModule

/**
 * Hosts an embedded Lynx bundle as an opaque page. `presentation: 'overlay'`
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

    private val dragDownToDismissEnabled: Boolean
        get() = intent.getBooleanExtra(EXTRA_PRESENT_DRAG_DOWN_TO_DISMISS, false)

    /** Root routes answer `router.close()` by leaving the app instead of finishing. */
    internal open val isRootRoute: Boolean
        get() = false

    /** Bundle to host. Pushed routes read it from route extras; roots state it. */
    protected open val bundleName: String
        get() = intent.getStringExtra(EXTRA_BUNDLE) ?: DEFAULT_BUNDLE

    internal val routeAnimation: String
        get() = intent.getStringExtra(EXTRA_ANIMATION)
            ?: NavigationModule.ANIMATION_DEFAULT

    internal val routePresentation: String
        get() = intent.getStringExtra(EXTRA_PRESENTATION)
            ?: PRESENTATION_PAGE

    /** Overlay routes carry the snapshot backdrop and its choreography. */
    internal val isOverlayRoute: Boolean
        get() = routePresentation == PRESENTATION_OVERLAY

    protected val statusBarStyle: String
        get() = intent.getStringExtra(EXTRA_STATUS_BAR_STYLE)
            ?: DeviceSystemUI.systemStatusBarStyle(this)

    /** Dialog-hosted pages must leave the Activity behind them visible. */
    protected open val usesTransparentPageBackground: Boolean
        get() = false

    /** Allows a floating route to size its Android content from the Lynx tree. */
    protected open val routeContentHeight: Int
        get() = ViewGroup.LayoutParams.MATCH_PARENT

    /** Notifies the host after Lynx has painted enough content for Window coordination. */
    private val routeScreenClient = object : LynxViewClient() {
        override fun onFirstScreen() {
            presentBackdrop?.playPresent(lynxView)
            bundleRepository.schedulePreloadAfterFirstScreen(bundleName)
            onLynxFirstScreen()
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
        configureRouteWindow()
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
        root = PresentDragDismissLayout(this).apply {
            dragDismissEnabled = dragDownToDismissEnabled && presentBackdrop != null
            dragDismissListener = object : PresentDragDismissLayout.Listener {
                override fun onDragStart(): Boolean =
                    presentBackdrop?.beginInteractiveDismiss(lynxView) == true

                override fun onDragProgress(progress: Float) {
                    presentBackdrop?.updateInteractiveDismiss(progress, lynxView)
                }

                override fun onDragEnd(progress: Float, velocityY: Float) {
                    if (progress >= PRESENT_DRAG_COMMIT_PROGRESS ||
                        velocityY >= PRESENT_DRAG_COMMIT_VELOCITY
                    ) {
                        presentBackdrop?.finishInteractiveDismiss(
                            lynxView,
                            ::finishPresentRoute,
                        )
                    } else {
                        presentBackdrop?.cancelInteractiveDismiss(lynxView)
                    }
                }

                override fun onDragCancel() {
                    presentBackdrop?.cancelInteractiveDismiss(lynxView)
                }
            }
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
        }
        setContentView(
            root,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                routeContentHeight,
            ),
        )
        if (presentBackdrop != null) {
            onBackPressedDispatcher.addCallback(this, presentBackCallback.apply { isEnabled = true })
        }
        resolveEntryAndLoad()
    }

    /**
     * The OTA entry gate: resolve the best source — dev override, verified
     * cache, or embedded asset — before the LynxView and its engine group
     * exist, so the group key matches the final URL. A changed bundle
     * downloads behind the loading overlay with a timeout; a slow manifest or
     * download falls back to the current source instead of blocking the page.
     */
    private fun resolveEntryAndLoad() {
        bundleRepository.resolveEntryUrl(
            bundleName,
            onDownloadStarted = {
                LoadingOverlay.show(this, getString(R.string.updating_bundle))
            },
            onReady = { url ->
                LoadingOverlay.hide(this)
                if (isFinishing || isDestroyed) return@resolveEntryUrl
                attachLynxView(url)
            },
        )
    }

    private fun attachLynxView(url: String) {
        lynxView = createLynxView(
            bundleRepository,
            bundleName,
            groupUrl = url,
            onBundleLoadFailure = ::fallBackToEmbeddedBundle,
        ).also(::prepareLynxView)
        root.addView(
            lynxView,
            if (presentBackdrop != null) 2 else 0,
            routeContentLayoutParams(),
        )
        nativeEnvironmentBridge = NativeEnvironmentBridge(
            lynxView = lynxView,
            additionalData = routeData(),
        )
        nativeEnvironmentBridge.attach { renderBundle(url) }
    }

    /** Configures the Window before the route creates and attaches its LynxView. */
    protected open fun configureRouteWindow() {
        // Lynx pages own keyboard avoidance through KeyboardAwareRoot and
        // keyboardstatuschanged. Prevent Android's adjustPan from applying a
        // second, focus-dependent translation when the cursor or text changes.
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_NOTHING)
        DeviceSystemUI.enableEdgeToEdge(this, statusBarStyle)
    }

    override fun onDestroy() {
        if (this::nativeEnvironmentBridge.isInitialized) nativeEnvironmentBridge.detach()
        if (this::lynxView.isInitialized) lynxView.destroy()
        presentBackdrop?.release()
        super.onDestroy()
    }

    /** Called on each LynxView's first screen, including an embedded fallback. */
    protected open fun onLynxFirstScreen() {}

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
            routeContentLayoutParams(),
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
        view.setBackgroundColor(
            if (backdrop != null || usesTransparentPageBackground) {
                Color.TRANSPARENT
            } else {
                getColor(R.color.lynx_page_background)
            },
        )
        view.addLynxViewClient(routeScreenClient)
        if (backdrop != null) {
            backdrop.prepareContent(view)
        }
    }

    private fun routeContentLayoutParams() = FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        routeContentHeight,
    )

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
        val route = mutableMapOf<String, Any>(
            "bundle" to bundleName,
            "animation" to routeAnimation,
            "presentation" to routePresentation,
            "statusBarStyle" to statusBarStyle,
            "params" to params,
        )
        return mapOf("route" to route)
    }

    companion object {
        const val EXTRA_BUNDLE = "lynx.route.bundle"
        const val EXTRA_ANIMATION = "lynx.route.animation"
        const val EXTRA_PRESENTATION = "lynx.route.presentation"
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
        const val EXTRA_PRESENT_DRAG_DOWN_TO_DISMISS =
            "lynx.route.presentDragDownToDismiss"
        const val EXTRA_STATUS_BAR_STYLE = "lynx.route.statusBarStyle"
        const val EXTRA_PARAMS_JSON = "lynx.route.params"
        const val PRESENTATION_PAGE = "page"
        const val PRESENTATION_INPUT_DIALOG = "inputDialog"
        const val PRESENTATION_OVERLAY = "overlay"

        fun isRoutePresentation(value: String): Boolean =
            value == PRESENTATION_PAGE ||
                value == PRESENTATION_INPUT_DIALOG ||
                value == PRESENTATION_OVERLAY

        private const val TAG = "LynxPageActivity"
        private const val DEFAULT_BUNDLE = "main"
        private const val PRESENT_DRAG_COMMIT_PROGRESS = 0.25f
        private const val PRESENT_DRAG_COMMIT_VELOCITY = 1000f
    }
}
