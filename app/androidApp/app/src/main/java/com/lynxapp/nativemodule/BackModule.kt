package com.lynxapp.nativemodule

import android.app.Activity
import android.os.Build
import android.window.BackEvent
import android.window.OnBackAnimationCallback
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.annotation.RequiresApi
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.JavaOnlyArray
import com.lynx.react.bridge.JavaOnlyMap
import com.lynx.tasm.LynxView

/**
 * Activity-owned back dispatcher shared with the page's BackModule.
 *
 * The enabled bit is updated before a system gesture begins. This keeps the
 * platform decision synchronous while JS receives lifecycle events later.
 */
class NativeBackController(private val activity: Activity) {
    private var lynxView: LynxView? = null
    private var enabled = false
    private var platformCallback: Any? = null
    private var gestureStarted = false
    private var lastProgress = 0.0
    private var lastTouchX = 0.0
    private var lastTouchY = 0.0
    private var lastEdge = EDGE_NONE

    fun attach(lynxView: LynxView) {
        this.lynxView = lynxView
    }

    fun setEnabled(nextEnabled: Boolean) {
        if (enabled == nextEnabled) {
            return
        }
        if (!nextEnabled && gestureStarted) {
            emit(
                phase = PHASE_CANCEL,
                progress = lastProgress,
                source = SOURCE_GESTURE,
                edge = lastEdge,
                touchX = lastTouchX,
                touchY = lastTouchY,
            )
            resetGesture()
        }
        enabled = nextEnabled
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (nextEnabled) {
                registerPlatformCallback()
            } else {
                unregisterPlatformCallback()
            }
        }
    }

    /** Called by Activity.onBackPressed for Android 12L and earlier. */
    fun handleLegacyBack(): Boolean {
        if (!enabled) {
            return false
        }
        emitDiscreteBack(SOURCE_SYSTEM)
        return true
    }

    fun destroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            unregisterPlatformCallback()
        }
        enabled = false
        gestureStarted = false
        lynxView = null
    }

    private fun registerPlatformCallback() {
        if (platformCallback != null) {
            return
        }
        platformCallback = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            Api34.createAndRegister(activity, this)
        } else {
            Api33.createAndRegister(activity, this)
        }
    }

    private fun unregisterPlatformCallback() {
        val callback = platformCallback ?: return
        Api33.unregister(activity, callback)
        platformCallback = null
        resetGesture()
    }

    private fun emitDiscreteBack(source: String) {
        emit(
            phase = PHASE_START,
            progress = 0.0,
            source = source,
            edge = EDGE_NONE,
            touchX = 0.0,
            touchY = 0.0,
        )
        emit(
            phase = PHASE_COMMIT,
            progress = 1.0,
            source = source,
            edge = EDGE_NONE,
            touchX = 0.0,
            touchY = 0.0,
        )
    }

    private fun onBackStarted(event: BackEvent) {
        gestureStarted = true
        updateGesture(event)
        emitCurrent(PHASE_START)
    }

    private fun onBackProgressed(event: BackEvent) {
        if (!gestureStarted) {
            gestureStarted = true
            updateGesture(event)
            emitCurrent(PHASE_START)
        } else {
            updateGesture(event)
        }
        emitCurrent(PHASE_PROGRESS)
    }

    private fun onBackCancelled() {
        if (!gestureStarted) {
            return
        }
        emitCurrent(PHASE_CANCEL)
        resetGesture()
    }

    private fun onBackInvoked() {
        if (gestureStarted) {
            emit(
                phase = PHASE_COMMIT,
                progress = 1.0,
                source = SOURCE_GESTURE,
                edge = lastEdge,
                touchX = lastTouchX,
                touchY = lastTouchY,
            )
            resetGesture()
        } else {
            emitDiscreteBack(SOURCE_SYSTEM)
        }
    }

    private fun updateGesture(event: BackEvent) {
        lastProgress = event.progress.toDouble().coerceIn(0.0, 1.0)
        lastTouchX = event.touchX.toDouble()
        lastTouchY = event.touchY.toDouble()
        lastEdge = when (event.swipeEdge) {
            BackEvent.EDGE_LEFT -> EDGE_LEFT
            BackEvent.EDGE_RIGHT -> EDGE_RIGHT
            else -> EDGE_NONE
        }
    }

    private fun emitCurrent(phase: String) {
        emit(
            phase = phase,
            progress = lastProgress,
            source = SOURCE_GESTURE,
            edge = lastEdge,
            touchX = lastTouchX,
            touchY = lastTouchY,
        )
    }

    private fun resetGesture() {
        gestureStarted = false
        lastProgress = 0.0
        lastTouchX = 0.0
        lastTouchY = 0.0
        lastEdge = EDGE_NONE
    }

    private fun emit(
        phase: String,
        progress: Double,
        source: String,
        edge: String,
        touchX: Double,
        touchY: Double,
    ) {
        val payload = JavaOnlyMap().apply {
            putString("platform", PLATFORM_ANDROID)
            putString("phase", phase)
            putDouble("progress", progress.coerceIn(0.0, 1.0))
            putString("source", source)
            putString("edge", edge)
            putDouble("touchX", touchX)
            putDouble("touchY", touchY)
        }
        lynxView?.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload))
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private object Api33 {
        fun createAndRegister(
            activity: Activity,
            controller: NativeBackController,
        ): OnBackInvokedCallback {
            val callback = OnBackInvokedCallback(controller::onBackInvoked)
            activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                callback,
            )
            return callback
        }

        fun unregister(activity: Activity, callback: Any) {
            activity.onBackInvokedDispatcher.unregisterOnBackInvokedCallback(
                callback as OnBackInvokedCallback,
            )
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private object Api34 {
        fun createAndRegister(
            activity: Activity,
            controller: NativeBackController,
        ): OnBackAnimationCallback {
            val callback = object : OnBackAnimationCallback {
                override fun onBackStarted(backEvent: BackEvent) {
                    controller.onBackStarted(backEvent)
                }

                override fun onBackProgressed(backEvent: BackEvent) {
                    controller.onBackProgressed(backEvent)
                }

                override fun onBackCancelled() {
                    controller.onBackCancelled()
                }

                override fun onBackInvoked() {
                    controller.onBackInvoked()
                }
            }
            activity.onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                callback,
            )
            return callback
        }
    }

    companion object {
        const val EVENT_NAME = "back"
        private const val PLATFORM_ANDROID = "android"
        private const val PHASE_START = "start"
        private const val PHASE_PROGRESS = "progress"
        private const val PHASE_CANCEL = "cancel"
        private const val PHASE_COMMIT = "commit"
        private const val SOURCE_SYSTEM = "system"
        private const val SOURCE_GESTURE = "gesture"
        private const val EDGE_LEFT = "left"
        private const val EDGE_RIGHT = "right"
        private const val EDGE_NONE = "none"
    }
}

/** Lets the current Lynx page synchronously opt in or out of native back interception. */
class BackModule(context: android.content.Context, param: Any?) : LynxModule(context, param) {
    private val activity = findActivity(context)
    private val controller = param as? NativeBackController

    private fun findActivity(context: android.content.Context?): Activity? {
        var current = context
        while (current is android.content.ContextWrapper) {
            if (current is Activity) return current
            current = current.baseContext
        }
        return null
    }

    @LynxMethod
    fun setEnabled(enabled: Boolean, callback: Callback) {
        val host = activity
        val backController = controller
        if (host == null || backController == null) {
            callback.invoke("Back has no Activity host")
            return
        }
        host.runOnUiThread {
            backController.setEnabled(enabled)
            callback.invoke("")
        }
    }

    override fun destroy() {
        activity?.runOnUiThread {
            controller?.setEnabled(false)
        }
        super.destroy()
    }

    companion object {
        const val NAME = "Back"
    }
}
