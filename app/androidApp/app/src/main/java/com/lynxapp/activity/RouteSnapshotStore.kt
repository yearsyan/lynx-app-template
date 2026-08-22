package com.lynxapp.activity

import android.graphics.Bitmap

/**
 * Hands the present-route snapshot from the opening Activity to the page being
 * opened. Both live in the same process, so an in-memory slot is enough; after
 * a process-death replay the slot is empty and the page falls back to its
 * solid background.
 */
internal object RouteSnapshotStore {
    @Volatile
    private var snapshot: Bitmap? = null

    fun put(bitmap: Bitmap) {
        snapshot?.recycle()
        snapshot = bitmap
    }

    fun consume(): Bitmap? {
        val bitmap = snapshot
        snapshot = null
        return bitmap
    }
}
