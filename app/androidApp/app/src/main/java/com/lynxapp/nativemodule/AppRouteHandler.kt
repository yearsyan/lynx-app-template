package com.lynxapp.nativemodule

import android.app.Activity
import android.content.Intent
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.ReadableMap
import com.lynxapp.activity.LynxPageActivity
import com.lynxapp.activity.TransparentLynxPageActivity
import com.lynxapp.autolink.router.LynxRouteHandler
import com.lynxapp.autolink.router.RouterModule.ANIMATION_DEFAULT
import com.lynxapp.autolink.router.RouterModule.ANIMATION_FADE
import com.lynxapp.autolink.router.RouterModule.ANIMATION_NONE
import com.lynxapp.autolink.router.RouterModule.PRESENTATION_PUSH
import com.lynxapp.autolink.router.RouterModule.PRESENTATION_SHEET
import com.lynxapp.autolink.router.RouterModule.isLynxRouteAnimation
import com.lynxapp.component.STATUS_BAR_STYLE_DARK_CONTENT
import com.lynxapp.component.isLynxStatusBarStyle
import org.json.JSONObject

/**
 * Host navigation behind the autolinked Router module: opens another Lynx
 * bundle in a real Android Activity. State on the calling Activity's route
 * (such as its animation) drives how close() undoes the transition.
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
            STATUS_BAR_STYLE_DARK_CONTENT,
        )
        if (!isLynxStatusBarStyle(statusBarStyle)) {
            callback.invoke("Invalid status bar style: $statusBarStyle")
            return
        }
        val params = options.getMap("params")?.toHashMap().orEmpty()
        activity.runOnUiThread {
            runCatching {
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
            }.onSuccess {
                callback.invoke("")
            }.onFailure { error ->
                callback.invoke(error.message ?: "Unable to open native route")
            }
        }
    }

    override fun close(activity: Activity, callback: Callback) {
        if (activity !is LynxPageActivity) {
            callback.invoke("The root route cannot be closed")
            return
        }
        activity.runOnUiThread {
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
            callback.invoke("")
        }
    }

    companion object {
        private val BUNDLE_NAME = Regex("^[a-z0-9][a-z0-9-]*$")
    }
}
