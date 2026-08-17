package com.lynxapp.activity

import android.app.Activity
import android.os.Bundle
import com.lynx.tasm.LynxView
import com.lynx.tasm.TemplateData
import com.lynxapp.LynxBundleRepository
import com.lynxapp.component.createLynxView
import com.lynxapp.component.enableLynxEdgeToEdge
import com.lynxapp.nativemodule.NativeBackController

class DebugActivity : Activity() {
    private lateinit var lynxView: LynxView
    private lateinit var nativeBackController: NativeBackController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableLynxEdgeToEdge()
        nativeBackController = NativeBackController(this)
        lynxView = createLynxView(
            LynxBundleRepository(this),
            nativeBackController,
        )
        nativeBackController.attach(lynxView)
        setContentView(lynxView)
        intent.getStringExtra("url")?.let { url ->
            lynxView.renderTemplateUrl(url, TemplateData.empty())
        }
    }

    override fun onDestroy() {
        nativeBackController.destroy()
        lynxView.destroy()
        super.onDestroy()
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onBackPressed() {
        if (!nativeBackController.handleLegacyBack()) {
            super.onBackPressed()
        }
    }
}
