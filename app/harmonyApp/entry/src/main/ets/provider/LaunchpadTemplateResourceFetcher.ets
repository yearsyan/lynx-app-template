import { LynxResourceRequest, LynxTemplateResourceFetcher, TemplateProviderResult } from '@lynx/lynx';
import { common } from '@kit.AbilityKit';
import { AsyncCallback, BusinessError } from '@ohos.base';
import http from '@ohos.net.http';
import resourceManager from '@ohos.resourceManager';

import { LynxBundleRepository } from './LynxBundleRepository';

export class LaunchpadTemplateResourceFetcher extends LynxTemplateResourceFetcher {
  private readonly bundleRepository: LynxBundleRepository = new LynxBundleRepository();
  private static readonly CACHE_SCHEME_LENGTH: number = 'lynx-cache://'.length;

  fetchTemplate(request: LynxResourceRequest,
    callback: AsyncCallback<TemplateProviderResult, void>) {
    if (this.bundleRepository.isCachedURL(request.url)) {
      try {
        const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
        // The version query only versions the URL; the cache file is keyed by
        // the plain bundle name.
        let bundleName: string =
          request.url.substring(LaunchpadTemplateResourceFetcher.CACHE_SCHEME_LENGTH);
        const queryIndex: number = bundleName.indexOf('?');
        if (queryIndex >= 0) {
          bundleName = bundleName.substring(0, queryIndex);
        }
        const error: BusinessError | undefined = undefined;
        callback(error, {
          binary: this.bundleRepository.readCachedBundle(context, bundleName),
        });
      } catch (error) {
        callback(error as BusinessError, { binary: new ArrayBuffer(0) });
      }
    } else if (request.url.startsWith('http')) {
      let httpRequest = http.createHttp();
      httpRequest.request(
        request.url, {
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
      }, (err: BusinessError, data: http.HttpResponse) => {
        callback(err, {
          binary: data?.result as ArrayBuffer
        });
        httpRequest.destroy();
      });
    } else {
      // local file
      const context: Context = getContext(this);
      const resourceMgr: resourceManager.ResourceManager = context.resourceManager;
      resourceMgr.getRawFileContent(request.url, (err: BusinessError, data: Uint8Array) => {
        callback(err, {
          binary: data?.buffer as ArrayBuffer
        })
      });
    }
  }

  fetchSSRData(request: LynxResourceRequest, callback: AsyncCallback<ArrayBuffer, void>) {
    let httpRequest = http.createHttp();
    httpRequest.request(request.url, {
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }, (err: BusinessError, data: http.HttpResponse) => {
      callback(err, data?.result as ArrayBuffer)
      httpRequest.destroy();
    })
  }
}
