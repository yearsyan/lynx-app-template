package com.lynxapp.autolink.router;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.ContextWrapper;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

/**
 * Route navigation exported to Lynx as `Router`.
 *
 * {@code open}/{@code close} delegate to the host-installed
 * {@link LynxRouteHandler}; {@code openURL} resolves the URL through the
 * system (any app that registered the scheme can handle it, including this
 * app's own scheme pages).
 */
@LynxNativeModule(name = RouterModule.NAME)
public final class RouterModule extends LynxContextModule {
    public static final String NAME = "Router";
    public static final String PRESENTATION_PUSH = "push";
    public static final String PRESENTATION_SHEET = "sheet";
    public static final String ANIMATION_DEFAULT = "default";
    public static final String ANIMATION_FADE = "fade";
    public static final String ANIMATION_NONE = "none";

    private static volatile LynxRouteHandler routeHandler;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    public RouterModule(LynxContext context) {
        super(context);
    }

    /** Installs the host navigation delegate used by {@code open}/{@code close}. */
    public static void setRouteHandler(@Nullable LynxRouteHandler handler) {
        routeHandler = handler;
    }

    public static boolean isLynxRouteAnimation(String value) {
        return ANIMATION_DEFAULT.equals(value)
                || ANIMATION_FADE.equals(value) || ANIMATION_NONE.equals(value);
    }

    @LynxMethod
    public void open(ReadableMap options, Callback callback) {
        LynxRouteHandler handler = routeHandler;
        Activity activity = resolveActivity();
        if (handler == null || activity == null) {
            callback.invoke("Router has no Activity host");
            return;
        }
        handler.open(activity, options, callback);
    }

    @LynxMethod
    public void close(Callback callback) {
        LynxRouteHandler handler = routeHandler;
        Activity activity = resolveActivity();
        if (handler == null || activity == null) {
            callback.invoke("Router has no Activity host");
            return;
        }
        handler.close(activity, callback);
    }

    @LynxMethod
    public void openURL(String url, Callback callback) {
        Uri uri = url == null ? Uri.EMPTY : Uri.parse(url);
        if (url == null || url.trim().isEmpty() || uri.getScheme() == null
                || !url.equals(url.trim())) {
            callback.invoke("Invalid URL: " + url);
            return;
        }
        Activity activity = resolveActivity();
        Context context = activity != null
                ? activity
                : mLynxContext != null ? mLynxContext.getApplicationContext() : mContext;
        if (context == null) {
            callback.invoke("Router has no host context");
            return;
        }
        Intent intent = new Intent(Intent.ACTION_VIEW, uri);
        if (activity == null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        }
        mainHandler.post(() -> {
            try {
                context.startActivity(intent);
                callback.invoke("");
            } catch (ActivityNotFoundException error) {
                callback.invoke("No activity found for URL: " + url);
            } catch (Throwable error) {
                callback.invoke(error.getMessage() != null
                        ? error.getMessage()
                        : "Unable to open URL");
            }
        });
    }

    /**
     * Walks from the Lynx context to the hosting Activity. A LynxView is
     * built with its Activity as the base context, so the wrapper chain
     * bottomes out there; null means the route cannot be presented.
     */
    @Nullable
    private Activity resolveActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context != null) {
            if (context instanceof Activity) {
                return (Activity) context;
            }
            if (!(context instanceof ContextWrapper)) {
                return null;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }
}
