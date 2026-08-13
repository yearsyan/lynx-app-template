// Copyright 2025 The Lynx Authors. All rights reserved.
// Licensed under the Apache License Version 2.0 that can be found in the
// LICENSES/Apache-2.0.txt file in the root directory of this repository.
// Modified by the Lynx template project to broaden method and error handling.

import { BusinessError } from '@kit.BasicServicesKit';
import {
  HttpStreamingDelegate,
  ILynxHttpService,
  LynxHttpRequest,
  LynxHttpResponse,
} from '@lynx/lynx';
import http from '@ohos.net.http';
import BuildProfile from 'BuildProfile';

/** App-owned Lynx fetch transport backed by HarmonyOS Network Kit. */
export class LynxTemplateHttpService implements ILynxHttpService {
  static readonly instance: LynxTemplateHttpService = new LynxTemplateHttpService();

  private static readonly SDK_ERROR_STATUS_CODE: number = 499;

  private constructor() {}

  request(request: LynxHttpRequest, callback: (response: LynxHttpResponse) => void): void {
    if (!this.isAllowedURL(request.url)) {
      callback(this.errorResponse(request.url, 'Invalid URL or cleartext HTTP in release build'));
      return;
    }
    const method: http.RequestMethod | null = this.methodFromName(request.httpMethod);
    if (method === null) {
      callback(this.errorResponse(request.url, `Unsupported HTTP method: ${request.httpMethod}`));
      return;
    }

    const nativeRequest: http.HttpRequest = http.createHttp();
    nativeRequest.request(request.url, {
      method,
      header: request.httpHeaders,
      extraData: request.httpBody,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
    }, (error: BusinessError, nativeResponse: http.HttpResponse) => {
      const response: LynxHttpResponse = new LynxHttpResponse();
      response.url = request.url;

      if (!error) {
        response.statusCode = nativeResponse.responseCode;
        response.httpHeaders = nativeResponse.header as Record<string, string>;
        const body: Object = nativeResponse.result;
        if (body instanceof ArrayBuffer) {
          response.httpBody = body;
        } else {
          response.statusCode = LynxTemplateHttpService.SDK_ERROR_STATUS_CODE;
          response.statusText = 'HTTP body was not an ArrayBuffer';
        }
      } else {
        response.statusCode = LynxTemplateHttpService.SDK_ERROR_STATUS_CODE;
        response.statusText = error.message;
      }

      callback(response);
      nativeRequest.destroy();
    });
  }

  requestStreaming(
    request: LynxHttpRequest,
    callback: (response: LynxHttpResponse) => void,
    delegate: HttpStreamingDelegate,
  ): void {
    if (!this.isAllowedURL(request.url)) {
      const message: string = 'Invalid URL or cleartext HTTP in release build';
      callback(this.errorResponse(request.url, message));
      delegate.onError(message);
      delegate.onEnd();
      return;
    }
    const method: http.RequestMethod | null = this.methodFromName(request.httpMethod);
    if (method === null) {
      const message: string = `Unsupported HTTP method: ${request.httpMethod}`;
      callback(this.errorResponse(request.url, message));
      delegate.onError(message);
      delegate.onEnd();
      return;
    }

    const nativeRequest: http.HttpRequest = http.createHttp();
    let responseHeaders: Record<string, string> = {};
    let useServerSentEvents: boolean = false;
    let hasReceivedHeaders: boolean = false;

    nativeRequest.on('dataReceive', (data: ArrayBuffer) => {
      if (useServerSentEvents) {
        delegate.onDataSSE(data);
      } else if (!hasReceivedHeaders) {
        delegate.onDataPending(data);
      } else {
        delegate.onData(data);
      }
    });
    nativeRequest.once('headersReceive', (headers: Object) => {
      responseHeaders = headers as Record<string, string>;
      useServerSentEvents = this.isServerSentEvent(responseHeaders);
      hasReceivedHeaders = true;

      const response: LynxHttpResponse = new LynxHttpResponse();
      response.url = request.url;
      response.httpHeaders = responseHeaders;
      // Network Kit reports the final status code only when the stream ends.
      response.statusCode = 200;
      callback(response);
      delegate.flushPendingData(useServerSentEvents);
    });

    nativeRequest.requestInStream(request.url, {
      method,
      header: request.httpHeaders,
      extraData: request.httpBody,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
    }, (error: BusinessError, statusCode: number) => {
      if (!error) {
        if (!hasReceivedHeaders) {
          const response: LynxHttpResponse = new LynxHttpResponse();
          response.url = request.url;
          response.httpHeaders = responseHeaders;
          response.statusCode = statusCode;
          callback(response);
        }
        if (useServerSentEvents) delegate.flushSSEBuffer();
        delegate.flushPendingData(useServerSentEvents);
        delegate.onEnd();
      } else {
        if (!hasReceivedHeaders) callback(this.errorResponse(request.url, error.message));
        delegate.onError(error.message);
        delegate.onEnd();
      }

      nativeRequest.off('dataReceive');
      nativeRequest.destroy();
    });
  }

  private methodFromName(methodName: string): http.RequestMethod | null {
    switch (methodName.toUpperCase()) {
      case 'OPTIONS': return http.RequestMethod.OPTIONS;
      case 'GET': return http.RequestMethod.GET;
      case 'HEAD': return http.RequestMethod.HEAD;
      case 'POST': return http.RequestMethod.POST;
      case 'PUT': return http.RequestMethod.PUT;
      case 'DELETE': return http.RequestMethod.DELETE;
      case 'TRACE': return http.RequestMethod.TRACE;
      case 'CONNECT': return http.RequestMethod.CONNECT;
      default: return null;
    }
  }

  private errorResponse(url: string, message: string): LynxHttpResponse {
    const response: LynxHttpResponse = new LynxHttpResponse();
    response.url = url;
    response.statusCode = LynxTemplateHttpService.SDK_ERROR_STATUS_CODE;
    response.statusText = message;
    return response;
  }

  private isAllowedURL(url: string): boolean {
    return url.startsWith('https://') || (BuildProfile.DEBUG && url.startsWith('http://'));
  }

  private isServerSentEvent(headers: Record<string, string>): boolean {
    for (const key of Object.keys(headers)) {
      if (key.toLowerCase() === 'content-type') {
        return headers[key].toLowerCase().includes('text/event-stream');
      }
    }
    return false;
  }
}
