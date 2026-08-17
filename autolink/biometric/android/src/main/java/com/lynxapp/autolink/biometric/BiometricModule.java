package com.lynxapp.autolink.biometric;

import android.app.KeyguardManager;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.fragment.app.FragmentActivity;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.Signature;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * System biometric prompt with an optional device-credential fallback.
 * The prompt is hosted by the LynxView's FragmentActivity, so hosts must
 * build their Lynx views from a FragmentActivity context.
 *
 * Also maintains a hardware-bound EC P-256 signing key in AndroidKeyStore
 * whose private key is usable only inside a BIOMETRIC_STRONG prompt
 * (BiometricPrompt.CryptoObject), for server-verifiable challenges.
 */
@LynxNativeModule(name = BiometricModule.NAME)
public final class BiometricModule extends LynxContextModule {
    public static final String NAME = "Biometric";

    private static final String DEFAULT_CANCEL_TEXT = "Cancel";
    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
    private static final String KEY_ALIAS = "lynx.biometric.signing";

    /** Guards against overlapping system prompts on this Lynx view. */
    private final AtomicBoolean promptActive = new AtomicBoolean(false);
    /** Keystore generation runs off the Lynx thread. */
    private final ExecutorService executor = Executors.newFixedThreadPool(1);

    public BiometricModule(LynxContext context) {
        super(context);
    }

    @Override
    public void destroy() {
        executor.shutdownNow();
    }

    @LynxMethod
    public void checkSupport(Callback callback) {
        try {
            callback.invoke(supportJSON());
        } catch (Throwable error) {
            callback.invoke(errorJSON(messageOf(error, "Unable to query biometric support")));
        }
    }

