package com.lynxapp.nativemodule

import android.app.Activity
import android.content.Context
import android.util.Base64
import com.lynx.jsbridge.LynxMethod
import com.lynx.jsbridge.LynxModule
import com.lynx.react.bridge.Callback
import com.lynx.react.bridge.JavaOnlyArray
import com.lynx.react.bridge.JavaOnlyMap
import com.lynx.react.bridge.ReadableMap
import com.lynx.tasm.LynxView
import com.lynxapp.AppHttpClient
import com.lynxapp.BuildConfig
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import okio.ByteString.Companion.toByteString

/** Activity-owned, production WebSocket transport independent of Lynx DevTool. */
class NativeWebSocketController(private val activity: Activity) {
    private class Connection {
        val terminal = AtomicBoolean(false)

        @Volatile
        var socket: WebSocket? = null
    }

    private val connections = ConcurrentHashMap<String, Connection>()

    @Volatile
    private var lynxView: LynxView? = null

    @Volatile
    private var destroyed = false

    fun attach(lynxView: LynxView) {
        this.lynxView = lynxView
    }

    fun connect(
        id: String,
        url: String,
        protocols: List<String>,
        headers: Map<String, String>,
    ): String {
        if (destroyed) return "WebSocket host has been destroyed"
        if (!CONNECTION_ID.matches(id)) return "Invalid WebSocket connection ID"
        if (!isAllowedUrl(url)) return "WebSocket URL must use wss:// (ws:// is Debug-only)"
        if (connections.containsKey(id)) return "WebSocket connection ID already exists"

        val request = runCatching {
            Request.Builder()
                .url(url)
                .apply {
                    headers.forEach { (name, value) -> addHeader(name, value) }
                    if (protocols.isNotEmpty()) {
                        header("Sec-WebSocket-Protocol", protocols.joinToString(", "))
                    }
                }
                .build()
        }.getOrElse { error ->
            return error.message ?: "Invalid WebSocket request"
        }

        val connection = Connection()
        connections[id] = connection
        connection.socket = runCatching {
            AppHttpClient.instance.newWebSocket(
                request,
                object : WebSocketListener() {
                    override fun onOpen(webSocket: WebSocket, response: Response) {
                        emit(
                            id,
                            JavaOnlyMap().apply {
                                putString("type", "open")
                                putString(
                                    "protocol",
                                    response.header("Sec-WebSocket-Protocol").orEmpty(),
                                )
                            },
                        )
                    }

                    override fun onMessage(webSocket: WebSocket, text: String) {
                        emit(
                            id,
                            JavaOnlyMap().apply {
                                putString("type", "message")
                                putString("dataType", "text")
                                putString("data", text)
                            },
                        )
                    }

                    override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                        emit(
                            id,
                            JavaOnlyMap().apply {
                                putString("type", "message")
                                putString("dataType", "base64")
                                putString("data", bytes.base64())
                            },
                        )
                    }

                    override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                        finish(id, connection, code, reason, true)
                    }

                    override fun onFailure(
                        webSocket: WebSocket,
                        t: Throwable,
                        response: Response?,
                    ) {
                        if (!connection.terminal.compareAndSet(false, true)) return
                        connections.remove(id, connection)
                        val message = t.message ?: "WebSocket transport failed"
                        emit(
                            id,
                            JavaOnlyMap().apply {
                                putString("type", "error")
                                putString("message", message)
                            },
                        )
                        emitClose(id, 1006, message, false)
                    }
                },
            )
        }.getOrElse { error ->
            connections.remove(id, connection)
            return error.message ?: "Unable to create WebSocket"
        }
        return ""
    }

    fun sendText(id: String, data: String): String = send(id) { socket ->
        socket.send(data)
    }

    fun sendBase64(id: String, data: String): String {
        val bytes = runCatching { Base64.decode(data, Base64.DEFAULT) }
            .getOrElse { return "Invalid Base64 WebSocket payload" }
        return send(id) { socket -> socket.send(bytes.toByteString()) }
    }

    fun close(id: String, code: Int, reason: String): String {
        val connection = connections[id] ?: return "Unknown WebSocket connection ID"
        return runCatching {
            if (!checkNotNull(connection.socket).close(code, reason)) {
                "WebSocket close request was rejected"
            } else {
                ""
            }
        }.getOrElse { error -> error.message ?: "Unable to close WebSocket" }
    }

    fun destroy() {
        if (destroyed) return
        destroyed = true
        lynxView = null
        connections.values.forEach { connection ->
            connection.terminal.set(true)
            connection.socket?.cancel()
        }
        connections.clear()
    }

    private fun send(id: String, operation: (WebSocket) -> Boolean): String {
        val connection = connections[id] ?: return "Unknown WebSocket connection ID"
        val socket = connection.socket ?: return "WebSocket is not ready"
        return runCatching {
            if (operation(socket)) "" else "WebSocket send queue rejected the message"
        }.getOrElse { error -> error.message ?: "Unable to send WebSocket message" }
    }

    private fun finish(
        id: String,
        connection: Connection,
        code: Int,
        reason: String,
        wasClean: Boolean,
    ) {
        if (!connection.terminal.compareAndSet(false, true)) return
        connections.remove(id, connection)
        emitClose(id, code, reason, wasClean)
    }

    private fun emitClose(id: String, code: Int, reason: String, wasClean: Boolean) {
        emit(
            id,
            JavaOnlyMap().apply {
                putString("type", "close")
                putInt("code", code)
                putString("reason", reason)
                putBoolean("wasClean", wasClean)
            },
        )
    }

    private fun emit(id: String, payload: JavaOnlyMap) {
        if (destroyed) return
        payload.putString("id", id)
        activity.runOnUiThread {
            if (!destroyed) {
                lynxView?.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload))
            }
        }
    }

    private fun isAllowedUrl(url: String): Boolean =
        url.startsWith("wss://", ignoreCase = true) ||
            (BuildConfig.DEBUG && url.startsWith("ws://", ignoreCase = true))

    companion object {
        const val EVENT_NAME = "nativeWebSocket"
        private val CONNECTION_ID = Regex("^[A-Za-z0-9._-]{1,128}$")
    }
}

