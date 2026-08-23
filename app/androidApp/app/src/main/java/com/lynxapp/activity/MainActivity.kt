package com.lynxapp.activity

import android.os.Bundle
import com.lynxapp.DebugSettingsEntry
import com.lynxapp.LynxBundleRepository
import com.lynxapp.R
import com.lynxapp.component.LoadingOverlay
import com.lynxapp.deeplink.DeepLinkRouteResolver

/**
 * Root launcher route hosting the `main` bundle: a thin LynxPageActivity
 * that states its route configuration instead of reading route extras, and
 * applies a pending OTA update behind a loading overlay once the first
 * render is under way. A `lynxapp://` VIEW intent instead feeds the standard
 * route extras from the shared deep link config before the base class reads
 * them, so a deep-linked root reuses the pushed-route init-data pipeline.
 */
class MainActivity : LynxPageActivity() {
    internal override val isRootRoute = true

    protected override val bundleName: String
        get() = intent.getStringExtra(EXTRA_BUNDLE) ?: LynxBundleRepository.BUNDLE_NAME

    override fun onCreate(savedInstanceState: Bundle?) {
        applyDeepLinkExtras()
        super.onCreate(savedInstanceState)
        DebugSettingsEntry.attach(this, root)
    }

    /** Standard launch mode stacks a fresh root instance for warm deep links. */
    private fun applyDeepLinkExtras() {
        if (intent.hasExtra(EXTRA_BUNDLE)) return
        val resolution = DeepLinkRouteResolver.resolve(applicationContext, intent.data) ?: return
        intent.putExtra(EXTRA_BUNDLE, resolution.bundle)
        intent.putExtra(EXTRA_PARAMS_JSON, resolution.paramsJson)
    }

    override fun onInitialBundleRendered() {
        bundleRepository.runWhenManifestReady { hasManifest ->
            if (!hasManifest) return@runWhenManifestReady
            val update = bundleRepository.pendingUpdateFor(bundleName)
                ?: return@runWhenManifestReady
            runOnUiThread { LoadingOverlay.show(this, getString(R.string.updating_bundle)) }
            bundleRepository.download(update) { updated ->
                runOnUiThread {
                    LoadingOverlay.hide(this)
                    // The current view's group caches its parsed TemplateBundle
                    // for the group's lifetime, so re-rendering in place would
                    // reuse the pre-update bundle. Recreate the activity: the
                    // fresh view resolves the cache URL, joins a fresh group,
                    // and loads the verified update.
                    if (updated && !isFinishing && !isDestroyed) recreate()
                }
            }
        }
    }
}
