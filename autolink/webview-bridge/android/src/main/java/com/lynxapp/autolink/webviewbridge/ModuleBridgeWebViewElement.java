package com.lynxapp.autolink.webviewbridge;

import android.content.Context;

import com.lynx.tasm.behavior.LynxContext;
import com.lynx.tasm.behavior.LynxElement;
import com.lynx.xelement.webview.LynxUIWebView;
import com.lynx.xelement.webview.LynxWebViewContainer;
import com.lynx.xelement.webview.service.ILynxWebViewService;
import com.lynx.xelement.webview.service.ILynxWebViewServiceProvider;

/** Autolinked native element; app-specific module wiring stays in the host adapter. */
@LynxElement(name = ModuleBridgeWebViewElement.NAME)
public final class ModuleBridgeWebViewElement extends LynxUIWebView<LynxWebViewContainer> {
    public static final String NAME = "module-webview";

    public ModuleBridgeWebViewElement(LynxContext context) {
        super(context);
        installProvider(context);
    }

    public ModuleBridgeWebViewElement(LynxContext context, Object params) {
        super(context, params);
        installProvider(context);
    }

    private void installProvider(LynxContext context) {
        setProvider(new ModuleBridgeProvider(context));
    }

    private static final class ModuleBridgeProvider implements ILynxWebViewServiceProvider {
        private final LynxContext lynxContext;

        private ModuleBridgeProvider(LynxContext lynxContext) {
            this.lynxContext = lynxContext;
        }

        @Override
        public void registerService(String type, ILynxWebViewService service) {}

        @Override
        public void unRegisterService(String type) {}

        @Override
        public ILynxWebViewService getLynxWebViewService(String type, Context context) {
            return new ModuleBridgeWebViewService(
                    lynxContext,
                    ModuleBridgeHostRegistry.entriesFor(lynxContext));
        }
    }
}
