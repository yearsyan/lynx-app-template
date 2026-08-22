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
import com.lynxapp.autolink.navigation.NavigationModule
import com.lynxapp.nativemodule.AppRouteHandler

class LynxTemplateApplication : Application() {
    // Lazily: property initializers run in the constructor, before the
    // Application is attached as a Context. First access happens in onCreate.
    val bundleRepository: LynxBundleRepository by lazy { LynxBundleRepository(this) }

    override fun onCreate() {
        super.onCreate()
        AppInstrumentation.init(this)
        // MMKV bootstrap lives in the autolinked Storage library.
        // The autolinked Navigation module delegates in-app bundle navigation
        // to this host handler; it must be installed before the first Lynx
        // view is created. It also watches Activity destructions to deliver
        // pending openForResult results.
        NavigationModule.setRouteHandler(AppRouteHandler(this))
        initLynxService()
        initLynxEnv()
        DevToolInitializer.onEnvironmentInitialized(this)
        // Prefetch the OTA version list so the root startup flow and route
        // opens can consult it from memory; never blocks process start.
        bundleRepository.refreshManifest { }
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
