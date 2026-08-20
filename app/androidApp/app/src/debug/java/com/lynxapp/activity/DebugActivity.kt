package com.lynxapp.activity

import android.os.Bundle
import androidx.fragment.app.FragmentActivity
import com.lynx.tasm.LynxView
import com.lynx.tasm.TemplateData
import com.lynxapp.LynxBundleRepository
import com.lynxapp.autolink.deviceinfo.DeviceSystemUI
import com.lynxapp.component.createLynxView

class DebugActivity : FragmentActivity() {
    private lateinit var lynxView: LynxView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        DeviceSystemUI.enableEdgeToEdge(this)
        val url = intent.getStringExtra("url")
        lynxView = createLynxView(
            LynxBundleRepository(this),
            url ?: "debug",
            url,
        )
        setContentView(lynxView)
        url?.let {
            lynxView.renderTemplateUrl(it, TemplateData.empty())
        }
    }

    override fun onDestroy() {
        lynxView.destroy()
        super.onDestroy()
    }
}
