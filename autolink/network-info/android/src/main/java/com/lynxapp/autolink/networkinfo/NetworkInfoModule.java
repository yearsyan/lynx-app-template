package com.lynxapp.autolink.networkinfo;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.telephony.TelephonyManager;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Network reachability exported to Lynx as NetworkInfo. Snapshots are read
 * on demand from ConnectivityManager; while started, a default-network
 * callback re-reads the snapshot on every capability change and forwards it
 * as a `networkInfo` global event — the same channel Sensors uses, so no
 * callback is held beyond a command ack. Reading the state requires
 * ACCESS_NETWORK_STATE, declared in this library's manifest and merged into
 * the host. The cellular generation is best-effort: it needs
 * READ_PHONE_STATE, which hosts typically do not hold, so it is simply null
 * in that case.
 */
@LynxNativeModule(name = NetworkInfoModule.NAME)
public final class NetworkInfoModule extends LynxContextModule {
    public static final String NAME = "NetworkInfo";
    public static final String EVENT_NAME = "networkInfo";

    private final Handler mainHandler = new Handler(Looper.getMainLooper());

    private ConnectivityManager connectivityManager;
    private TelephonyManager telephonyManager;
    private ConnectivityManager.NetworkCallback networkCallback;
    private boolean listening = false;
    private volatile boolean destroyed = false;
    @Nullable private String lastEmittedSignature;

    public NetworkInfoModule(LynxContext context) {
        super(context);
    }

    @LynxMethod
    public void getInfo(Callback callback) {
        ConnectivityManager manager = manager();
        if (manager == null) {
            callback.invoke("{\"error\":\"NetworkInfo has no application context\"}");
            return;
        }
        try {
            callback.invoke(value(snapshot(manager)));
        } catch (JSONException failure) {
            callback.invoke("{\"error\":\"NetworkInfo serialization failed\"}");
        }
    }

    @LynxMethod
    public void start(Callback callback) {
        ConnectivityManager manager = manager();
        if (manager == null) {
            callback.invoke("NetworkInfo has no application context");
            return;
        }
        if (listening) {
            callback.invoke("");
            return;
        }
        if (destroyed) {
            callback.invoke("NetworkInfo host has been destroyed");
            return;
        }
        try {
            networkCallback = new ConnectivityManager.NetworkCallback() {
                @Override
                public void onAvailable(@NonNull Network network) {
                    emitSnapshot();
                }

                @Override
                public void onCapabilitiesChanged(
                        @NonNull Network network,
                        @NonNull NetworkCapabilities capabilities) {
                    emitSnapshot();
                }

                @Override
                public void onLost(@NonNull Network network) {
                    emitSnapshot();
                }

                @Override
                public void onUnavailable() {
                    emitSnapshot();
                }
            };
            manager.registerDefaultNetworkCallback(networkCallback);
            listening = true;
            // Observers always start with the current state; later updates
            // arrive through the callback above.
            emitSnapshot();
            callback.invoke("");
        } catch (RuntimeException failure) {
            networkCallback = null;
            callback.invoke(failure.getMessage() != null
                    ? failure.getMessage()
                    : "Unable to listen for network changes");
        }
    }

    @LynxMethod
    public void stop(Callback callback) {
        stopListening();
        callback.invoke("");
    }

    @Override
    public void destroy() {
        destroyed = true;
        stopListening();
    }

    private void stopListening() {
        ConnectivityManager manager = manager();
        ConnectivityManager.NetworkCallback callback = networkCallback;
        networkCallback = null;
        listening = false;
        lastEmittedSignature = null;
        if (manager != null && callback != null) {
            try {
                manager.unregisterNetworkCallback(callback);
            } catch (RuntimeException ignored) {
                // The callback was already unregistered.
            }
        }
    }

