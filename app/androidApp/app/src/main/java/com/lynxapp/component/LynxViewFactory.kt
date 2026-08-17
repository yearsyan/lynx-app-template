package com.lynxapp.component

import android.app.Activity
import com.lynx.tasm.LynxBooleanOption
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynx.xelement.XElementBehaviors
import com.lynx.xelement.webview.BehaviorGenerator as WebViewBehaviorGenerator
import com.lynxapp.LynxAutolinkRegistry
import com.lynxapp.LynxBundleRepository
import com.lynxapp.LynxGenericResourceFetcher
import com.lynxapp.nativemodule.NativeBackController
import com.lynxapp.nativemodule.NativeBackModule
import com.lynxapp.nativemodule.NativeHapticsModule
import com.lynxapp.nativemodule.NativeRouterModule
import com.lynxapp.nativemodule.NativeStatusBarModule

/** Creates every app-owned LynxView with the same native module contract. */
internal fun Activity.createLynxView(
    bundleRepository: LynxBundleRepository,
    nativeBackController: NativeBackController,
): LynxView {
    val builder = LynxViewBuilder()
        .addBehaviors(XElementBehaviors().create())
        .addBehaviors(WebViewBehaviorGenerator.getBehaviors())
        .setTemplateProvider(bundleRepository)
    builder.setGenericResourceFetcher(LynxGenericResourceFetcher)
    builder.setEnableGenericResourceFetcher(LynxBooleanOption.TRUE)
    // WebSocket, MMKV storage and clipboard come from the autolink/*
    // workspace libraries; HarmonyOS hosts register their own instead.
    LynxAutolinkRegistry.setup(builder)
    builder.registerModule(NativeHapticsModule.NAME, NativeHapticsModule::class.java)
    builder.registerModule(
        NativeRouterModule.NAME,
        NativeRouterModule::class.java,
        this,
    )
    builder.registerModule(
        NativeStatusBarModule.NAME,
        NativeStatusBarModule::class.java,
        this,
    )
    builder.registerModule(
        NativeBackModule.NAME,
        NativeBackModule::class.java,
        nativeBackController,
    )
    return builder.build(this)
}
