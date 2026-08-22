package com.lynxapp.autolink.navigation;

import android.app.Activity;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;

import org.json.JSONObject;

/**
 * Host-installed navigation for in-app Lynx bundle routes.
 *
 * The autolinked Navigation module resolves the Activity hosting the calling
 * Lynx view and forwards {@code open}/{@code close} here, because only the
 * host knows how to present its Lynx pages. Implementations must be
 * stateless: the Activity argument identifies the calling route. The
 * result-routing methods are exempt: they correlate the opened route with
 * the opener's pending result callback through a host-owned registry.
 */
public interface LynxRouteHandler {
    /** Opens another Lynx bundle from the route hosted by {@code activity}. */
    void open(Activity activity, ReadableMap options, Callback callback);

    /** Closes the route hosted by {@code activity} unless it is the root. */
    void close(Activity activity, Callback callback);

    /**
     * Opens another Lynx bundle and keeps {@code resultCallback} pending until
     * the opened route closes. The callback is invoked exactly once with a
     * JSON envelope: {@code {"error": message}} when the open fails, otherwise
     * {@code {"value": result}} after a {@code closeWithResult}, or {@code {}}
     * when the route closed without one.
     */
    default void openForResult(
            Activity activity, ReadableMap options, Callback resultCallback) {
        resultCallback.invoke(RouteResultEnvelope.error("openForResult is not supported by this host"));
    }

    /**
     * Closes the route hosted by {@code activity}, delivering {@code result} to
     * the opener's pending {@code openForResult} callback when the route was
     * opened for a result; the result is dropped otherwise.
     */
    default void closeWithResult(
            Activity activity, ReadableMap result, Callback callback) {
        callback.invoke("closeWithResult is not supported by this host");
    }

    /** JSON envelopes carried by openForResult callbacks. */
    final class RouteResultEnvelope {
        private RouteResultEnvelope() {}

        public static String error(String message) {
            JSONObject envelope = new JSONObject();
            try {
                envelope.put("error", message);
            } catch (org.json.JSONException ignored) {
                // JSONObject.putString only throws for null keys/values.
            }
            return envelope.toString();
        }

        /** @param jsonValue a JSON-encodable value (e.g. JSONObject) */
        public static String value(Object jsonValue) {
            JSONObject envelope = new JSONObject();
            try {
                envelope.put("value", jsonValue);
            } catch (org.json.JSONException ignored) {
                // JSONObject.putString only throws for null keys/values.
            }
            return envelope.toString();
        }

        public static String empty() {
            return new JSONObject().toString();
        }
    }
}