    private void emitSnapshot() {
        if (destroyed) {
            return;
        }
        ConnectivityManager manager = manager();
        if (manager == null) {
            return;
        }
        JavaOnlyMap payload = snapshot(manager);
        // Capability callbacks fire for every signal-strength or address
        // change; observers only care about material transitions.
        String signature = payload.getBoolean("connected")
                + "|" + payload.getString("type")
                + "|" + payload.getString("cellularGeneration");
        if (signature.equals(lastEmittedSignature)) {
            return;
        }
        lastEmittedSignature = signature;
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

    private JavaOnlyMap snapshot(ConnectivityManager manager) {
        String type = "unknown";
        boolean connected = false;
        NetworkCapabilities capabilities = null;
        Network active = manager.getActiveNetwork();
        if (active != null) {
            capabilities = manager.getNetworkCapabilities(active);
        }
        if (capabilities != null) {
            if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                type = "wifi";
                connected = true;
            } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                type = "cellular";
                connected = true;
            } else if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                type = "ethernet";
                connected = true;
            } else {
                // VPN, Bluetooth tethering and other transports still count
                // as connectivity when they carry the internet capability.
                type = "other";
                connected = capabilities.hasCapability(
                        NetworkCapabilities.NET_CAPABILITY_INTERNET);
            }
        } else {
            type = "none";
        }
        JavaOnlyMap payload = new JavaOnlyMap();
        payload.putBoolean("connected", connected);
        payload.putString("type", type);
        String generation = cellularGeneration(type.equals("cellular"));
        if (generation != null) {
            payload.putString("cellularGeneration", generation);
        } else {
            payload.putString("cellularGeneration", null);
        }
        payload.putDouble("timestamp", System.currentTimeMillis());
        return payload;
    }

    /**
     * Maps the data network type to a generation. getDataNetworkType()
     * requires READ_PHONE_STATE on Android 12+; without it the generation is
     * unknown (null) rather than a reason to fail the whole snapshot.
     */
    @Nullable
    private String cellularGeneration(boolean cellular) {
        if (!cellular || telephonyManager() == null) {
            return null;
        }
        int networkType;
        try {
            networkType = telephonyManager().getDataNetworkType();
        } catch (SecurityException failure) {
            return null;
        }
        switch (networkType) {
            case TelephonyManager.NETWORK_TYPE_GPRS:
            case TelephonyManager.NETWORK_TYPE_EDGE:
            case TelephonyManager.NETWORK_TYPE_CDMA:
            case TelephonyManager.NETWORK_TYPE_1xRTT:
            case TelephonyManager.NETWORK_TYPE_IDEN:
            case TelephonyManager.NETWORK_TYPE_GSM:
                return "2g";
            case TelephonyManager.NETWORK_TYPE_UMTS:
            case TelephonyManager.NETWORK_TYPE_EVDO_0:
            case TelephonyManager.NETWORK_TYPE_EVDO_A:
            case TelephonyManager.NETWORK_TYPE_EVDO_B:
            case TelephonyManager.NETWORK_TYPE_HSDPA:
            case TelephonyManager.NETWORK_TYPE_HSUPA:
            case TelephonyManager.NETWORK_TYPE_HSPA:
            case TelephonyManager.NETWORK_TYPE_EHRPD:
            case TelephonyManager.NETWORK_TYPE_HSPAP:
            case TelephonyManager.NETWORK_TYPE_TD_SCDMA:
                return "3g";
            case TelephonyManager.NETWORK_TYPE_LTE:
            case TelephonyManager.NETWORK_TYPE_IWLAN:
                return "4g";
            case TelephonyManager.NETWORK_TYPE_NR:
                return "5g";
            case TelephonyManager.NETWORK_TYPE_UNKNOWN:
            default:
                return null;
        }
    }

    @Nullable
    private ConnectivityManager manager() {
        if (connectivityManager != null) {
            return connectivityManager;
        }
        Context context = mLynxContext != null ? mLynxContext : mContext;
        Context appContext = context != null ? context.getApplicationContext() : null;
        if (appContext == null) {
            return null;
        }
        connectivityManager =
                (ConnectivityManager) appContext.getSystemService(Context.CONNECTIVITY_SERVICE);
        return connectivityManager;
    }

    @Nullable
    private TelephonyManager telephonyManager() {
        if (telephonyManager != null) {
            return telephonyManager;
        }
        Context context = mLynxContext != null ? mLynxContext : mContext;
        Context appContext = context != null ? context.getApplicationContext() : null;
        if (appContext == null) {
            return null;
        }
        telephonyManager =
                (TelephonyManager) appContext.getSystemService(Context.TELEPHONY_SERVICE);
        return telephonyManager;
    }

    private static String value(JavaOnlyMap snapshot) throws JSONException {
        JSONObject result = new JSONObject();
        JSONObject value = new JSONObject();
        value.put("connected", snapshot.getBoolean("connected"));
        value.put("type", snapshot.getString("type"));
        String generation = snapshot.getString("cellularGeneration");
        value.put("cellularGeneration", generation != null ? generation : JSONObject.NULL);
        value.put("timestamp", snapshot.getDouble("timestamp"));
        result.put("value", value);
        return result.toString();
    }
}
