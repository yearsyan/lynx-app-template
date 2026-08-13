package com.lynxapp

import android.app.Activity
import android.widget.FrameLayout

/** Release no-op: the settings Activity and UI are absent from this source set. */
object DebugSettingsEntry {
    @Suppress("UNUSED_PARAMETER")
    fun attach(activity: Activity, root: FrameLayout) = Unit
}
