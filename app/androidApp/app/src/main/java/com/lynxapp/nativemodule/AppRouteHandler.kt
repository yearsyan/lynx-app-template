package com.lynxapp.nativemodule

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.util.Log
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.ReadableMap
import com.lynxapp.LynxTemplateApplication
import com.lynxapp.R
import com.lynxapp.activity.LynxDialogActivity
import com.lynxapp.activity.LynxPageActivity
import com.lynxapp.activity.PresentBackdrop
import com.lynxapp.activity.PresentContentAnimationOptions
import com.lynxapp.activity.RouteSnapshotStore
import com.lynxapp.autolink.navigation.LynxRouteHandler
import com.lynxapp.autolink.navigation.LynxRouteHandler.RouteResultEnvelope
import com.lynxapp.autolink.navigation.NavigationModule.ANIMATION_DEFAULT
import com.lynxapp.autolink.navigation.NavigationModule.ANIMATION_FADE
import com.lynxapp.autolink.navigation.NavigationModule.ANIMATION_NONE
import com.lynxapp.autolink.navigation.NavigationModule.isLynxRouteAnimation
import com.lynxapp.autolink.device.DeviceSystemUI
import com.lynxapp.component.LoadingOverlay
import org.json.JSONObject
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicLong

private data class PresentRouteOptions(
    val scrimColor: String?,
    val backdropTransition: Boolean,
    val enterAnimation: PresentContentAnimationOptions,
    val exitAnimation: PresentContentAnimationOptions,
    val backdropBlur: Boolean,
    val androidPredictiveBackDown: Boolean,
    val dragDownToDismiss: Boolean,
)

private data class ValidatedRoute(
    val bundle: String,
    val animation: String,
    val presentation: String,
    val statusBarStyle: String,
    val params: Map<String, Any>,
    val presentOptions: PresentRouteOptions,
)

/** A pending openForResult callback, resolved when the opened route dies. */
private class PendingRouteResult(
    val resultCallback: Callback,
    opener: Activity,
) {
    val opener = WeakReference(opener)
    var result: Map<String, Any>? = null
}

/**
 * Host navigation behind the autolinked Navigation module: opens another Lynx
 * bundle in a real Android Activity. When the Application-prefetched OTA
 * version list marks the target bundle outdated, the update downloads behind
 * a loading overlay before the page opens against the fresh cache. State on
 * the calling Activity's route (such as its animation) drives how close()
 * undoes the transition. `presentation: 'overlay'` snapshots the calling page
 * first; the opened page replays that snapshot as its backdrop (see
 * PresentBackdrop) instead of relying on a translucent activity, so the
 * iOS-like present transition also composes with the normal back stack.
 *
 * openForResult routes carry a result token through the launched intent; the
 * pending callback registry here delivers the recorded result (or none) from
 * onActivityDestroyed, which fires on every close path — close(),
 * closeWithResult(), system Back and finishWithPresentTransition alike.
 */
