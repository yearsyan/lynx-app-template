package com.lynxapp.autolink.webviewbridge

import com.lynx.jsbridge.LynxModule
import com.lynx.tasm.LynxView
import com.lynx.tasm.behavior.LynxContext

/** One native-module registration captured from the owning LynxView builder. */
data class ModuleBridgeEntry(
    val name: String,
    val moduleClass: Class<out LynxModule>,
    val param: Any?,
)

/**
 * Per-view hand-off between the explicit host adapter and the autolinked
 * `<module-webview>` element. The registry is stored on LynxContext, so it has
 * the same lifetime and ownership boundary as the LynxView itself.
 */
object ModuleBridgeHostRegistry {
    private const val REGISTRY_KEY = "lynx.module-webview.module-registry"

    @JvmStatic
    fun attach(view: LynxView, entries: List<ModuleBridgeEntry>) {
        view.lynxContext.putSharedData(REGISTRY_KEY, entries.toList())
    }

    @JvmStatic
    @Suppress("UNCHECKED_CAST")
    fun entriesFor(context: LynxContext): List<ModuleBridgeEntry> =
        context.getSharedData(REGISTRY_KEY) as? List<ModuleBridgeEntry> ?: emptyList()
}
