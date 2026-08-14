package com.lynxapp.component

import android.app.Activity
import com.lynx.tasm.LynxBooleanOption
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynx.xelement.XElementBehaviors
import com.lynx.xelement.webview.BehaviorGenerator as WebViewBehaviorGenerator
import com.lynxapp.LynxBundleRepository
import com.lynxapp.LynxGenericResourceFetcher
import com.lynxapp.nativemodule.NativeBackController
import com.lynxapp.nativemodule.NativeBackModule
import com.lynxapp.nativemodule.NativeKVModule
import com.lynxapp.nativemodule.NativeRouterModule
import com.lynxapp.nativemodule.NativeWebSocketController
import com.lynxapp.nativemodule.NativeWebSocketModule

/** Creates every app-owned LynxView with the same native module contract. */
internal fun Activity.createLynxView(
    bundleRepository: LynxBundleRepository,
    nativeBackController: NativeBackController,
    nativeWebSocketController: NativeWebSocketController,
): LynxView {
    val builder = LynxViewBuilder()
        .addBehaviors(XElementBehaviors().create())
        .addBehaviors(WebViewBehaviorGenerator.getBehaviors())
        .setTemplateProvider(bundleRepository)
    builder.setGenericResourceFetcher(LynxGenericResourceFetcher)
    builder.setEnableGenericResourceFetcher(LynxBooleanOption.TRUE)
    builder.registerModule(NativeKVModule.NAME, NativeKVModule::class.java)
    builder.registerModule(
        NativeRouterModule.NAME,
        NativeRouterModule::class.java,
        this,
    )
    builder.registerModule(
        NativeBackModule.NAME,
        NativeBackModule::class.java,
        nativeBackController,
    )
    builder.registerModule(
        NativeWebSocketModule.NAME,
        NativeWebSocketModule::class.java,
        nativeWebSocketController,
    )
    return builder.build(this)
}
