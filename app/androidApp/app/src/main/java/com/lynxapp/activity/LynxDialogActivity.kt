package com.lynxapp.activity

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.ViewConfiguration
import android.view.WindowManager
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import com.lynxapp.autolink.device.DeviceSystemUI
import com.lynxapp.autolink.navigation.NavigationModule

/**
 * Android-only route host backed by a dedicated, floating dialog Window.
 *
 * The Lynx content determines this bottom Window's height. The Window always
 * uses `adjustResize`, follows the IME during dismissal, and only finishes once
 * the IME inset has reached zero.
 */
class LynxDialogActivity : LynxPageActivity() {
    private var firstScreenReady = false
    private var hasPresentedIme = false
    private var lastImeBottom = 0
    private var lastImeVisible = false
    private var finishRequested = false
    private var finishingImmediately = false
    private var imeAnimationRunning = false

    private val enableOutsideDismiss = Runnable {
        if (!isFinishing) setFinishOnTouchOutside(true)
    }

    private val finishAfterImeSettled = Runnable {
        if (!imeAnimationRunning && !isImeActive()) finishImmediately()
    }

    private val imeAnimationCallback = object : WindowInsetsAnimationCompat.Callback(
        WindowInsetsAnimationCompat.Callback.DISPATCH_MODE_CONTINUE_ON_SUBTREE,
    ) {
        override fun onPrepare(animation: WindowInsetsAnimationCompat) {
            if (animation.isImeAnimation()) imeAnimationRunning = true
        }

        override fun onProgress(
            insets: WindowInsetsCompat,
            runningAnimations: MutableList<WindowInsetsAnimationCompat>,
        ): WindowInsetsCompat {
            handleImeInsets(insets)
            return insets
        }

        override fun onEnd(animation: WindowInsetsAnimationCompat) {
            if (animation.isImeAnimation()) imeAnimationRunning = false
            ViewCompat.getRootWindowInsets(window.decorView)?.let(::handleImeInsets)
            scheduleFinishIfImeSettled()
        }
    }

    override val usesTransparentPageBackground: Boolean
        get() = true

    override val routeContentHeight: Int
        get() = ViewGroup.LayoutParams.WRAP_CONTENT

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Some dialog themes reapply their default width after content attach.
        // Keep the route full width but let Lynx's measured content own height.
        window.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        observeImeInsets()
    }

    override fun configureRouteWindow() {
        WindowCompat.setDecorFitsSystemWindows(window, true)
        window.setGravity(Gravity.BOTTOM)
        window.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        // The launch gesture can finish after this Window is already visible
        // and above the IME. Do not interpret that same ACTION_UP as an outside
        // tap; arm the normal platform dismissal after the gesture timeout.
        setFinishOnTouchOutside(false)
        DeviceSystemUI.setStatusBarStyle(this, statusBarStyle)
        WindowCompat.getInsetsController(window, window.decorView)
            .isAppearanceLightNavigationBars = true

        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setDimAmount(DEFAULT_DIM_AMOUNT)
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun onLynxFirstScreen() {
        firstScreenReady = true
        window.decorView.removeCallbacks(enableOutsideDismiss)
        window.decorView.postDelayed(
            enableOutsideDismiss,
            ViewConfiguration.getLongPressTimeout().toLong(),
        )
        ViewCompat.getRootWindowInsets(window.decorView)?.let(::handleImeInsets)
        showInitialImeWhenReady()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) showInitialImeWhenReady()
    }

    private fun showInitialImeWhenReady() {
        if (!firstScreenReady || !hasWindowFocus()) return
        // A show request issued during Activity startup can be ignored before
        // the Window and Lynx editor are connected. Post it after both gates.
        window.decorView.post {
            if (!isFinishing && hasWindowFocus()) {
                WindowCompat.getInsetsController(window, window.decorView)
                    .show(WindowInsetsCompat.Type.ime())
            }
        }
    }

    private fun observeImeInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
            handleImeInsets(insets)
            insets
        }
        ViewCompat.setWindowInsetsAnimationCallback(
            window.decorView,
            imeAnimationCallback,
        )
        ViewCompat.requestApplyInsets(window.decorView)
    }

    private fun handleImeInsets(insets: WindowInsetsCompat) {
        val imeBottom = insets.getInsets(WindowInsetsCompat.Type.ime()).bottom
        val imeVisible = insets.isVisible(WindowInsetsCompat.Type.ime()) || imeBottom > 0
        lastImeBottom = imeBottom
        lastImeVisible = imeVisible

        if (firstScreenReady && hasWindowFocus() && imeVisible) {
            hasPresentedIme = true
        }
        if (
            firstScreenReady &&
            hasWindowFocus() &&
            (hasPresentedIme || finishRequested) &&
            !imeVisible &&
            imeBottom == 0 &&
            !imeAnimationRunning
        ) {
            scheduleFinishIfImeSettled()
        }
    }

    private fun WindowInsetsAnimationCompat.isImeAnimation(): Boolean =
        typeMask and WindowInsetsCompat.Type.ime() != 0

    private fun scheduleFinishIfImeSettled() {
        if (!firstScreenReady || !hasWindowFocus()) return
        if (!hasPresentedIme && !finishRequested) return
        window.decorView.removeCallbacks(finishAfterImeSettled)
        window.decorView.postOnAnimation(finishAfterImeSettled)
    }

    private fun isImeActive(): Boolean {
        val insets = ViewCompat.getRootWindowInsets(window.decorView)
        val currentBottom = insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom
            ?: lastImeBottom
        val currentlyVisible = insets?.isVisible(WindowInsetsCompat.Type.ime())
            ?: lastImeVisible
        return currentlyVisible || currentBottom > 0
    }

    private fun requestDismissAfterIme() {
        if (finishRequested) return
        finishRequested = true
        setFinishOnTouchOutside(false)
        WindowCompat.getInsetsController(window, window.decorView)
            .hide(WindowInsetsCompat.Type.ime())
    }

    override fun onDestroy() {
        window.decorView.removeCallbacks(enableOutsideDismiss)
        window.decorView.removeCallbacks(finishAfterImeSettled)
        ViewCompat.setOnApplyWindowInsetsListener(window.decorView, null)
        ViewCompat.setWindowInsetsAnimationCallback(window.decorView, null)
        super.onDestroy()
    }

    override fun finish() {
        if (finishingImmediately || isFinishing) return
        if (firstScreenReady && isImeActive()) {
            requestDismissAfterIme()
            return
        }
        finishImmediately()
    }

    private fun finishImmediately() {
        if (finishingImmediately || isFinishing) return
        finishingImmediately = true
        super.finish()
        when (routeAnimation) {
            NavigationModule.ANIMATION_NONE -> overridePendingTransition(0, 0)
            NavigationModule.ANIMATION_FADE -> overridePendingTransition(
                android.R.anim.fade_in,
                android.R.anim.fade_out,
            )
        }
    }

    private companion object {
        const val DEFAULT_DIM_AMOUNT = 0.45f
    }
}
