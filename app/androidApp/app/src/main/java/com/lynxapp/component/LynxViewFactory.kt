package com.lynxapp.component

import android.app.Activity
import com.lynx.tasm.LynxBooleanOption
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynx.xelement.XElementBehaviors
import com.lynxapp.GroupTemplateFetcher
import com.lynxapp.LynxBundleRepository
import com.lynxapp.LynxGenericResourceFetcher
import com.lynxapp.nativemodule.NativeBackController
import com.lynxapp.nativemodule.BackModule
import com.lynxapp.nativemodule.StatusBarModule

/** Creates every app-owned LynxView with the same native module contract. */
internal fun Activity.createLynxView(
    bundleRepository: LynxBundleRepository,
    nativeBackController: NativeBackController,
    bundleKey: String,
    groupUrl: String? = null,
): LynxView {
    val webviewBridgeAdapter = WebviewModuleBridgeHostAdapter()
    val builder = webviewBridgeAdapter.builder
    // A grouped view's template fetch is served by the group (fed by
    // GroupTemplateFetcher), so the group key includes the resolved URL to
    // keep its cached TemplateBundle coherent with dev-URL switches and OTA
    // cache applies. groupUrl overrides the resolved bundle URL for callers
    // that render an arbitrary URL (DebugActivity).
    builder.setLynxViewGroup(
        LynxViewGroupCache.groupFor(
            this,
            bundleKey,
            groupUrl ?: bundleRepository.urlForBundle(bundleKey),
            GroupTemplateFetcher(bundleRepository),
        ),
    )
    builder.addBehaviors(XElementBehaviors().create())
    builder.setTemplateProvider(bundleRepository)
    builder.setGenericResourceFetcher(LynxGenericResourceFetcher)
    builder.setEnableGenericResourceFetcher(LynxBooleanOption.TRUE)
    // Workspace libraries are registered app-wide by Lynx's generated
    // Autolink entry. The Router's host navigation installs once in the
    // Application; only view-owned modules are registered explicitly here.
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
