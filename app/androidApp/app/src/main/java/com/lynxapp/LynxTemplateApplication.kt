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

class LynxTemplateApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // MMKV bootstrap lives in the autolinked NativeKVModule library.
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
