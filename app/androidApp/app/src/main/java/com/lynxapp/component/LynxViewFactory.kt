package com.lynxapp.component

import android.app.Activity
import com.lynx.tasm.LynxBooleanOption
import com.lynx.tasm.LynxError
import com.lynx.tasm.LynxView
import com.lynx.tasm.LynxViewBuilder
import com.lynx.tasm.LynxViewClient
import com.lynx.xelement.XElementBehaviors
import com.lynxapp.GroupTemplateFetcher
import com.lynxapp.LynxBundleRepository
import com.lynxapp.LynxGenericResourceFetcher

// LynxSubErrorCode E_APP_BUNDLE_LOAD_BAD_RESPONSE / _PARSE_FAILED /
// _BAD_BUNDLE: the bundle bytes could not be fetched or parsed (dev server
// offline, broken OTA cache). JS runtime errors are deliberately excluded so
// development mistakes stay visible.
private val BUNDLE_LOAD_FAILURE_SUBCODES = setOf(10203, 10204, 10205)

/** Creates every app-owned LynxView with the same native module contract. */
internal fun Activity.createLynxView(
    bundleRepository: LynxBundleRepository,
    bundleKey: String,
    groupUrl: String? = null,
    onBundleLoadFailure: (() -> Unit)? = null,
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
    // Workspace libraries, including Back, are registered app-wide by Lynx's
    // generated Autolink entry. Router host navigation installs once in the
    // Application; view-scoped modules discover this Activity from context.
    return builder.build(this).also { lynxView ->
        webviewBridgeAdapter.attach(lynxView)
        if (onBundleLoadFailure != null) {
            lynxView.addLynxViewClient(object : LynxViewClient() {
                override fun onReceivedError(error: LynxError) {
                    if (error.isFatal && error.subCode in BUNDLE_LOAD_FAILURE_SUBCODES) {
                        runOnUiThread { onBundleLoadFailure() }
                    }
                }
            })
        }
    }
}
