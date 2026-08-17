package com.lynxapp

import android.app.Application
import com.facebook.drawee.backends.pipeline.Fresco
import com.facebook.imagepipeline.core.ImagePipelineConfig
import com.facebook.imagepipeline.memory.PoolConfig
import com.facebook.imagepipeline.memory.PoolFactory
import com.lynx.service.image.LynxImageService
import com.lynx.service.log.LynxLogService
import com.lynx.tasm.LynxEnv
import com.lynx.tasm.service.LynxServiceCenter
import com.lynxapp.autolink.router.RouterModule
import com.lynxapp.nativemodule.AppRouteHandler

class LynxTemplateApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        AppInstrumentation.init(this)
        // MMKV bootstrap lives in the autolinked KV library.
        // The autolinked Router module delegates in-app bundle navigation
        // to this stateless host handler; it must be installed before the
        // first Lynx view is created.
        RouterModule.setRouteHandler(AppRouteHandler())
        initLynxService()
        initLynxEnv()
        DevToolInitializer.onEnvironmentInitialized(this)
    }

    private fun initLynxService() {
        // init Fresco which is needed by LynxImageService
        val factory = PoolFactory(PoolConfig.newBuilder().build())
        val builder =
            ImagePipelineConfig.newBuilder(applicationContext).setPoolFactory(factory)
        Fresco.initialize(applicationContext, builder.build())

        LynxServiceCenter.inst().registerService(LynxImageService.getInstance())
        LynxServiceCenter.inst().registerService(LynxLogService)
        LynxServiceCenter.inst().registerService(LynxTemplateHttpService)

        DevToolInitializer.registerService()
    }

    private fun initLynxEnv() {
        LynxEnv.inst().init(
            this,
            null,
            null,
            null
        )
        LynxEnv.inst().enableLynxDebug(BuildConfig.DEBUG)
        LynxEnv.inst().enableDevtool(BuildConfig.DEBUG)
        LynxEnv.inst().enableLogBox(BuildConfig.DEBUG)
    }
}
