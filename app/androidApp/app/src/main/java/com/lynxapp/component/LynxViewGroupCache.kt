package com.lynxapp.component

import android.content.Context
import com.lynx.tasm.group.ILynxViewGroup
import com.lynx.tasm.group.LynxViewGroupBuilder
import com.lynx.tasm.resourceprovider.template.LynxTemplateResourceFetcher
import java.util.concurrent.ConcurrentHashMap

/**
 * Process-wide LynxViewGroups with engine caching enabled (Lynx 3.8+, SDK 4.0).
 *
 * Every LynxView created for the same bundle joins that bundle's group; when
 * such a view is destroyed its LynxEngine returns to the group instead of
 * being torn down, so re-entering the page reuses the warmed engine instead of
 * cold-creating one. Groups are keyed by bundle identity plus resolved URL and
 * live for the whole process: the retained engines are bounded by the number
 * of distinct bundle URLs the app renders, and the SDK does not support
 * releasing a group that still has views.
 *
 * A grouped view never queries its own AbsTemplateProvider for
 * renderTemplateUrl: the group performs the template fetch through the
 * supplied LynxTemplateResourceFetcher and caches the parsed TemplateBundle
 * for its lifetime. Keying by URL keeps that cache coherent — switching the
 * dev server URL or applying an OTA cache resolves to a different URL, so the
 * next view joins a fresh group that fetches the new bytes instead of
 * reusing the previous bundle. Shared modules stay disabled (the default), so
 * the Activity-scoped modules registered per view in LynxViewFactory are never
 * shared across views.
 */
object LynxViewGroupCache {
    private val groups = ConcurrentHashMap<String, ILynxViewGroup>()

    fun groupFor(
        context: Context,
        bundleKey: String,
        url: String?,
        fetcher: LynxTemplateResourceFetcher,
    ): ILynxViewGroup =
        groups.getOrPut("$bundleKey|${url.orEmpty()}") {
            val builder = LynxViewGroupBuilder()
                .setContext(context.applicationContext)
            if (url != null) builder.setUrl(url)
            builder.setTemplateResourceFetcher(fetcher)
            builder
                .setEnableCacheEngine(true)
                .build()
        }
}
