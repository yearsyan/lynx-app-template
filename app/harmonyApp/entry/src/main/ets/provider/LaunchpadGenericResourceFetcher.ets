import { LynxError, LynxSubErrorCode, LynxGenericResourceFetcher, LynxResourceRequest, LynxResourceType } from '@lynx/lynx';
import { AsyncCallback, BusinessError } from '@ohos.base';
import http from '@ohos.net.http';
import { ImageKnife, ImageKnifeOption, CacheStrategy } from  '@ohos/imageknife';

export class LaunchpadGenericResourceFetcher extends LynxGenericResourceFetcher {
  // In-flight downloads keyed by URL so cancel() can destroy them.
  private activeRequests: Map<string, Set<http.HttpRequest>> = new Map();

  fetchResource(request: LynxResourceRequest, callback: AsyncCallback<ArrayBuffer, void>): void {
    let httpRequest = http.createHttp();
    this.trackRequest(request.url, httpRequest);
    httpRequest.request(request.url, {
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    }, (err: BusinessError, data: http.HttpResponse) => {
      this.untrackRequest(request.url, httpRequest);
      callback(err, data?.result as ArrayBuffer)
      httpRequest.destroy();
    })
  }

  fetchResourcePath(request: LynxResourceRequest, callback: AsyncCallback<string, void>): void {
    if (request.type === LynxResourceType.LYNX_RESOURCE_TYPE_IMAGE) {
      let option = new ImageKnifeOption();
      option.loadSrc = request.url;
      option.writeCacheStrategy = CacheStrategy.File;
      let error: BusinessError | undefined = undefined;
      ImageKnife.getInstance().preLoadCache(option).then((data: string) => {
        if (data.length > 0) {
          callback(error, data);
        } else {
          error = {
            code: LynxSubErrorCode.E_RESOURCE_IMAGE_PIC_SOURCE,
            message: 'Image path is invalid',
            name: 'Image Error',
          }
          callback(error, '');
        }
      }).catch((e: string) => {
        error = {
          code: LynxSubErrorCode.E_RESOURCE_IMAGE_FROM_NETWORK_OR_OTHERS,
          message: e,
          name: 'Image Error',
        }
        callback(error, '');
      })
    } else {
      callback({
        code: LynxError.LYNX_ERROR_CODE_RESOURCE,
        message: 'unsupported type: ' + request.type,
        name: 'Resource Error',
      }, '');
    }
  }

  cancel(request: LynxResourceRequest): void {
    const pending: Set<http.HttpRequest> | undefined = this.activeRequests.get(request.url);
    if (pending === undefined) {
      return;
    }
    for (const httpRequest of pending) {
      httpRequest.destroy();
    }
    this.activeRequests.delete(request.url);
  }

  private trackRequest(url: string, httpRequest: http.HttpRequest): void {
    let pending: Set<http.HttpRequest> | undefined = this.activeRequests.get(url);
    if (pending === undefined) {
      pending = new Set<http.HttpRequest>();
      this.activeRequests.set(url, pending);
    }
    pending.add(httpRequest);
  }

  private untrackRequest(url: string, httpRequest: http.HttpRequest): void {
    const pending: Set<http.HttpRequest> | undefined = this.activeRequests.get(url);
    if (pending === undefined) {
      return;
    }
    pending.delete(httpRequest);
    if (pending.size === 0) {
      this.activeRequests.delete(url);
    }
  }
}