    @LynxMethod
    public void authenticate(String optionsJSON, Callback callback) {
        final Options options;
        try {
            options = Options.parse(optionsJSON);
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric options")));
            return;
        }
        if (!promptActive.compareAndSet(false, true)) {
            callback.invoke(outcomeJSON("busy",
                    "Another authentication request is already active"));
            return;
        }

        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            FragmentActivity activity = resolveFragmentActivity();
            if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                complete(callback, "unavailable",
                        "The biometric prompt has no usable host activity");
                return;
            }
            Executor executor = main::post;
            BiometricPrompt prompt = new BiometricPrompt(activity, executor,
                    new BiometricPrompt.AuthenticationCallback() {
                        @Override
                        public void onAuthenticationError(
                                int errorCode, @NonNull CharSequence errString) {
                            complete(callback, outcomeForErrorCode(errorCode),
                                    errString.toString());
                        }

                        @Override
                        public void onAuthenticationSucceeded(
                                @NonNull BiometricPrompt.AuthenticationResult result) {
                            complete(callback, "success", "");
                        }
                    });
            try {
                prompt.authenticate(promptInfo(options));
            } catch (Throwable error) {
                complete(callback, "unavailable",
                        messageOf(error, "Unable to show the biometric prompt"));
            }
        });
    }

    private BiometricPrompt.PromptInfo promptInfo(Options options) {
        BiometricPrompt.PromptInfo.Builder info = new BiometricPrompt.PromptInfo.Builder()
                .setTitle(options.title)
                .setDescription(options.reason);
        if (options.subtitle != null && !options.subtitle.isEmpty()) {
            info.setSubtitle(options.subtitle);
        }
        if (options.allowDeviceCredential) {
            // A negative button cannot coexist with the credential fallback.
            info.setAllowedAuthenticators(
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL
                            | BiometricManager.Authenticators.BIOMETRIC_WEAK);
        } else {
            info.setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK);
            info.setNegativeButtonText(options.cancelButtonText == null
                    || options.cancelButtonText.isEmpty()
                            ? DEFAULT_CANCEL_TEXT
                            : options.cancelButtonText);
        }
        return info.build();
    }

    @LynxMethod
    public void createSigningKey(Callback callback) {
        executor.execute(() -> {
            String gate = strongBiometricGate();
            if (gate != null) {
                callback.invoke(cryptoJSON(gate, "", null, "publicKey"));
                return;
            }
            try {
                KeyStore keyStore = KeyStore.getInstance(ANDROID_KEYSTORE);
                keyStore.load(null);
                // createSigningKey replaces any previous key on purpose:
                // the server rebinds to the returned public key anyway.
                try {
                    keyStore.deleteEntry(KEY_ALIAS);
                } catch (RuntimeException ignored) {
                    // No entry yet or deletion unsupported; generation wins.
                }
                KeyPairGenerator generator =
                        KeyPairGenerator.getInstance("EC", ANDROID_KEYSTORE);
                generator.initialize(
                        new KeyGenParameterSpec.Builder(
                                KEY_ALIAS,
                                KeyProperties.PURPOSE_SIGN
                                        | KeyProperties.PURPOSE_VERIFY)
                                .setAlgorithmParameterSpec(
                                        new ECGenParameterSpec("secp256r1"))
                                .setDigests(KeyProperties.DIGEST_SHA256)
                                // The private key is only usable inside a
                                // BIOMETRIC_STRONG prompt (CryptoObject).
                                .setUserAuthenticationRequired(true)
                                .setInvalidatedByBiometricEnrollment(true)
                                .build());
                KeyPair keyPair = generator.generateKeyPair();
                String publicKey = Base64.encodeToString(
                        rawPoint((ECPublicKey) keyPair.getPublic()), Base64.NO_WRAP);
                callback.invoke(cryptoJSON("success", "", publicKey, "publicKey"));
            } catch (Throwable error) {
                callback.invoke(cryptoJSON("unknown",
                        messageOf(error, "Unable to create the signing key"), null,
                        "publicKey"));
            }
        });
    }

    @LynxMethod
    public void signChallenge(String optionsJSON, Callback callback) {
        final Options options;
        final byte[] challenge;
        try {
            options = Options.parse(optionsJSON);
            challenge = Base64.decode(options.challenge, Base64.NO_WRAP);
            if (challenge == null || challenge.length == 0) {
                throw new IllegalArgumentException("Biometric challenge must not be empty");
            }
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric options")));
            return;
        }
        if (!promptActive.compareAndSet(false, true)) {
            callback.invoke(cryptoJSON("busy",
                    "Another authentication request is already active", null,
                    "signature"));
            return;
        }

        final Signature signature;
        try {
            KeyStore keyStore = KeyStore.getInstance(ANDROID_KEYSTORE);
            keyStore.load(null);
            KeyStore.Entry entry = keyStore.getEntry(KEY_ALIAS, null);
            if (!(entry instanceof KeyStore.PrivateKeyEntry)) {
                promptActive.set(false);
                callback.invoke(cryptoJSON("keyNotFound",
                        "No signing key on this device; create it first", null,
                        "signature"));
                return;
            }
            signature = Signature.getInstance("SHA256withECDSA");
            // Initializes with the auth-gated key; the actual sign below only
            // succeeds inside the authenticated CryptoObject callback.
            signature.initSign(((KeyStore.PrivateKeyEntry) entry).getPrivateKey());
        } catch (KeyPermanentlyInvalidatedException error) {
            promptActive.set(false);
            callback.invoke(cryptoJSON("keyNotFound",
                    "The signing key was invalidated by a biometric change", null,
                    "signature"));
            return;
        } catch (Throwable error) {
            promptActive.set(false);
            callback.invoke(cryptoJSON("unknown",
                    messageOf(error, "Unable to access the signing key"), null,
                    "signature"));
            return;
        }

        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            FragmentActivity activity = resolveFragmentActivity();
            if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                completeCrypto(callback, "unavailable",
                        "The biometric prompt has no usable host activity", null);
                return;
            }
            Executor executor = main::post;
            BiometricPrompt prompt = new BiometricPrompt(activity, executor,
                    new BiometricPrompt.AuthenticationCallback() {
                        @Override
                        public void onAuthenticationError(
                                int errorCode, @NonNull CharSequence errString) {
                            completeCrypto(callback, outcomeForErrorCode(errorCode),
                                    errString.toString(), null);
                        }

                        @Override
                        public void onAuthenticationSucceeded(
                                @NonNull BiometricPrompt.AuthenticationResult result) {
                            try {
                                Signature authenticated =
                                        result.getCryptoObject().getSignature();
                                authenticated.update(challenge);
                                byte[] raw = ecdsaDerToRaw(authenticated.sign());
                                if (raw.length != 64) {
                                    throw new IllegalStateException(
                                            "Unexpected ECDSA signature length");
                                }
                                completeCrypto(callback, "success", "",
                                        Base64.encodeToString(raw, Base64.NO_WRAP));
                            } catch (Throwable error) {
                                completeCrypto(callback, "unknown",
                                        messageOf(error, "Unable to sign the challenge"),
                                        null);
                            }
                        }
                    });
            BiometricPrompt.PromptInfo.Builder info =
                    new BiometricPrompt.PromptInfo.Builder()
                            .setTitle(options.title)
                            .setDescription(options.reason)
                            // CryptoObject requires Class 3 (strong) biometrics.
                            .setAllowedAuthenticators(
                                    BiometricManager.Authenticators.BIOMETRIC_STRONG)
                            .setNegativeButtonText(options.cancelButtonText == null
                                    || options.cancelButtonText.isEmpty()
                                            ? DEFAULT_CANCEL_TEXT
                                            : options.cancelButtonText);
            if (options.subtitle != null && !options.subtitle.isEmpty()) {
                info.setSubtitle(options.subtitle);
            }
            try {
                prompt.authenticate(info.build(), new BiometricPrompt.CryptoObject(signature));
            } catch (Throwable error) {
                completeCrypto(callback, "unavailable",
                        messageOf(error, "Unable to show the biometric prompt"), null);
            }
        });
    }

    /**
     * Returns null when a Class 3 (strong) biometric is usable right now;
     * otherwise the outcome code explaining why the signing key cannot work.
     */
    @Nullable
    private String strongBiometricGate() {
        int status;
        try {
            status = BiometricManager.from(applicationContext())
                    .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG);
        } catch (Throwable error) {
            return "notSupported";
        }
        switch (status) {
            case BiometricManager.BIOMETRIC_SUCCESS:
                return null;
            case BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED:
                return "notEnrolled";
            case BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE:
            case BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE:
                return "noHardware";
            default:
                return "notSupported";
        }
    }

    private void completeCrypto(Callback callback, String code, String message,
            @Nullable String payload) {
        promptActive.set(false);
        callback.invoke(cryptoJSON(code, message, payload, "signature"));
    }

    /** value = { code, message, field: payload } with the payload only on success. */
    private static String cryptoJSON(
            String code, String message, @Nullable String payload, String field) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("message", message == null ? "" : message);
            if (payload != null) {
                value.put(field, payload);
            }
            JSONObject result = new JSONObject();
            result.put("error", "");
            result.put("value", value);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"error\":\"Unable to encode the biometric result\"}";
        }
    }

    /** Uncompressed EC point: 0x04 || X(32) || Y(32). */
    private static byte[] rawPoint(ECPublicKey publicKey) {
        byte[] raw = new byte[65];
        raw[0] = 0x04;
        copyPadded(publicKey.getW().getAffineX().toByteArray(), raw, 1, 32);
        copyPadded(publicKey.getW().getAffineY().toByteArray(), raw, 33, 32);
        return raw;
    }

    /** Right-aligns a positive big-endian integer into exactly `length` bytes. */
    private static void copyPadded(byte[] source, byte[] destination,
            int offset, int length) {
        int start = Math.max(0, source.length - length);
        int pad = length - (source.length - start);
        for (int i = 0; i < pad; i++) {
            destination[offset + i] = 0;
        }
        System.arraycopy(source, start, destination, offset + pad,
                source.length - start);
    }

    /**
     * Converts an ASN.1 DER ECDSA signature (SEQUENCE of the two INTEGERs)
     * into the fixed-width 64-byte raw r || s form used by the contract.
     */
    static byte[] ecdsaDerToRaw(byte[] der) {
        if (der == null || der.length < 8 || der[0] != 0x30) {
            throw new IllegalArgumentException("Malformed ECDSA signature");
        }
        int index = (der[1] & 0x80) == 0 ? 2 : 2 + (der[1] & 0x7f);
        int rLength = readIntegerHeader(der, index);
        index += 2;
        byte[] r = stripSignByte(der, index, rLength);
        index += rLength;
        int sLength = readIntegerHeader(der, index);
        index += 2;
        byte[] s = stripSignByte(der, index, sLength);

        byte[] raw = new byte[64];
        copyPadded(r, raw, 0, 32);
        copyPadded(s, raw, 32, 32);
        return raw;
    }

    private static int readIntegerHeader(byte[] der, int index) {
        if (index + 1 >= der.length || der[index] != 0x02) {
            throw new IllegalArgumentException("Malformed ECDSA signature");
        }
        return der[index + 1] & 0xff;
    }

    /** Drops the ASN.1 leading sign byte when present. */
    private static byte[] stripSignByte(byte[] der, int offset, int length) {
        int start = offset;
        int count = length;
        if (count > 1 && der[start] == 0x00 && (der[start + 1] & 0x80) != 0) {
            start += 1;
            count -= 1;
        }
        while (count > 0 && der[start] == 0x00) {
            start += 1;
            count -= 1;
        }
        byte[] value = new byte[count];
        System.arraycopy(der, start, value, 0, count);
        return value;
    }

    private void complete(Callback callback, String code, String message) {
        promptActive.set(false);
        callback.invoke(outcomeJSON(code, message));
    }

    /**
     * Resolves the FragmentActivity hosting this LynxView. The LynxContext
     * is a MutableContextWrapper whose base context is the activity the
     * view was built with.
     */
    @Nullable
    private FragmentActivity resolveFragmentActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context instanceof ContextWrapper) {
            if (context instanceof FragmentActivity) {
                return (FragmentActivity) context;
            }
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }

    private String supportJSON() throws JSONException {
        Context context = applicationContext();
        JSONObject value = new JSONObject();
        int status = BiometricManager.from(context)
                .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK);
        value.put("canAuthenticate", status == BiometricManager.BIOMETRIC_SUCCESS);
        value.put("reason", reasonForManagerStatus(status));
        // androidx.biometric does not expose the sensor kind (face vs
        // fingerprint), so the contract falls back to "unknown" here.
        value.put("biometryType", "unknown");
        KeyguardManager keyguard =
                (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
        value.put("deviceCredentialSetup", keyguard != null && keyguard.isDeviceSecure());

        JSONObject result = new JSONObject();
        result.put("error", "");
        result.put("value", value);
        return result.toString();
    }

    private static String reasonForManagerStatus(int status) {
        switch (status) {
            case BiometricManager.BIOMETRIC_SUCCESS:
                return "ok";
            case BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED:
                return "notEnrolled";
            case BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE:
            case BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE:
            case BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED:
                return "noHardware";
            default:
                return "unknown";
        }
    }

    private static String outcomeForErrorCode(int errorCode) {
        switch (errorCode) {
            case BiometricPrompt.ERROR_USER_CANCELED:
                return "userCancel";
            case BiometricPrompt.ERROR_NEGATIVE_BUTTON:
                return "userFallback";
            case BiometricPrompt.ERROR_CANCELED:
                return "systemCancel";
            case BiometricPrompt.ERROR_TIMEOUT:
                return "timeout";
            case BiometricPrompt.ERROR_LOCKOUT:
            case BiometricPrompt.ERROR_LOCKOUT_PERMANENT:
                return "locked";
            case BiometricPrompt.ERROR_NO_BIOMETRICS:
                return "notEnrolled";
            case BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL:
                return "noDeviceCredential";
            case BiometricPrompt.ERROR_HW_UNAVAILABLE:
            case BiometricPrompt.ERROR_HW_NOT_PRESENT:
                return "noHardware";
            default:
                return "unknown";
        }
    }

    private static String outcomeJSON(String code, String message) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("message", message == null ? "" : message);
            JSONObject result = new JSONObject();
            result.put("error", "");
            result.put("value", value);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"error\":\"Unable to encode the biometric result\"}";
        }
    }

    private static String errorJSON(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message);
            return result.toString();
        } catch (JSONException exception) {
            return "{\"error\":\"Unable to encode the biometric error\"}";
        }
    }

    private Context applicationContext() {
        Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
        if (context == null && mContext != null) {
            context = mContext.getApplicationContext();
        }
        if (context == null) {
            throw new IllegalStateException("Biometric has no host context");
        }
        return context;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }

    /** Bridge-level subset of the shared option contracts. */
    private static final class Options {
        final String title;
        @Nullable final String subtitle;
        final String reason;
        @Nullable final String cancelButtonText;
        final boolean allowDeviceCredential;
        /** Base64 challenge; only signChallenge populates it. */
        @Nullable final String challenge;

        private Options(
                String title,
                @Nullable String subtitle,
                String reason,
                @Nullable String cancelButtonText,
                boolean allowDeviceCredential,
                @Nullable String challenge) {
            this.title = title;
            this.subtitle = subtitle;
            this.reason = reason;
            this.cancelButtonText = cancelButtonText;
            this.allowDeviceCredential = allowDeviceCredential;
            this.challenge = challenge;
        }

        static Options parse(String optionsJSON) throws JSONException {
            JSONObject json = new JSONObject(optionsJSON == null ? "{}" : optionsJSON);
            String title = requireNonEmpty(json.optString("title"), "Biometric title");
            String reason = requireNonEmpty(json.optString("reason"), "Biometric reason");
            return new Options(
                    title,
                    optionalOrNull(json.optString("subtitle")),
                    reason,
                    optionalOrNull(json.optString("cancelButtonText")),
                    json.optBoolean("allowDeviceCredential", false),
                    optionalOrNull(json.optString("challenge")));
        }

        private static String requireNonEmpty(String value, String field) {
            String trimmed = value == null ? "" : value.trim();
            if (trimmed.isEmpty()) {
                throw new IllegalArgumentException(field + " must not be empty");
            }
            return trimmed;
        }

        @Nullable
        private static String optionalOrNull(String value) {
            if (value == null) {
                return null;
            }
            String trimmed = value.trim();
            return trimmed.isEmpty() ? null : trimmed;
        }
    }
}
