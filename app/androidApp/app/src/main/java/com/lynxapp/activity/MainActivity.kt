package com.lynxapp.activity

import android.os.Bundle
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import com.lynx.tasm.LynxView
import com.lynxapp.DebugSettingsEntry
import com.lynxapp.LynxBundleRepository
import com.lynxapp.component.NativeEnvironmentBridge
import com.lynxapp.component.createLynxView
import com.lynxapp.component.enableLynxEdgeToEdge
import com.lynxapp.nativemodule.NativeBackController

// Extends FragmentActivity (like LynxPageActivity) so the autolinked
// Biometric module can host its BiometricPrompt on the main Lynx page too.
class MainActivity : FragmentActivity() {
    private lateinit var lynxView: LynxView
    private lateinit var bundleRepository: LynxBundleRepository
    private lateinit var nativeEnvironmentBridge: NativeEnvironmentBridge
    private lateinit var nativeBackController: NativeBackController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableLynxEdgeToEdge()
        bundleRepository = LynxBundleRepository(this)
        nativeBackController = NativeBackController(this)
        lynxView = createLynxView(
            bundleRepository,
            nativeBackController,
            LynxBundleRepository.BUNDLE_NAME,
        )
        nativeBackController.attach(lynxView)
        val root = FrameLayout(this).apply {
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
        nativeBackController.destroy()
        nativeEnvironmentBridge.detach()
        lynxView.destroy()
        super.onDestroy()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!nativeBackController.handleLegacyBack()) {
            super.onBackPressed()
        }
    }

    private fun renderBundle(url: String) {
        lynxView.renderTemplateUrl(url, nativeEnvironmentBridge.initialData())
        nativeEnvironmentBridge.onTemplateLoadStarted()
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
}
