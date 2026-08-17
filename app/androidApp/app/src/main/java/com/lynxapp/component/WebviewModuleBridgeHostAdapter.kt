package com.lynxapp.component

import com.lynx.jsbridge.LynxModule
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynxapp.autolink.webviewbridge.ModuleBridgeEntry
import com.lynxapp.autolink.webviewbridge.ModuleBridgeHostRegistry

/**
 * Explicit app adapter for the autolinked `<module-webview>` element.
 *
 * It records the exact module registrations installed on this LynxView and
 * attaches that same registry after the view is built. The native component
 * itself remains app-agnostic and owns no duplicate module list.
 */
internal class WebviewModuleBridgeHostAdapter {
    val builder = RecordingLynxViewBuilder()

    fun attach(view: LynxView) {
        ModuleBridgeHostRegistry.attach(view, builder.recordedModules)
    }
}

internal class RecordingLynxViewBuilder : LynxViewBuilder() {
    private val recorded = mutableListOf<ModuleBridgeEntry>()

    val recordedModules: List<ModuleBridgeEntry>
        get() = recorded.toList()

    override fun registerModule(name: String, moduleClass: Class<out LynxModule>) {
        recorded.add(ModuleBridgeEntry(name, moduleClass, null))
        super.registerModule(name, moduleClass)
    }

    override fun registerModule(name: String, moduleClass: Class<out LynxModule>, param: Any?) {
        recorded.add(ModuleBridgeEntry(name, moduleClass, param))
        super.registerModule(name, moduleClass, param)
    }
}
