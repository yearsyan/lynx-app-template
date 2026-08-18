package com.lynxapp.component

import android.content.Context
import com.lynx.tasm.group.ILynxViewGroup
import com.lynx.tasm.group.LynxViewGroupBuilder
import java.util.concurrent.ConcurrentHashMap

/**
 * Process-wide LynxViewGroups with engine caching enabled (Lynx 3.8+, SDK 4.0).
 *
 * Every LynxView created for the same bundle joins that bundle's group; when
 * such a view is destroyed its LynxEngine returns to the group instead of
 * being torn down, so re-entering the page reuses the warmed engine instead of
 * cold-creating one. Groups are keyed by bundle identity and live for the
 * whole process: the retained engines are bounded by the app's bundle count,
 * and the SDK does not support releasing a group that still has views.
 *
 * Views keep rendering through their own template provider; the group's URL is
 * bookkeeping only. Shared modules stay disabled (the default), so the
 * Activity-scoped modules registered per view in LynxViewFactory are never
 * shared across views.
 */
object LynxViewGroupCache {
    private val groups = ConcurrentHashMap<String, ILynxViewGroup>()

    fun groupFor(context: Context, bundleKey: String, url: String?): ILynxViewGroup =
        groups.getOrPut(bundleKey) {
            val builder = LynxViewGroupBuilder()
                .setContext(context.applicationContext)
            if (url != null) builder.setUrl(url)
            builder
                .setEnableCacheEngine(true)
                .build()
        }
}
