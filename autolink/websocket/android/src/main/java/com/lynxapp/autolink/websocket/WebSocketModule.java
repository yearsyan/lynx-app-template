package com.lynxapp.autolink.websocket;

import android.content.pm.ApplicationInfo;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableArray;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;
import okio.ByteString;

/**
 * Autolinked Lynx module exposing a production WebSocket transport that is
 * independent of Lynx DevTool. Events flow back to JS through the module's
 * {@link LynxContext} instead of a host-owned controller.
 */
@LynxNativeModule(name = WebSocketModule.NAME)
public final class WebSocketModule extends LynxContextModule {
    public static final String NAME = "WebSocket";
    public static final String EVENT_NAME = "webSocket";

    private static final Pattern CONNECTION_ID = Pattern.compile("^[A-Za-z0-9._-]{1,128}$");

    private static final class Connection {
        final AtomicBoolean terminal = new AtomicBoolean(false);

        volatile WebSocket socket;
    }

    private final Map<String, Connection> connections = new ConcurrentHashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private volatile boolean destroyed = false;
    private volatile OkHttpClient client;

    public WebSocketModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void connect(ReadableMap options, Callback callback) {
        String id = orEmpty(options.getString("id"));
        String url = orEmpty(options.getString("url"));
        String error = connect(id, url, protocolsOf(options), headersOf(options));
        callback.invoke(error);
    }

    @LynxMethod
    public void sendText(String id, String data, Callback callback) {
        callback.invoke(send(id, socket -> socket.send(data)));
    }

    @LynxMethod
    public void sendBase64(String id, String data, Callback callback) {
        final byte[] bytes;
        try {
            bytes = Base64.decode(data, Base64.DEFAULT);
        } catch (IllegalArgumentException error) {
            callback.invoke("Invalid Base64 WebSocket payload");
            return;
        }
        callback.invoke(send(id, socket -> socket.send(ByteString.of(bytes, 0, bytes.length))));
    }

    @LynxMethod
    public void close(String id, int code, String reason, Callback callback) {
        Connection connection = connections.get(id);
        if (connection == null) {
            callback.invoke("Unknown WebSocket connection ID");
            return;
        }
        WebSocket socket = connection.socket;
        if (socket == null) {
            callback.invoke("WebSocket is not ready");
            return;
        }
        try {
            callback.invoke(socket.close(code, reason) ? "" : "WebSocket close request was rejected");
        } catch (Throwable error) {
            callback.invoke(messageOf(error, "Unable to close WebSocket"));
        }
    }

    @Override
    public void destroy() {
        destroyed = true;
        for (Connection connection : connections.values()) {
            connection.terminal.set(true);
            WebSocket socket = connection.socket;
            if (socket != null) {
                socket.cancel();
            }
        }
        connections.clear();
    }

    private String connect(String id, String url, List<String> protocols, Map<String, String> headers) {
        if (destroyed) {
            return "WebSocket host has been destroyed";
        }
        if (!CONNECTION_ID.matcher(id).matches()) {
            return "Invalid WebSocket connection ID";
        }
        if (!isAllowedUrl(url)) {
            return "WebSocket URL must use wss:// (ws:// is Debug-only)";
        }
        if (connections.containsKey(id)) {
            return "WebSocket connection ID already exists";
        }

        final Request request;
        try {
            Request.Builder builder = new Request.Builder().url(url);
            for (Map.Entry<String, String> header : headers.entrySet()) {
                builder.addHeader(header.getKey(), header.getValue());
            }
            if (!protocols.isEmpty()) {
                builder.header("Sec-WebSocket-Protocol", joinComma(protocols));
            }
            request = builder.build();
        } catch (Throwable error) {
            return messageOf(error, "Invalid WebSocket request");
        }

        final Connection connection = new Connection();
        connections.put(id, connection);
        try {
            connection.socket = client().newWebSocket(request, new Listener(id, connection));
        } catch (Throwable error) {
            connections.remove(id, connection);
            return messageOf(error, "Unable to create WebSocket");
        }
        return "";
    }

    private String send(String id, SendOperation operation) {
        Connection connection = connections.get(id);
        if (connection == null) {
            return "Unknown WebSocket connection ID";
        }
        WebSocket socket = connection.socket;
        if (socket == null) {
            return "WebSocket is not ready";
        }
        try {
            return operation.send(socket) ? "" : "WebSocket send queue rejected the message";
        } catch (Throwable error) {
            return messageOf(error, "Unable to send WebSocket message");
        }
    }

