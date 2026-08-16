package com.lynxapp.nativemodule

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback

/** One-shot impact haptics mapped to predefined vibration effects. */
class NativeHapticsModule(context: Context) : LynxModule(context) {
    private val vibrator =
        context.applicationContext.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    @LynxMethod
    fun impact(style: String, callback: Callback) {
        val target = vibrator
        if (target == null || !target.hasVibrator()) {
            callback.invoke("Vibrator is not available on this device")
            return
        }
        when (style) {
            IMPACT_LIGHT -> vibrate(target, VibrationEffect.EFFECT_TICK, DURATION_LIGHT_MS)
            IMPACT_MEDIUM -> vibrate(target, VibrationEffect.EFFECT_CLICK, DURATION_MEDIUM_MS)
            IMPACT_HEAVY -> vibrate(target, VibrationEffect.EFFECT_HEAVY_CLICK, DURATION_HEAVY_MS)
            else -> {
                callback.invoke("Invalid haptic impact style: $style")
                return
            }
        }
        callback.invoke("")
    }

    private fun vibrate(target: Vibrator, predefinedEffect: Int, fallbackDurationMs: Long) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            target.vibrate(VibrationEffect.createPredefined(predefinedEffect))
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            target.vibrate(
                VibrationEffect.createOneShot(
                    fallbackDurationMs,
                    VibrationEffect.DEFAULT_AMPLITUDE,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            target.vibrate(fallbackDurationMs)
        }
    }

    companion object {
        const val NAME = "NativeHapticsModule"
        const val IMPACT_LIGHT = "light"
        const val IMPACT_MEDIUM = "medium"
        const val IMPACT_HEAVY = "heavy"
        private const val DURATION_LIGHT_MS = 15L
        private const val DURATION_MEDIUM_MS = 30L
        private const val DURATION_HEAVY_MS = 60L
    }
}
