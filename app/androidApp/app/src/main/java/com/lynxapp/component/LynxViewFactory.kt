package com.lynxapp.component

import android.app.Activity
import com.lynx.tasm.LynxBooleanOption
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynx.xelement.XElementBehaviors
import com.lynxapp.LynxAutolinkRegistry
import com.lynxapp.LynxBundleRepository
import com.lynxapp.LynxGenericResourceFetcher
import com.lynxapp.nativemodule.NativeBackController
import com.lynxapp.nativemodule.BackModule
import com.lynxapp.nativemodule.StatusBarModule

/** Creates every app-owned LynxView with the same native module contract. */
internal fun Activity.createLynxView(
    bundleRepository: LynxBundleRepository,
    nativeBackController: NativeBackController,
): LynxView {
    val webviewBridgeAdapter = WebviewModuleBridgeHostAdapter()
    val builder = webviewBridgeAdapter.builder
    builder.addBehaviors(XElementBehaviors().create())
    builder.setTemplateProvider(bundleRepository)
    builder.setGenericResourceFetcher(LynxGenericResourceFetcher)
    builder.setEnableGenericResourceFetcher(LynxBooleanOption.TRUE)
    // Router, WebSocket, MMKV storage, clipboard and haptics come from the
    // autolink/* workspace libraries; HarmonyOS hosts register their own
    // instead. The Router's host navigation installs once in the Application.
    LynxAutolinkRegistry.setup(builder)
    builder.registerModule(
        StatusBarModule.NAME,
        StatusBarModule::class.java,
        this,
    )
    builder.registerModule(
        BackModule.NAME,
        BackModule::class.java,
        nativeBackController,
    )
    return builder.build(this).also(webviewBridgeAdapter::attach)
}
