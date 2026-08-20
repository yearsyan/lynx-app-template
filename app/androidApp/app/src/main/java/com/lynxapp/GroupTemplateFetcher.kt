package com.lynxapp

import com.lynx.tasm.provider.AbsTemplateProvider
import com.lynx.tasm.resourceprovider.LynxResourceCallback
import com.lynx.tasm.resourceprovider.LynxResourceRequest
import com.lynx.tasm.resourceprovider.LynxResourceResponse
import com.lynx.tasm.resourceprovider.template.LynxTemplateResourceFetcher
import com.lynx.tasm.resourceprovider.template.TemplateProviderResult

/**
 * Routes LynxViewGroup template fetches through the app's bundle resolution
 * (dev server URL, verified OTA cache, embedded assets).
 *
 * When a LynxView has a LynxViewGroup attached, renderTemplateUrl never
 * consults the view's own AbsTemplateProvider: LynxTemplateRender delegates
 * the fetch to the group, which requires a LynxTemplateResourceFetcher and
 * caches the parsed TemplateBundle for the group's lifetime. Without this
 * adapter every grouped view fails with error 102/10203
 * "no TemplateResourceFetcher was provided".
 */
class GroupTemplateFetcher(
    private val repository: LynxBundleRepository,
) : LynxTemplateResourceFetcher() {
    override fun fetchTemplate(
        request: LynxResourceRequest,
        callback: LynxResourceCallback<TemplateProviderResult>,
    ) {
        repository.loadTemplate(
            request.url,
            object : AbsTemplateProvider.Callback {
                override fun onSuccess(data: ByteArray) {
                    callback.onResponse(
                        LynxResourceResponse.onSuccess(
                            TemplateProviderResult.fromBinary(data),
                        ),
                    )
                }

                override fun onFailed(reason: String) {
                    @Suppress("UNCHECKED_CAST")
                    val response = LynxResourceResponse.onFailed(RuntimeException(reason))
                        as LynxResourceResponse<TemplateProviderResult>
                    callback.onResponse(response)
                }
            },
        )
    }

    override fun fetchSSRData(
        request: LynxResourceRequest,
        callback: LynxResourceCallback<ByteArray>,
    ) {
        @Suppress("UNCHECKED_CAST")
        val response = LynxResourceResponse.onFailed(
            UnsupportedOperationException("SSR data is not supported"),
        ) as LynxResourceResponse<ByteArray>
        callback.onResponse(response)
    }
}