class AppRouteHandler(
    application: Application,
) : LynxRouteHandler, Application.ActivityLifecycleCallbacks {
    init {
        application.registerActivityLifecycleCallbacks(this)
    }

    // Main-thread confined: written from runOnUiThread blocks, read from the
    // registered ActivityLifecycleCallbacks.
    private val pendingResults = HashMap<String, PendingRouteResult>()

    override fun open(activity: Activity, options: ReadableMap, callback: Callback) {
        val route = parseRouteOptions(options, callback::invoke) ?: return
        activity.runOnUiThread {
            runCatching {
                openWhenReady(activity, route, resultToken = null)
            }.onSuccess {
                callback.invoke("")
            }.onFailure { error ->
                callback.invoke(error.message ?: "Unable to open native route")
            }
        }
    }

    override fun openForResult(
        activity: Activity,
        options: ReadableMap,
        resultCallback: Callback,
    ) {
        // A callable reference to the member extension invokeEnvelopeError is
        // prohibited in Kotlin; wrap the call instead.
        val route = parseRouteOptions(options) {
            resultCallback.invokeEnvelopeError(it)
        } ?: return
        val token = "route-result-${NEXT_RESULT_TOKEN.incrementAndGet()}"
        activity.runOnUiThread {
            // Registry access stays on the main thread: openForResult puts,
            // closeWithResult records, onActivityDestroyed delivers.
            pendingResults[token] = PendingRouteResult(resultCallback, activity)
            runCatching {
                openWhenReady(activity, route, resultToken = token)
            }.onFailure { error ->
                pendingResults.remove(token)
                resultCallback.invokeEnvelopeError(
                    error.message ?: "Unable to open native route",
                )
            }
        }
    }

    override fun close(activity: Activity, callback: Callback) {
        if (activity !is LynxPageActivity) {
            callback.invoke("The route cannot be closed")
            return
        }
        activity.runOnUiThread { performClose(activity, callback) }
    }

    override fun closeWithResult(
        activity: Activity,
        result: ReadableMap,
        callback: Callback,
    ) {
        if (activity !is LynxPageActivity) {
            callback.invoke("The route cannot be closed")
            return
        }
        activity.runOnUiThread {
            routeResultToken(activity)?.let { token ->
                pendingResults[token]?.result = result.toHashMap()
            }
            performClose(activity, callback)
        }
    }

    private fun performClose(activity: LynxPageActivity, callback: Callback) {
        if (activity.isRootRoute) {
            // Closing the root leaves the app; the task stays alive so
            // returning is instant instead of a cold Lynx restart.
            activity.moveTaskToBack(true)
        } else if (activity.isOverlayRoute) {
            // The reverse choreography finishes the activity itself once
            // the backdrop has restored the previous page's pixels.
            activity.finishWithPresentTransition()
        } else {
            activity.finish()
            when (activity.routeAnimation) {
                ANIMATION_NONE ->
                    activity.overridePendingTransition(0, 0)
                ANIMATION_FADE ->
                    activity.overridePendingTransition(
                        android.R.anim.fade_in,
                        android.R.anim.fade_out,
                    )
            }
        }
        callback.invoke("")
    }

    /**
     * Opens the route immediately, or once a pending bundle update has
     * downloaded behind [LoadingOverlay] (a failed download opens the page
     * with the current source instead of blocking navigation). The open
     * callback resolves as soon as the flow is initiated.
     */
    private fun openWhenReady(
        activity: Activity,
        route: ValidatedRoute,
        resultToken: String?,
    ) {
        val repository = (activity.application as LynxTemplateApplication).bundleRepository
        val update = repository.pendingUpdateFor(route.bundle)
        if (update == null) {
            startActivityForRoute(activity, route, resultToken)
            return
        }
        LoadingOverlay.show(activity, activity.getString(R.string.updating_bundle))
        repository.download(update) { updated ->
            if (!updated) {
                Log.w(TAG, "Bundle ${route.bundle} update failed; opening the current source")
            }
            activity.runOnUiThread {
                LoadingOverlay.hide(activity)
                if (activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                startActivityForRoute(activity, route, resultToken)
            }
        }
    }

    private fun startActivityForRoute(
        activity: Activity,
        route: ValidatedRoute,
        resultToken: String?,
    ) {
        if (route.presentation == LynxPageActivity.PRESENTATION_OVERLAY) {
            // Capture only after any update overlay has been hidden, so the
            // snapshot shows the page the user was looking at.
            PresentBackdrop.capture(activity, route.presentOptions.backdropBlur) { snapshot ->
                activity.runOnUiThread {
                    if (activity.isFinishing || activity.isDestroyed) {
                        snapshot?.recycle()
                        return@runOnUiThread
                    }
                    if (snapshot != null) {
                        RouteSnapshotStore.put(snapshot)
                    }
                    startRouteActivity(activity, route, resultToken, snapshot != null)
                }
            }
        } else {
            startRouteActivity(activity, route, resultToken, false)
        }
    }

    private fun startRouteActivity(
        activity: Activity,
        route: ValidatedRoute,
        resultToken: String?,
        withSnapshot: Boolean,
    ) {
        val destination = if (
            route.presentation == LynxPageActivity.PRESENTATION_INPUT_DIALOG
        ) {
            LynxDialogActivity::class.java
        } else {
            LynxPageActivity::class.java
        }
        activity.startActivity(
            Intent(activity, destination).apply {
                putExtra(LynxPageActivity.EXTRA_BUNDLE, route.bundle)
                putExtra(LynxPageActivity.EXTRA_ANIMATION, route.animation)
                putExtra(LynxPageActivity.EXTRA_PRESENTATION, route.presentation)
                putExtra(LynxPageActivity.EXTRA_SNAPSHOT, withSnapshot)
                putExtra(LynxPageActivity.EXTRA_STATUS_BAR_STYLE, route.statusBarStyle)
                if (route.presentOptions.scrimColor != null) {
                    putExtra(
                        LynxPageActivity.EXTRA_PRESENT_SCRIM_COLOR,
                        route.presentOptions.scrimColor,
                    )
                }
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_BACKDROP_TRANSITION,
                    route.presentOptions.backdropTransition,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_ENTER_OPACITY,
                    route.presentOptions.enterAnimation.opacity,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_ENTER_PUSH,
                    route.presentOptions.enterAnimation.push,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_EXIT_OPACITY,
                    route.presentOptions.exitAnimation.opacity,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_EXIT_PUSH,
                    route.presentOptions.exitAnimation.push,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_BACKDROP_BLUR,
                    route.presentOptions.backdropBlur,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_ANDROID_PREDICTIVE_BACK_DOWN,
                    route.presentOptions.androidPredictiveBackDown,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PRESENT_DRAG_DOWN_TO_DISMISS,
                    route.presentOptions.dragDownToDismiss,
                )
                putExtra(
                    LynxPageActivity.EXTRA_PARAMS_JSON,
                    JSONObject(route.params).toString(),
                )
                if (resultToken != null) {
                    putExtra(EXTRA_RESULT_TOKEN, resultToken)
                }
            },
        )
        when (route.animation) {
            ANIMATION_NONE ->
                activity.overridePendingTransition(0, 0)
            ANIMATION_FADE ->
                activity.overridePendingTransition(
                    android.R.anim.fade_in,
                    android.R.anim.fade_out,
                )
        }
    }

    private fun parseRouteOptions(
        options: ReadableMap,
        onError: (String) -> Unit,
    ): ValidatedRoute? {
        val bundle = options.getString("bundle", "")
        if (!BUNDLE_NAME.matches(bundle)) {
            onError("Invalid Lynx bundle name: $bundle")
            return null
        }

        val presentation = options.getString(
            "presentation",
            LynxPageActivity.PRESENTATION_PAGE,
        )
        if (!LynxPageActivity.isRoutePresentation(presentation)) {
            onError("Invalid route presentation: $presentation")
            return null
        }
        val defaultAnimation = if (
            presentation == LynxPageActivity.PRESENTATION_PAGE
        ) {
            ANIMATION_DEFAULT
        } else {
            ANIMATION_NONE
        }
        // Overlay routes own their open/close choreography, so they always
        // run without a system transition regardless of the animation value.
        val animation = if (
            presentation == LynxPageActivity.PRESENTATION_OVERLAY
        ) {
            ANIMATION_NONE
        } else {
            options.getString("animation", defaultAnimation)
        }
        if (!isLynxRouteAnimation(animation)) {
            onError("Invalid route animation: $animation")
            return null
        }
        val statusBarStyle = options.getString(
            "statusBarStyle",
            DeviceSystemUI.STATUS_BAR_STYLE_DARK_CONTENT,
        )
        if (!DeviceSystemUI.isStatusBarStyle(statusBarStyle)) {
            onError("Invalid status bar style: $statusBarStyle")
            return null
        }
        val params = options.getMap("params")?.toHashMap().orEmpty()
        val overlay = options.getMap("overlay")
        val presentScrimColor = overlay?.getString("scrimColor")
        if (presentScrimColor != null && !SCRIM_COLOR.matches(presentScrimColor)) {
            onError("Invalid overlay scrim color: $presentScrimColor")
            return null
        }
        val presentBackdropTransition = overlay?.getBoolean("backdropTransition", true) ?: true
        val legacyContentTransition = overlay?.getBoolean("contentTransition", true) ?: true
        val presentEnter = overlay?.getMap("enter")
        val presentExit = overlay?.getMap("exit")
        val presentBackdropBlur = overlay?.getBoolean("backdropBlur", false) ?: false
        val presentAndroidPredictiveBackDown =
            overlay?.getBoolean("androidPredictiveBackDown", false) ?: false
        val presentDragDownToDismiss =
            overlay?.getBoolean("dragDownToDismiss", false) ?: false
        val presentOptions = PresentRouteOptions(
            scrimColor = presentScrimColor,
            backdropTransition = presentBackdropTransition,
            enterAnimation = PresentContentAnimationOptions(
                opacity = presentEnter?.getBoolean("opacity", false) ?: false,
                push = presentEnter?.getBoolean("push", legacyContentTransition)
                    ?: legacyContentTransition,
            ),
            exitAnimation = PresentContentAnimationOptions(
                opacity = presentExit?.getBoolean("opacity", false) ?: false,
                push = presentExit?.getBoolean("push", legacyContentTransition)
                    ?: legacyContentTransition,
            ),
            backdropBlur = presentBackdropBlur,
            androidPredictiveBackDown = presentAndroidPredictiveBackDown,
            dragDownToDismiss = presentDragDownToDismiss,
        )
        return ValidatedRoute(
            bundle = bundle,
            animation = animation,
            presentation = presentation,
            statusBarStyle = statusBarStyle,
            params = params,
            presentOptions = presentOptions,
        )
    }

    private fun routeResultToken(activity: Activity): String? =
        activity.intent?.getStringExtra(EXTRA_RESULT_TOKEN)

    /** Delivers the pending entry once, with its recorded result or none. */
    private fun completePendingResult(token: String) {
        val pending = pendingResults.remove(token) ?: return
        val result = pending.result
        val envelope = if (result != null) {
            RouteResultEnvelope.value(JSONObject(result))
        } else {
            RouteResultEnvelope.empty()
        }
        pending.resultCallback.invoke(envelope)
    }

    override fun onActivityDestroyed(activity: Activity) {
        // Route close: deliver its pending result (or the no-result envelope).
        routeResultToken(activity)?.let(::completePendingResult)
        // Opener death: the awaiting JS context is gone; drop its entries.
        val iterator = pendingResults.entries.iterator()
        while (iterator.hasNext()) {
            val entry = iterator.next().value
            if (entry.opener.get() === activity) {
                iterator.remove()
            }
        }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: android.os.Bundle?) {}

    override fun onActivityStarted(activity: Activity) {}

    override fun onActivityResumed(activity: Activity) {}

    override fun onActivityPaused(activity: Activity) {}

    override fun onActivityStopped(activity: Activity) {}

    override fun onActivitySaveInstanceState(
        activity: Activity,
        outState: android.os.Bundle,
    ) {}

    companion object {
        private const val TAG = "AppRouteHandler"
        /** Correlates a launched route with its opener's pending callback. */
        internal const val EXTRA_RESULT_TOKEN = "lynx.route.result-token"
        private val BUNDLE_NAME = Regex("^[a-z0-9][a-z0-9-]*$")
        private val SCRIM_COLOR = Regex("^#[0-9a-fA-F]{8}$")
        private val NEXT_RESULT_TOKEN = AtomicLong()

        /** Invokes the callback with a JSON error envelope. */
        private fun Callback.invokeEnvelopeError(message: String) {
            invoke(RouteResultEnvelope.error(message))
        }
    }
}
