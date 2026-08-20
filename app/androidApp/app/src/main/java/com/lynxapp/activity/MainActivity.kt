package com.lynxapp.activity

import android.os.Bundle
import android.util.Log
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import com.lynx.tasm.LynxView
import com.lynxapp.autolink.deviceinfo.DeviceSystemUI
import com.lynxapp.autolink.deviceinfo.NativeEnvironmentBridge
import com.lynxapp.DebugSettingsEntry
import com.lynxapp.LynxBundleRepository
import com.lynxapp.component.createLynxView

// Extends FragmentActivity (like LynxPageActivity) so the autolinked Back and
// Biometric modules can use AndroidX lifecycle-aware host APIs.
class MainActivity : FragmentActivity() {
    private lateinit var lynxView: LynxView
    private lateinit var bundleRepository: LynxBundleRepository
    private lateinit var nativeEnvironmentBridge: NativeEnvironmentBridge
    private lateinit var root: FrameLayout
    private var fellBackToEmbedded = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceSystemUI.enableEdgeToEdge(this)
        bundleRepository = LynxBundleRepository(this)
        lynxView = createLynxView(
            bundleRepository,
            LynxBundleRepository.BUNDLE_NAME,
            onBundleLoadFailure = ::fallBackToEmbeddedBundle,
        )
        root = FrameLayout(this).apply {
            addView(
                lynxView,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
        }
        setContentView(root)
        DebugSettingsEntry.attach(this, root)
        nativeEnvironmentBridge = NativeEnvironmentBridge(lynxView)
        nativeEnvironmentBridge.attach(::loadInitialBundle)
    }

    override fun onDestroy() {
        nativeEnvironmentBridge.detach()
        lynxView.destroy()
        super.onDestroy()
    }

    private fun renderBundle(url: String) {
        lynxView.renderTemplateUrl(url, nativeEnvironmentBridge.initialData())
        nativeEnvironmentBridge.onTemplateLoadStarted()
    }

    // A dev server or OTA cache that cannot serve the bundle must not leave a
    // white screen; render the embedded bundle instead. Runs at most once:
    // if the embedded bundle itself fails, the error stays visible. The view
    // is rebuilt because its LynxViewGroup is bound to the failed URL —
    // re-rendering in place would refetch that URL instead of the fallback.
    private fun fallBackToEmbeddedBundle() {
        if (fellBackToEmbedded) return
        fellBackToEmbedded = true
        Log.w(TAG, "Startup bundle failed to load; falling back to the embedded bundle")

        val embedded = bundleRepository.embeddedUrlForBundle(LynxBundleRepository.BUNDLE_NAME)
        nativeEnvironmentBridge.detach()
        root.removeView(lynxView)
        lynxView.destroy()

        lynxView = createLynxView(
            bundleRepository,
            LynxBundleRepository.BUNDLE_NAME,
            groupUrl = embedded,
        )
        root.addView(
            lynxView,
            0,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        nativeEnvironmentBridge = NativeEnvironmentBridge(lynxView)
        nativeEnvironmentBridge.attach { renderBundle(embedded) }
    }

    private fun loadInitialBundle() {
        renderBundle(bundleRepository.startupUrl())
        bundleRepository.checkForUpdate { updated ->
            if (updated) {
                runOnUiThread {
                    // The current view's group caches its parsed TemplateBundle
                    // for the group's lifetime, so re-rendering in place would
                    // reuse the pre-update bundle. Recreate the activity: the
                    // fresh view resolves the cache URL, joins a fresh group,
                    // and loads the verified update.
                    recreate()
                }
            }
        }
    }

    private companion object {
        const val TAG = "MainActivity"
    }
}