/** Lynx NativeModule facade for the app-owned Android WebSocket controller. */
class NativeWebSocketModule(context: Context, param: Any?) : LynxModule(context, param) {
    private val controller = param as? NativeWebSocketController

    @LynxMethod
    fun connect(options: ReadableMap, callback: Callback) {
        val host = controller
        if (host == null) {
            callback.invoke("Native WebSocket has no Activity host")
            return
        }
        val protocols = options.getArray("protocols")
            ?.asArrayList()
            ?.filterIsInstance<String>()
            .orEmpty()
        val headers = options.getMap("headers")
            ?.asHashMap()
            .orEmpty()
            .mapValues { (_, value) -> value as? String ?: value.toString() }
        callback.invoke(
            host.connect(
                id = options.getString("id", ""),
                url = options.getString("url", ""),
                protocols = protocols,
                headers = headers,
            ),
        )
    }

    @LynxMethod
    fun sendText(id: String, data: String, callback: Callback) {
        callback.invoke(controller?.sendText(id, data) ?: "Native WebSocket has no Activity host")
    }

    @LynxMethod
    fun sendBase64(id: String, data: String, callback: Callback) {
        callback.invoke(controller?.sendBase64(id, data) ?: "Native WebSocket has no Activity host")
    }

    @LynxMethod
    fun close(id: String, code: Int, reason: String, callback: Callback) {
        callback.invoke(controller?.close(id, code, reason) ?: "Native WebSocket has no Activity host")
    }

    companion object {
        const val NAME = "NativeWebSocketModule"
    }
}
