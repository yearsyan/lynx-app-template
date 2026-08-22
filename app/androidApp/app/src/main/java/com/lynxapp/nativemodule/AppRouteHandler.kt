package com.lynxapp.nativemodule

import android.app.Activity
import android.content.Intent
import android.util.Log
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.ReadableMap
import com.lynxapp.LynxTemplateApplication
import com.lynxapp.activity.LynxPageActivity
import com.lynxapp.activity.TransparentLynxPageActivity
import com.lynxapp.autolink.navigation.LynxRouteHandler
import com.lynxapp.autolink.navigation.NavigationModule.ANIMATION_DEFAULT
import com.lynxapp.autolink.navigation.NavigationModule.ANIMATION_FADE
import com.lynxapp.autolink.navigation.NavigationModule.ANIMATION_NONE
import com.lynxapp.autolink.navigation.NavigationModule.PRESENTATION_PUSH
import com.lynxapp.autolink.navigation.NavigationModule.PRESENTATION_SHEET
import com.lynxapp.autolink.navigation.NavigationModule.isLynxRouteAnimation
import com.lynxapp.autolink.device.DeviceSystemUI
import com.lynxapp.component.LoadingOverlay
import org.json.JSONObject

/**
 * Host navigation behind the autolinked Navigation module: opens another Lynx
 * bundle in a real Android Activity. When the Application-prefetched OTA
 * version list marks the target bundle outdated, the update downloads behind
 * a loading overlay before the page opens against the fresh cache. State on
 * the calling Activity's route (such as its animation) drives how close()
 * undoes the transition.
 */
class AppRouteHandler : LynxRouteHandler {
    override fun open(activity: Activity, options: ReadableMap, callback: Callback) {
        val bundle = options.getString("bundle", "")
        if (!BUNDLE_NAME.matches(bundle)) {
            callback.invoke("Invalid Lynx bundle name: $bundle")
            return
        }

        val presentation = options.getString("presentation", PRESENTATION_PUSH)
        val transparent = options.getBoolean(
            "transparent",
            presentation == PRESENTATION_SHEET,
        )
        val animation = options.getString("animation", ANIMATION_DEFAULT)
        if (!isLynxRouteAnimation(animation)) {
            callback.invoke("Invalid route animation: $animation")
            return
        }
        val statusBarStyle = options.getString(
            "statusBarStyle",
            DeviceSystemUI.STATUS_BAR_STYLE_DARK_CONTENT,
        )
        if (!DeviceSystemUI.isStatusBarStyle(statusBarStyle)) {
            callback.invoke("Invalid status bar style: $statusBarStyle")
            return
        }
        val params = options.getMap("params")?.toHashMap().orEmpty()
        activity.runOnUiThread {
            runCatching {
                openWhenReady(
                    activity,
                    bundle,
                    presentation,
                    transparent,
                    animation,
                    statusBarStyle,
                    params,
                )
            }.onSuccess {
                callback.invoke("")
            }.onFailure { error ->
                callback.invoke(error.message ?: "Unable to open native route")
            }
        }
    }

    /**
     * Opens the route immediately, or once a pending bundle update has
     * downloaded behind [LoadingOverlay] (a failed download opens the page
     * with the current source instead of blocking navigation). The open
     * callback resolves as soon as the flow is initiated.
     */
    private fun openWhenReady(
        activity: Activity,
        bundle: String,
        presentation: String,
        transparent: Boolean,
        animation: String,
        statusBarStyle: String,
        params: Map<String, Any>,
    ) {
        val repository = (activity.application as LynxTemplateApplication).bundleRepository
        val update = repository.pendingUpdateFor(bundle)
        if (update == null) {
            startActivityForRoute(activity, bundle, presentation, transparent, animation, statusBarStyle, params)
            return
        }
        LoadingOverlay.show(activity, UPDATE_LOADING_TEXT)
        repository.download(update) { updated ->
            if (!updated) {
                Log.w(TAG, "Bundle $bundle update failed; opening the current source")
            }
            activity.runOnUiThread {
                LoadingOverlay.hide(activity)
                if (activity.isFinishing || activity.isDestroyed) return@runOnUiThread
                startActivityForRoute(activity, bundle, presentation, transparent, animation, statusBarStyle, params)
            }
        }
    }

    private fun startActivityForRoute(
        activity: Activity,
        bundle: String,
        presentation: String,
        transparent: Boolean,
        animation: String,
        statusBarStyle: String,
        params: Map<String, Any>,
    ) {
        val destination = if (transparent) {
            TransparentLynxPageActivity::class.java
        } else {
            LynxPageActivity::class.java
        }
        activity.startActivity(
            Intent(activity, destination).apply {
                putExtra(LynxPageActivity.EXTRA_BUNDLE, bundle)
                putExtra(LynxPageActivity.EXTRA_PRESENTATION, presentation)
                putExtra(LynxPageActivity.EXTRA_ANIMATION, animation)
                putExtra(LynxPageActivity.EXTRA_TRANSPARENT, transparent)
                putExtra(LynxPageActivity.EXTRA_STATUS_BAR_STYLE, statusBarStyle)
                putExtra(
                    LynxPageActivity.EXTRA_PARAMS_JSON,
                    JSONObject(params).toString(),
                )
            },
        )
        when {
            animation == ANIMATION_NONE ->
                activity.overridePendingTransition(0, 0)
            animation == ANIMATION_FADE || presentation == PRESENTATION_SHEET ->
                activity.overridePendingTransition(
                    android.R.anim.fade_in,
                    android.R.anim.fade_out,
                )
        }
    }

    override fun close(activity: Activity, callback: Callback) {
        if (activity !is LynxPageActivity) {
            callback.invoke("The route cannot be closed")
            return
        }
        activity.runOnUiThread {
            if (activity.isRootRoute) {
                // Closing the root leaves the app; the task stays alive so
                // returning is instant instead of a cold Lynx restart.
                activity.moveTaskToBack(true)
            } else {
                activity.finish()
                when {
                    activity.routeAnimation == ANIMATION_NONE ->
                        activity.overridePendingTransition(0, 0)
                    activity.routeAnimation == ANIMATION_FADE ||
                        activity.routePresentation == PRESENTATION_SHEET ->
                        activity.overridePendingTransition(
                            android.R.anim.fade_in,
                            android.R.anim.fade_out,
                        )
                }
            }
            callback.invoke("")
        }
    }

    companion object {
        private const val TAG = "AppRouteHandler"
        private const val UPDATE_LOADING_TEXT = "正在更新…"
        private val BUNDLE_NAME = Regex("^[a-z0-9][a-z0-9-]*$")
    }
}
