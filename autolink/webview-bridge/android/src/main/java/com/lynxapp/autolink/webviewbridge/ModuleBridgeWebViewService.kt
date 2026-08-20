package com.lynxapp.autolink.webviewbridge

import android.content.Context
import android.graphics.Bitmap
import android.webkit.JavascriptInterface
import android.webkit.ValueCallback
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import com.lynx.jsbridge.CommonModuleCreator
import com.lynx.jsbridge.IContextFinder
import com.lynx.jsbridge.LynxModuleFactory
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.JavaOnlyArray
import com.lynx.react.bridge.JavaOnlyMap
import com.lynx.react.bridge.ReadableArray
import com.lynx.react.bridge.ReadableMap
import com.lynx.tasm.behavior.LynxContext
import com.lynx.xelement.webview.service.ILynxWebViewCallback
import com.lynx.xelement.webview.service.ILynxWebViewService
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

/** WebView service backing the autolinked `<module-webview>` element. */
class ModuleBridgeWebViewService(
    private val lynxContext: LynxContext,
    private val entries: List<ModuleBridgeEntry>,
) : ILynxWebViewService {
    private var callback: ILynxWebViewCallback? = null
    private var webView: WebView? = null
    private val moduleFactory = LynxModuleFactory().apply {
        bind(CommonModuleCreator(BridgeContextFinder(lynxContext)))
        entries.forEach { entry -> registerModule(entry.name, entry.moduleClass, entry.param) }
    }

    @Volatile
    private var allowedModules: Set<String> = emptySet()

    override fun setCallback(callback: ILynxWebViewCallback?) {
        this.callback = callback
    }

    override fun setParams(params: HashMap<String, Any>?) {
        val bridge = params?.get(BRIDGE_PARAM) as? Map<*, *>
        allowedModules = (bridge?.get(MODULES_PARAM) as? List<*>)
            ?.mapNotNull { it as? String }
            ?.filter(String::isNotEmpty)
            ?.toSet()
            ?: emptySet()
    }

    override fun initWebView() {
        webView = WebView(lynxContext).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            webViewClient = bridgeClient
            addJavascriptInterface(JsGateway(), JS_GATEWAY_NAME)
        }
    }

    override fun getWebView(): WebView? = webView

    override fun loadUrl(url: String?) {
        webView?.loadUrl(url.orEmpty())
    }

    override fun loadHtmlString(html: String?) {
        webView?.loadDataWithBaseURL(null, html.orEmpty(), "text/html", "utf-8", null)
    }

    override fun reload() {
        webView?.reload()
    }

    override fun evaluateJavascript(script: String?, resultCallback: ValueCallback<String>?) {
        webView?.evaluateJavascript(script.orEmpty(), resultCallback)
    }

    override fun destroy() {
        moduleFactory.destroy()
        webView?.removeJavascriptInterface(JS_GATEWAY_NAME)
        webView?.destroy()
        webView = null
    }

    private val bridgeClient = object : WebViewClient() {
        override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
            injectBridgeScript()
        }

        override fun onPageFinished(view: WebView, url: String?) {
            injectBridgeScript()
            callback?.onPageFinished(view, url)
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) {
            if (!request.isForMainFrame) {
                return
            }
            callback?.onReceivedError(
                view,
                request,
                error.errorCode,
                error.description?.toString().orEmpty(),
            )
        }
    }

    /** Entry point for page JS; Android invokes these methods off the UI thread. */
    private inner class JsGateway {
        @JavascriptInterface
        fun postMessage(message: String) {
            callback?.onMessageReceived(message)
        }

        @JavascriptInterface
        fun invokeNative(request: String) {
            handleInvoke(request)
        }
    }

    private fun injectBridgeScript() {
        val view = webView ?: return
        view.post { view.evaluateJavascript(BRIDGE_SCRIPT, null) }
    }

    private fun handleInvoke(request: String) {
        val json = try {
            JSONObject(request)
        } catch (_: Throwable) {
            return
        }
        val id = json.optLong(KEY_ID, -1)
        val session = json.optString(KEY_SESSION)
        val moduleName = json.optString(KEY_MODULE)
        val methodName = json.optString(KEY_METHOD)
        val args = json.optJSONArray(KEY_ARGS) ?: JSONArray()
        if (id < 0 || session.isEmpty() || moduleName.isEmpty() || methodName.isEmpty()) {
            return
        }

        if (moduleName !in allowedModules) {
            respond(session, id, ok = false, "module '$moduleName' is not exposed to this webview")
            return
        }

        lynxContext.runOnTasmThread {
            try {
                invokeModule(session, id, moduleName, methodName, args)
            } catch (error: Throwable) {
                respond(session, id, ok = false, errorMessage(error, "invoke failed"))
            }
        }
    }

    private fun invokeModule(
        session: String,
        id: Long,
        moduleName: String,
        methodName: String,
        args: JSONArray,
    ) {
        // CommonModuleCreator resolves the per-view entries registered below
        // first and falls back to LynxEnv's app-wide registry, which is where
        // autolinked libraries register; constructor selection, wrapper setup
        // and module lifecycle therefore match normal Lynx native-module calls.
        val wrapper = moduleFactory.getModule(moduleName)
            ?: throw IllegalStateException("unknown module '$moduleName'")
        val descriptor = wrapper.methodDescriptors.firstOrNull { it.name == methodName }
            ?: throw NoSuchMethodException("module '$moduleName' has no @LynxMethod '$methodName'")
        val method = descriptor.method
        val types = method.parameterTypes
        val callbackIndexes = types.indices.filter { types[it] == Callback::class.java }
        if (callbackIndexes.size > 1 ||
            (callbackIndexes.size == 1 && callbackIndexes.single() != types.lastIndex)
        ) {
            throw IllegalArgumentException("only one trailing Callback parameter is supported")
        }
        val hasCallback = callbackIndexes.isNotEmpty()
        val valueCount = if (hasCallback) types.size - 1 else types.size
        if (valueCount != args.length()) {
            throw IllegalArgumentException(
                "expected $valueCount arguments for '$moduleName.$methodName', got ${args.length()}",
            )
        }

        val responded = AtomicBoolean(false)
        val argv = arrayOfNulls<Any>(types.size)
        for (index in 0 until valueCount) {
            argv[index] = convertArgument(args.opt(index), types[index])
        }
        if (hasCallback) {
            argv[types.lastIndex] = Callback { values ->
                if (responded.compareAndSet(false, true)) {
                    respond(session, id, ok = true, values.toList())
                }
            }
        }
        method.isAccessible = true
        method.invoke(wrapper.module, *argv)
        if (!hasCallback && responded.compareAndSet(false, true)) {
            respond(session, id, ok = true, emptyList<Any>())
        }
    }

    private fun convertArgument(raw: Any?, type: Class<*>): Any? {
        val value = normalizeJsonValue(raw)
        return when (type) {
            String::class.java -> value as? String
            java.lang.Boolean.TYPE, java.lang.Boolean::class.java ->
                value as? Boolean ?: throw IllegalArgumentException("expected boolean, got $value")
            java.lang.Integer.TYPE, java.lang.Integer::class.java ->
                (value as? Number)?.toInt() ?: throw IllegalArgumentException("expected int, got $value")
            java.lang.Long.TYPE, java.lang.Long::class.java ->
                (value as? Number)?.toLong() ?: throw IllegalArgumentException("expected long, got $value")
            java.lang.Double.TYPE, java.lang.Double::class.java ->
                (value as? Number)?.toDouble() ?: throw IllegalArgumentException("expected double, got $value")
            java.lang.Float.TYPE, java.lang.Float::class.java ->
                (value as? Number)?.toFloat() ?: throw IllegalArgumentException("expected float, got $value")
            ReadableMap::class.java ->
                if (raw is JSONObject) JavaOnlyMap.from(jsonObjectToMap(raw)) else null
            ReadableArray::class.java ->
                if (raw is JSONArray) JavaOnlyArray.from(jsonArrayToList(raw)) else null
            else -> throw IllegalArgumentException("unsupported parameter type ${type.name}")
        }
    }

    private fun respond(session: String, id: Long, ok: Boolean, payload: Any?) {
        val envelope = JSONObject()
            .put(KEY_SESSION, session)
            .put(KEY_ID, id)
            .put(KEY_OK, ok)
            .put(if (ok) KEY_RESULT else KEY_ERROR, toJsonValue(payload))
        postToWeb("window.$JS_API&&window.$JS_API.$ON_RESPONSE($envelope)")
    }

    private fun postToWeb(script: String) {
        val view = webView ?: return
        view.post { view.evaluateJavascript(script, null) }
    }

    private fun errorMessage(error: Throwable, fallback: String): String {
        val message = (error.cause ?: error).message
        return if (message.isNullOrEmpty()) fallback else message
    }

    private companion object {
        const val BRIDGE_PARAM = "module-bridge"
        const val MODULES_PARAM = "modules"
        const val JS_GATEWAY_NAME = "LynxWebViewBridge"
        const val JS_API = "__lynxNativeBridge"
        const val ON_RESPONSE = "_onResponse"
        const val KEY_SESSION = "session"
        const val KEY_ID = "id"
        const val KEY_MODULE = "module"
        const val KEY_METHOD = "method"
        const val KEY_ARGS = "args"
        const val KEY_OK = "ok"
        const val KEY_RESULT = "result"
        const val KEY_ERROR = "error"

        fun jsonObjectToMap(json: JSONObject): HashMap<String, Any?> =
            HashMap<String, Any?>().apply {
                json.keys().forEach { key -> put(key, normalizeJsonValue(json.opt(key))) }
            }

        fun jsonArrayToList(json: JSONArray): ArrayList<Any?> =
            ArrayList<Any?>(json.length()).apply {
                for (index in 0 until json.length()) {
                    add(normalizeJsonValue(json.opt(index)))
                }
            }

        fun normalizeJsonValue(value: Any?): Any? = when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> jsonObjectToMap(value)
            is JSONArray -> jsonArrayToList(value)
            else -> value
        }

        fun toJsonValue(value: Any?): Any = when (value) {
            null -> JSONObject.NULL
            is ReadableMap -> toJsonValue(value.toHashMap())
            is ReadableArray -> toJsonValue(value.toArrayList())
            is Map<*, *> -> JSONObject().apply {
                value.forEach { (key, item) -> put(key.toString(), toJsonValue(item)) }
            }
            is List<*> -> JSONArray().apply { value.forEach { put(toJsonValue(it)) } }
            is String, is Boolean, is Int, is Long, is Double -> value
            is Number -> value.toDouble()
            else -> value.toString()
        }

        val BRIDGE_SCRIPT = """
            (function () {
              if (window.__lynxNativeBridge) { return; }
              var session = 'wv-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2);
              var nextId = 1;
              var pending = Object.create(null);
              function settle(envelope) {
                if (!envelope || envelope.session !== session) { return; }
                var entry = pending[envelope.id];
                if (!entry) { return; }
                delete pending[envelope.id];
                if (envelope.ok) {
                  entry.resolve(envelope.result || []);
                } else {
                  entry.reject(new Error(envelope.error || 'invoke failed'));
                }
              }
              window.__lynxNativeBridge = {
                invoke: function (moduleName, methodName, args) {
                  var id = nextId++;
                  return new Promise(function (resolve, reject) {
                    pending[id] = { resolve: resolve, reject: reject };
                    LynxWebViewBridge.invokeNative(JSON.stringify({
                      session: session,
                      id: id,
                      module: moduleName,
                      method: methodName,
                      args: args || []
                    }));
                  });
                },
                _onResponse: settle
              };
              window.dispatchEvent(new Event('lynx-native-bridge-ready'));
            })();
        """.trimIndent()
    }

    /** Context hand-off required by Lynx's CommonModuleCreator and wrappers. */
    private class BridgeContextFinder(context: LynxContext) : IContextFinder {
        private val context = WeakReference<Context>(context)

        override fun findContext(id: String): WeakReference<Context> = context

        override fun registerContext(id: String, context: WeakReference<Context>) = Unit
    }
}
