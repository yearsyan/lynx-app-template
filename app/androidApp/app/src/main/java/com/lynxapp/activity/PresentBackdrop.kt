package com.lynxapp.activity

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RenderEffect
import android.graphics.Shader
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.view.animation.AnimationUtils
import android.view.animation.Interpolator
import android.widget.ImageView

/** Per-phase content choreography resolved by the native route handler. */
internal data class PresentContentAnimationOptions(
    val opacity: Boolean = false,
    val push: Boolean = true,
) {
    val isEnabled: Boolean
        get() = opacity || push
}

/**
 * Simulates an iOS-style present transition for an opaque Lynx page. The
 * previous page's snapshot is installed as the window background and a
 * fullscreen backdrop layer before the first frame, so opening with no system
 * transition is imperceptible; when the Lynx content paints its first screen
 * the backdrop shrinks with rounded corners while the content slides in.
 * Dismissing reverses both before the page really closes, so the revealed
 * previous page stays pixel-aligned with the restored snapshot.
 *
 * The backdrop and content choreographies can be cleared independently, and a
 * blurred backdrop is captured at reduced resolution (no pixel alignment is
 * attempted) with the blur applied by RenderEffect where available.
 */
internal class PresentBackdrop(
    private val activity: Activity,
    private val bitmap: Bitmap,
    scrimColor: Int? = null,
    private val backdropTransition: Boolean = true,
    private val enterAnimation: PresentContentAnimationOptions = PresentContentAnimationOptions(),
    private val exitAnimation: PresentContentAnimationOptions = PresentContentAnimationOptions(),
    blurred: Boolean = false,
) {
    private val easing: Interpolator =
        AnimationUtils.loadInterpolator(activity, android.R.interpolator.fast_out_slow_in)
    private val cornerRadiusMax = CORNER_RADIUS_DP * activity.resources.displayMetrics.density

    private var choreography: ValueAnimator? = null
    private var presented = false
    private var interactiveDismissReady = false
    private var interactiveDismissFraction: Float? = null
    private val playsPresentChoreography = backdropTransition || enterAnimation.isEnabled
    private val playsDismissChoreography = backdropTransition || exitAnimation.isEnabled

    // Below API 31 (no RenderEffect) the blur is baked into a copy of the
    // downscaled bitmap; the original stays untouched for recycling.
    private val displayedBitmap: Bitmap =
        if (blurred && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            blurBitmap(bitmap, BLUR_RADIUS_FALLBACK)
        } else {
            bitmap
        }

    /** Fullscreen snapshot layer that sits behind the transparent LynxView. */
    val view: View = ImageView(activity).apply {
        scaleType = ImageView.ScaleType.FIT_XY
        setImageBitmap(displayedBitmap)
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                // Constant top-only corners (iOS containerConcentric style):
                // present from the first frame instead of animating in with the
                // shrink. Outline coordinates live in view space, so the radius
                // scales together with the snapshot via the scale transform.
                // The bottom corners stay square where the snapshot meets the
                // screen bottom. The two rounded corners keep the path convex.
                outline.setConvexPath(
                    topRoundedRectPath(
                        view.width.toFloat(),
                        view.height.toFloat(),
                        cornerRadiusMax,
                    )
                )
            }
        }
        clipToOutline = true
        if (blurred && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setRenderEffect(
                RenderEffect.createBlurEffect(
                    BLUR_RADIUS,
                    BLUR_RADIUS,
                    Shader.TileMode.CLAMP,
                ),
            )
        }
    }

    /**
     * Stationary dim layer between the snapshot and the content. The color
     * carries the dimming alpha; the choreography only fades the layer itself
     * in place. When neither transition plays the scrim is static from the
     * first frame.
     */
    val scrim: View = View(activity).apply {
        setBackgroundColor(scrimColor ?: DEFAULT_SCRIM_COLOR)
        alpha = if (playsPresentChoreography) 0f else 1f
    }

    init {
        // The window background paints before the content view exists, so the
        // very first frame already shows the snapshot instead of the theme
        // background flashing through.
        activity.window.setBackgroundDrawable(BitmapDrawable(activity.resources, displayedBitmap))
    }

    /** Applies the enter start state before the content paints its first screen. */
    fun prepareContent(content: View) {
        applyContent(0f, content, enterAnimation)
    }

    /** Plays the open choreography once the content has painted its first screen. */
    fun playPresent(content: View) {
        if (presented) {
            return
        }
        presented = true
        interactiveDismissReady = false
        applyChoreography(0f, content, enterAnimation)
        if (!playsPresentChoreography) {
            applyChoreography(1f, content, enterAnimation)
            interactiveDismissReady = true
            return
        }
        if (backdropTransition) {
            // The backdrop still covers the whole window, so swapping the
            // snapshot window background for the solid margin color is
            // invisible here; the margins reveal it as the backdrop shrinks.
            activity.window.setBackgroundDrawable(ColorDrawable(BACKDROP_BACKGROUND))
        }
        animateChoreography(
            0f,
            1f,
            content,
            enterAnimation,
            onEnd = { interactiveDismissReady = true },
        )
    }

    /** Starts predictive Back at the fully presented choreography state. */
    fun beginInteractiveDismiss(content: View): Boolean {
        if (!presented || !interactiveDismissReady || !playsDismissChoreography) {
            return false
        }
        choreography?.cancel()
        choreography = null
        interactiveDismissReady = false
        interactiveDismissFraction = 1f
        applyChoreography(1f, content, exitAnimation)
        return true
    }

    /** Maps Android predictive Back progress onto the reverse choreography. */
    fun updateInteractiveDismiss(progress: Float, content: View) {
        if (interactiveDismissFraction == null) return
        val fraction = 1f - progress.coerceIn(0f, 1f)
        interactiveDismissFraction = fraction
        applyChoreography(fraction, content, exitAnimation)
    }

    /** Springs a cancelled predictive Back gesture to the presented state. */
    fun cancelInteractiveDismiss(content: View) {
        val fraction = interactiveDismissFraction ?: return
        interactiveDismissFraction = null
        animateChoreography(
            fraction,
            1f,
            content,
            exitAnimation,
            onEnd = { interactiveDismissReady = true },
            durationMs = interactiveDuration(1f - fraction),
        )
    }

    /** Completes predictive Back from its current progress. */
    fun finishInteractiveDismiss(content: View, onEnd: () -> Unit) {
        val fraction = interactiveDismissFraction
        if (fraction == null) {
            playDismiss(content, onEnd)
            return
        }
        interactiveDismissFraction = null
        interactiveDismissReady = false
        animateChoreography(
            fraction,
            0f,
            content,
            exitAnimation,
            onEnd = onEnd,
            durationMs = interactiveDuration(fraction),
        )
    }

    /**
     * Reverses the open choreography and reports completion, so the page can
     * close over a fullscreen, pixel-aligned snapshot with no system
     * transition. Before the first screen there is nothing to animate.
     */
    fun playDismiss(content: View, onEnd: () -> Unit) {
        interactiveDismissReady = false
        interactiveDismissFraction = null
        if (!presented) {
            onEnd()
            return
        }
        if (!playsDismissChoreography) {
            onEnd()
            return
        }
        // Every phase is identity + alpha 1 at fraction 1, so selecting an
        // independently configured exit phase cannot jump the visible page.
        applyChoreography(1f, content, exitAnimation)
        animateChoreography(1f, 0f, content, exitAnimation, onEnd)
    }

    /** Detaches the layers and frees the snapshot bitmap. */
    fun release() {
        choreography?.cancel()
        choreography = null
        (view.parent as? ViewGroup)?.removeView(view)
        (view as ImageView).setImageDrawable(null)
        (scrim.parent as? ViewGroup)?.removeView(scrim)
        // Swap in a plain background before recycling: the old drawable still
        // holds the bitmap and the window may draw its background once more.
        activity.window.setBackgroundDrawable(ColorDrawable(BACKDROP_BACKGROUND))
        if (displayedBitmap !== bitmap) {
            displayedBitmap.recycle()
        }
        bitmap.recycle()
    }

    private fun animateChoreography(
        from: Float,
        to: Float,
        content: View,
        contentAnimation: PresentContentAnimationOptions,
        onEnd: (() -> Unit)? = null,
        durationMs: Long = DURATION_MS,
    ) {
        choreography?.cancel()
        val animator = ValueAnimator.ofFloat(from, to)
        animator.duration = durationMs
        animator.interpolator = easing
        animator.addUpdateListener { animation ->
            applyChoreography(animation.animatedValue as Float, content, contentAnimation)
        }
        if (onEnd != null) {
            animator.addListener(object : AnimatorListenerAdapter() {
                private var cancelled = false

                override fun onAnimationCancel(animation: Animator) {
                    cancelled = true
                }

                override fun onAnimationEnd(animation: Animator) {
                    if (!cancelled) {
                        onEnd()
                    }
                }
            })
        }
        choreography = animator
        animator.start()
    }

    private fun interactiveDuration(distance: Float): Long =
        (DURATION_MS.toFloat() * distance.coerceIn(0f, 1f))
            .toLong()
            .coerceAtLeast(MIN_INTERACTIVE_DURATION_MS)

    private fun applyChoreography(
        fraction: Float,
        content: View,
        contentAnimation: PresentContentAnimationOptions,
    ) {
        if (backdropTransition) {
            val scale = 1f - BACKDROP_SHIFT * fraction
            view.scaleX = scale
            view.scaleY = scale
            // Shift down by half the scale shift: exactly cancels the scale's
            // bottom inset, so the snapshot's bottom edge stays flush with the
            // screen bottom (no black gap) while its top edge drops below the
            // status bar.
            view.translationY = view.height * BACKDROP_SHIFT / 2f * fraction
        }
        scrim.alpha = if (backdropTransition || contentAnimation.isEnabled) fraction else 1f
        applyContent(fraction, content, contentAnimation)
    }

    private fun applyContent(
        fraction: Float,
        content: View,
        animation: PresentContentAnimationOptions,
    ) {
        val travelDistance = maxOf(
            content.height,
            activity.window.decorView.height,
            activity.resources.displayMetrics.heightPixels,
        ).toFloat()
        content.translationY = if (animation.push) travelDistance * (1f - fraction) else 0f
        content.alpha = if (animation.opacity) fraction else 1f
    }

    companion object {
        private const val DURATION_MS = 350L
        private const val MIN_INTERACTIVE_DURATION_MS = 80L
        private const val BACKDROP_SHIFT = 0.08f
        private const val CORNER_RADIUS_DP = 12f

        /** Default scrim: 35% black ('#59000000'). */
        private val DEFAULT_SCRIM_COLOR = 0x59000000.toInt()

        /** Solid color the margins expose once the snapshot shrinks. */
        private const val BACKDROP_BACKGROUND = 0xFF000000.toInt()

        /** Blurred backdrops give up pixel alignment, so they capture small. */
        private const val BLURRED_CAPTURE_SCALE = 1f / 3f
        private const val BLUR_RADIUS = 25f
        private const val BLUR_RADIUS_FALLBACK = 10

        /**
         * Copies the composited window pixels of [activity]; the decor is
         * drawn into the bitmap below API 26 where PixelCopy is unavailable.
         * Blurred backdrops are captured at [BLURRED_CAPTURE_SCALE] since no
         * pixel alignment is needed. Invokes [onReady] with null when the
         * window has no surface to copy.
         */
        fun capture(activity: Activity, blurred: Boolean, onReady: (Bitmap?) -> Unit) {
            val window = activity.window
            val decor = window?.decorView
            if (window == null || decor == null || decor.width <= 0 || decor.height <= 0) {
                onReady(null)
                return
            }
            val scale = if (blurred) BLURRED_CAPTURE_SCALE else 1f
            val width = (decor.width * scale).toInt().coerceAtLeast(1)
            val height = (decor.height * scale).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                PixelCopy.request(
                    window,
                    Rect(0, 0, decor.width, decor.height),
                    bitmap,
                    { result ->
                        if (result == PixelCopy.SUCCESS) {
                            onReady(bitmap)
                        } else {
                            bitmap.recycle()
                            onReady(null)
                        }
                    },
                    Handler(Looper.getMainLooper()),
                )
            } else {
                val canvas = Canvas(bitmap)
                canvas.scale(scale, scale)
                decor.draw(canvas)
                onReady(bitmap)
            }
        }

        /** Pre-31 blur fallback: two separable box-blur iterations on the small bitmap. */
        private fun blurBitmap(source: Bitmap, radius: Int): Bitmap {
            val width = source.width
            val height = source.height
            val pixels = IntArray(width * height)
            source.getPixels(pixels, 0, width, 0, 0, width, height)
            boxBlur(pixels, width, height, radius, true)
            boxBlur(pixels, width, height, radius, false)
            boxBlur(pixels, width, height, radius, true)
            boxBlur(pixels, width, height, radius, false)
            val blurred = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            blurred.setPixels(pixels, 0, width, 0, 0, width, height)
            return blurred
        }

        /** Rectangle with only the top two corners rounded; stays convex. */
        private fun topRoundedRectPath(width: Float, height: Float, radius: Float): Path {
            val r = radius.coerceAtMost(width / 2f).coerceAtMost(height / 2f)
            return Path().apply {
                moveTo(0f, r)
                quadTo(0f, 0f, r, 0f)
                lineTo(width - r, 0f)
                quadTo(width, 0f, width, r)
                lineTo(width, height)
                lineTo(0f, height)
                close()
            }
        }

        private fun boxBlur(pixels: IntArray, width: Int, height: Int, radius: Int, horizontal: Boolean) {
            val outer = if (horizontal) height else width
            val inner = if (horizontal) width else height
            val window = radius * 2 + 1
            val line = IntArray(inner)
            for (o in 0 until outer) {
                for (i in 0 until inner) {
                    line[i] = pixels[if (horizontal) o * width + i else i * width + o]
                }
                var alpha = 0
                var red = 0
                var green = 0
                var blue = 0
                for (i in -radius..radius) {
                    val pixel = line[i.coerceIn(0, inner - 1)]
                    alpha += pixel ushr 24
                    red += (pixel shr 16) and 0xFF
                    green += (pixel shr 8) and 0xFF
                    blue += pixel and 0xFF
                }
                for (i in 0 until inner) {
                    pixels[if (horizontal) o * width + i else i * width + o] =
                        (alpha / window shl 24) or (red / window shl 16) or
                        (green / window shl 8) or (blue / window)
                    val removed = line[(i - radius).coerceAtLeast(0)]
                    val added = line[(i + radius + 1).coerceAtMost(inner - 1)]
                    alpha += (added ushr 24) - (removed ushr 24)
                    red += ((added shr 16) and 0xFF) - ((removed shr 16) and 0xFF)
                    green += ((added shr 8) and 0xFF) - ((removed shr 8) and 0xFF)
                    blue += (added and 0xFF) - (removed and 0xFF)
                }
            }
        }
    }
}
