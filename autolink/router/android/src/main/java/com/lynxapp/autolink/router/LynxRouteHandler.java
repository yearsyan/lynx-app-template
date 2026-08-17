package com.lynxapp.autolink.router;

import android.app.Activity;

import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;

/**
 * Host-installed navigation for in-app Lynx bundle routes.
 *
 * The autolinked Router module resolves the Activity hosting the calling
 * Lynx view and forwards {@code open}/{@code close} here, because only the
 * host knows how to present its Lynx pages. Implementations must be
 * stateless: the Activity argument identifies the calling route.
 */
public interface LynxRouteHandler {
    /** Opens another Lynx bundle from the route hosted by {@code activity}. */
    void open(Activity activity, ReadableMap options, Callback callback);

    /** Closes the route hosted by {@code activity} unless it is the root. */
    void close(Activity activity, Callback callback);
}