    private OkHttpClient client() {
        OkHttpClient result = client;
        if (result == null) {
            synchronized (this) {
                result = client;
                if (result == null) {
                    result = new OkHttpClient.Builder().build();
                    client = result;
                }
            }
        }
        return result;
    }

    private boolean isAllowedUrl(String url) {
        if (url.regionMatches(true, 0, "wss://", 0, "wss://".length())) {
            return true;
        }
        if (!url.regionMatches(true, 0, "ws://", 0, "ws://".length())) {
            return false;
        }
        ApplicationInfo info = mLynxContext != null
                ? mLynxContext.getApplicationInfo()
                : null;
        return info != null && (info.flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    private void finish(String id, Connection connection, int code, String reason, boolean wasClean) {
        if (!connection.terminal.compareAndSet(false, true)) {
            return;
        }
        connections.remove(id, connection);
        emitClose(id, code, reason, wasClean);
    }

    private void emitFailure(String id, String message) {
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putString("type", "error");
        payload.putString("message", message);
        emit(id, payload);
        emitClose(id, 1006, message, false);
    }

    private void emitClose(String id, int code, String reason, boolean wasClean) {
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putString("type", "close");
        payload.putInt("code", code);
        payload.putString("reason", reason);
        payload.putBoolean("wasClean", wasClean);
        emit(id, payload);
    }

    private void emit(String id, JavaOnlyMap payload) {
        if (destroyed) {
            return;
        }
        payload.putString("id", id);
        mainHandler.post(() -> {
            if (destroyed) {
                return;
            }
            LynxContext context = mLynxContext;
            if (context != null) {
                context.sendGlobalEvent(EVENT_NAME, JavaOnlyArray.of(payload));
            }
        });
    }

    private static List<String> protocolsOf(ReadableMap options) {
        List<String> protocols = new ArrayList<>();
        ReadableArray array = options.getArray("protocols");
        if (array == null) {
            return protocols;
        }
        for (int index = 0; index < array.size(); index++) {
            String protocol = array.getString(index);
            if (protocol != null) {
                protocols.add(protocol);
            }
        }
        return protocols;
    }

    private static Map<String, String> headersOf(ReadableMap options) {
        Map<String, String> headers = new HashMap<>();
        ReadableMap map = options.getMap("headers");
        if (map == null) {
            return headers;
        }
        for (Map.Entry<String, Object> entry : map.toHashMap().entrySet()) {
            Object value = entry.getValue();
            headers.put(entry.getKey(), value == null ? "" : value.toString());
        }
        return headers;
    }

    private static String joinComma(List<String> values) {
        StringBuilder builder = new StringBuilder();
        for (int index = 0; index < values.size(); index++) {
            if (index > 0) {
                builder.append(", ");
            }
            builder.append(values.get(index));
        }
        return builder.toString();
    }

    private static String orEmpty(@Nullable String value) {
        return value == null ? "" : value;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.isEmpty() ? fallback : message;
    }

    private interface SendOperation {
        boolean send(WebSocket socket);
    }

    private final class Listener extends WebSocketListener {
        private final String id;
        private final Connection connection;

        Listener(String id, Connection connection) {
            this.id = id;
            this.connection = connection;
        }

        @Override
        public void onOpen(WebSocket webSocket, Response response) {
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "open");
            payload.putString("protocol", orEmpty(response.header("Sec-WebSocket-Protocol")));
            emit(id, payload);
        }

        @Override
        public void onMessage(WebSocket webSocket, String text) {
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "message");
            payload.putString("dataType", "text");
            payload.putString("data", text);
            emit(id, payload);
        }

        @Override
        public void onMessage(WebSocket webSocket, ByteString bytes) {
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "message");
            payload.putString("dataType", "base64");
            payload.putString("data", Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP));
            emit(id, payload);
        }

        @Override
        public void onClosed(WebSocket webSocket, int code, String reason) {
            finish(id, connection, code, reason, true);
        }

        @Override
        public void onFailure(WebSocket webSocket, Throwable t, Response response) {
            if (!connection.terminal.compareAndSet(false, true)) {
                return;
            }
            connections.remove(id, connection);
            String message = messageOf(t, "WebSocket transport failed");
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "error");
            payload.putString("message", message);
            emit(id, payload);
            emitClose(id, 1006, message, false);
        }
    }
}
