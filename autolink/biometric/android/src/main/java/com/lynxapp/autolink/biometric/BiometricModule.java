package com.lynxapp.autolink.biometric;

import android.app.KeyguardManager;
import android.content.Context;
import android.content.ContextWrapper;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyInfo;
import android.security.keystore.KeyPermanentlyInvalidatedException;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.biometric.BiometricManager;
import androidx.biometric.BiometricPrompt;
import androidx.fragment.app.FragmentActivity;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.lang.reflect.Method;
import java.util.UUID;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;

/**
 * Policy-based local authentication plus v2 biometric-gated P-256 signing.
 * Signing keys have independent key ids, so creating or registering a new key
 * never destroys the currently registered one.
 */
@LynxNativeModule(name = BiometricModule.NAME)
public final class BiometricModule extends LynxContextModule {
    public static final String NAME = "Biometric";

    private static final String DEFAULT_CANCEL_TEXT = "Cancel";
    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
    private static final String KEY_ALIAS_PREFIX = "lynx.biometric.signing.v2.";
    private static final String POLICY_WEAK = "biometricWeak";
    private static final String POLICY_STRONG = "biometricStrong";
    private static final String POLICY_DEVICE_OWNER = "deviceOwnerAuthentication";
    private static final byte[] SIGNING_DOMAIN =
            "LYNX_BIOMETRIC_V2\0".getBytes(StandardCharsets.US_ASCII);
    private static final Pattern SCOPE_PATTERN =
            Pattern.compile("^[A-Za-z0-9._-]{1,64}$");
    private static final Pattern KEY_ID_PATTERN = Pattern.compile(
            "^[A-Za-z0-9._-]{1,64}~[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$");
    private static final Pattern BASE64_PATTERN = Pattern.compile(
            "^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$");

    private final AtomicBoolean promptActive = new AtomicBoolean(false);
    private final ExecutorService keyExecutor = Executors.newSingleThreadExecutor();

    public BiometricModule(LynxContext context) {
        super(context);
    }

    @Override
    public void destroy() {
        keyExecutor.shutdownNow();
    }

    @LynxMethod
    public void checkSupport(String optionsJSON, Callback callback) {
        try {
            String policy = parsePolicyOptions(optionsJSON);
            callback.invoke(supportJSON(policy));
        } catch (Throwable error) {
            callback.invoke(errorJSON(messageOf(error, "Unable to query biometric support")));
        }
    }

    @LynxMethod
    public void authenticate(String optionsJSON, Callback callback) {
        final PromptOptions options;
        try {
            options = PromptOptions.parse(optionsJSON, true);
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric options")));
            return;
        }
        if (!promptActive.compareAndSet(false, true)) {
            callback.invoke(outcomeJSON("busy",
                    "Another authentication request is already active", options.policy));
            return;
        }

        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            FragmentActivity activity = resolveFragmentActivity();
            if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                complete(callback, "unavailable",
                        "The authentication prompt has no usable host activity",
                        options.policy);
                return;
            }
            Executor executor = main::post;
            BiometricPrompt prompt = new BiometricPrompt(activity, executor,
                    new BiometricPrompt.AuthenticationCallback() {
                        @Override
                        public void onAuthenticationError(
                                int errorCode, @NonNull CharSequence errString) {
                            complete(callback, outcomeForErrorCode(errorCode),
                                    errString.toString(), options.policy);
                        }

                        @Override
                        public void onAuthenticationSucceeded(
                                @NonNull BiometricPrompt.AuthenticationResult result) {
                            complete(callback, "success", "", options.policy);
                        }
                    });
            try {
                prompt.authenticate(promptInfo(options));
            } catch (Throwable error) {
                complete(callback, "unavailable",
                        messageOf(error, "Unable to show the authentication prompt"),
                        options.policy);
            }
        });
    }

    private BiometricPrompt.PromptInfo promptInfo(PromptOptions options) {
        BiometricPrompt.PromptInfo.Builder info = new BiometricPrompt.PromptInfo.Builder()
                .setTitle(options.title)
                .setDescription(options.reason)
                .setAllowedAuthenticators(authenticatorsForPolicy(options.policy));
        if (options.subtitle != null) info.setSubtitle(options.subtitle);
        if (!POLICY_DEVICE_OWNER.equals(options.policy)) {
            info.setNegativeButtonText(options.cancelButtonText == null
                    ? DEFAULT_CANCEL_TEXT : options.cancelButtonText);
        }
        return info.build();
    }

    @LynxMethod
    public void createSigningKey(String optionsJSON, Callback callback) {
        final KeyCreateOptions options;
        try {
            options = KeyCreateOptions.parse(optionsJSON);
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric key options")));
            return;
        }
        keyExecutor.execute(() -> createSigningKeyOnExecutor(options, callback));
    }

    private void createSigningKeyOnExecutor(KeyCreateOptions options, Callback callback) {
        String gate = strongBiometricGate();
        if (gate != null) {
            callback.invoke(keyJSON(gate, "", null, null, null,
                    "unknown", "none", null));
            return;
        }

        String keyId = options.scope + "~" + UUID.randomUUID().toString().toLowerCase();
        String alias = aliasForKeyId(keyId);
        try {
            KeyPair pair;
            boolean attestationRequested = options.attestationChallenge != null;
            try {
                pair = generateSigningKey(alias, options.attestationChallenge);
            } catch (Throwable attestationError) {
                if (options.attestationChallenge == null) throw attestationError;
                // Key attestation is an optional registration signal. Devices
                // that cannot produce it still get a usable auth-bound key and
                // report attestationType=none to the server.
                deleteAliasQuietly(alias);
                pair = generateSigningKey(alias, null);
                attestationRequested = false;
            }

            KeyStore keyStore = loadedKeyStore();
            String publicKey = Base64.encodeToString(
                    rawPoint((ECPublicKey) pair.getPublic()), Base64.NO_WRAP);
            String securityLevel = securityLevel(pair.getPrivate());
            JSONArray certificates = null;
            String attestationType = "none";
            Certificate leaf = keyStore.getCertificate(alias);
            boolean attested = attestationRequested
                    && leaf != null
                    && hasAndroidKeyAttestation(leaf);
            if (attested) {
                certificates = certificateChain(keyStore, alias, true);
                if (certificates.length() > 0) attestationType = "androidKey";
            }
            callback.invoke(keyJSON("success", "", keyId, options.scope,
                    publicKey, securityLevel, attestationType, certificates));
        } catch (Throwable error) {
            deleteAliasQuietly(alias);
            callback.invoke(keyJSON("unknown",
                    messageOf(error, "Unable to create the signing key"),
                    null, null, null, "unknown", "none", null));
        }
    }

    @LynxMethod
    public void getSigningKey(String optionsJSON, Callback callback) {
        final String keyId;
        try {
            keyId = parseKeyIdOptions(optionsJSON);
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric key options")));
            return;
        }
        keyExecutor.execute(() -> {
            try {
                KeyStore keyStore = loadedKeyStore();
                KeyStore.Entry entry = keyStore.getEntry(aliasForKeyId(keyId), null);
                if (!(entry instanceof KeyStore.PrivateKeyEntry)) {
                    callback.invoke(keyJSON("keyNotFound",
                            "No signing key with this keyId exists", null, null,
                            null, "unknown", "none", null));
                    return;
                }
                KeyStore.PrivateKeyEntry privateEntry =
                        (KeyStore.PrivateKeyEntry) entry;
                String publicKey = Base64.encodeToString(
                        rawPoint((ECPublicKey) privateEntry.getCertificate().getPublicKey()),
                        Base64.NO_WRAP);
                boolean attested = hasAndroidKeyAttestation(
                        privateEntry.getCertificate());
                JSONArray certificates = certificateChain(
                        keyStore, aliasForKeyId(keyId), attested);
                String attestationType = attested ? "androidKey" : "none";
                callback.invoke(keyJSON("success", "", keyId,
                        scopeFromKeyId(keyId), publicKey,
                        securityLevel(privateEntry.getPrivateKey()),
                        attestationType,
                        "androidKey".equals(attestationType) ? certificates : null));
            } catch (Throwable error) {
                callback.invoke(keyJSON("unknown",
                        messageOf(error, "Unable to read the signing key"),
                        null, null, null, "unknown", "none", null));
            }
        });
    }

    @LynxMethod
    public void deleteSigningKey(String optionsJSON, Callback callback) {
        final String keyId;
        try {
            keyId = parseKeyIdOptions(optionsJSON);
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric key options")));
            return;
        }
        if (!promptActive.compareAndSet(false, true)) {
            callback.invoke(deleteJSON("busy",
                    "Another authentication request is already active", keyId));
            return;
        }
        keyExecutor.execute(() -> {
            try {
                KeyStore keyStore = loadedKeyStore();
                String alias = aliasForKeyId(keyId);
                if (!keyStore.containsAlias(alias)) {
                    promptActive.set(false);
                    callback.invoke(deleteJSON("keyNotFound",
                            "No signing key with this keyId exists", keyId));
                    return;
                }
                keyStore.deleteEntry(alias);
                promptActive.set(false);
                callback.invoke(deleteJSON("success", "", keyId));
            } catch (Throwable error) {
                promptActive.set(false);
                callback.invoke(deleteJSON("unknown",
                        messageOf(error, "Unable to delete the signing key"), keyId));
            }
        });
    }

    @LynxMethod
    public void signChallenge(String optionsJSON, Callback callback) {
        final SignOptions options;
        try {
            options = SignOptions.parse(optionsJSON);
        } catch (JSONException | IllegalArgumentException error) {
            callback.invoke(errorJSON(messageOf(error, "Invalid biometric signing options")));
            return;
        }
        if (!promptActive.compareAndSet(false, true)) {
            callback.invoke(signatureJSON("busy",
                    "Another authentication request is already active",
                    options.keyId, null));
            return;
        }

        final Signature signature;
        try {
            KeyStore.Entry entry = loadedKeyStore().getEntry(
                    aliasForKeyId(options.keyId), null);
            if (!(entry instanceof KeyStore.PrivateKeyEntry)) {
                promptActive.set(false);
                callback.invoke(signatureJSON("keyNotFound",
                        "No signing key with this keyId exists", options.keyId, null));
                return;
            }
            signature = Signature.getInstance("SHA256withECDSA");
            signature.initSign(((KeyStore.PrivateKeyEntry) entry).getPrivateKey());
        } catch (KeyPermanentlyInvalidatedException error) {
            promptActive.set(false);
            deleteAliasQuietly(aliasForKeyId(options.keyId));
            callback.invoke(signatureJSON("keyNotFound",
                    "The signing key was invalidated by a biometric change",
                    options.keyId, null));
            return;
        } catch (Throwable error) {
            promptActive.set(false);
            callback.invoke(signatureJSON("unknown",
                    messageOf(error, "Unable to access the signing key"),
                    options.keyId, null));
            return;
        }

        Handler main = new Handler(Looper.getMainLooper());
        main.post(() -> {
            FragmentActivity activity = resolveFragmentActivity();
            if (activity == null || activity.isFinishing() || activity.isDestroyed()) {
                completeSignature(callback, "unavailable",
                        "The biometric prompt has no usable host activity",
                        options.keyId, null);
                return;
            }
            Executor executor = main::post;
            BiometricPrompt prompt = new BiometricPrompt(activity, executor,
                    new BiometricPrompt.AuthenticationCallback() {
                        @Override
                        public void onAuthenticationError(
                                int errorCode, @NonNull CharSequence errString) {
                            completeSignature(callback, outcomeForErrorCode(errorCode),
                                    errString.toString(), options.keyId, null);
                        }

                        @Override
                        public void onAuthenticationSucceeded(
                                @NonNull BiometricPrompt.AuthenticationResult result) {
                            try {
                                BiometricPrompt.CryptoObject crypto = result.getCryptoObject();
                                if (crypto == null || crypto.getSignature() == null) {
                                    throw new IllegalStateException(
                                            "Authentication returned no signing operation");
                                }
                                Signature authenticated = crypto.getSignature();
                                authenticated.update(options.payload);
                                byte[] raw = ecdsaDerToRaw(authenticated.sign());
                                completeSignature(callback, "success", "", options.keyId,
                                        Base64.encodeToString(raw, Base64.NO_WRAP));
                            } catch (Throwable error) {
                                completeSignature(callback, "unknown",
                                        messageOf(error, "Unable to sign the challenge"),
                                        options.keyId, null);
                            }
                        }
                    });
            BiometricPrompt.PromptInfo.Builder info =
                    new BiometricPrompt.PromptInfo.Builder()
                            .setTitle(options.title)
                            .setDescription(options.reason)
                            .setAllowedAuthenticators(
                                    BiometricManager.Authenticators.BIOMETRIC_STRONG)
                            .setNegativeButtonText(options.cancelButtonText == null
                                    ? DEFAULT_CANCEL_TEXT : options.cancelButtonText);
            if (options.subtitle != null) info.setSubtitle(options.subtitle);
            try {
                prompt.authenticate(info.build(), new BiometricPrompt.CryptoObject(signature));
            } catch (Throwable error) {
                completeSignature(callback, "unavailable",
                        messageOf(error, "Unable to show the biometric prompt"),
                        options.keyId, null);
            }
        });
    }

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
                return "noHardware";
            case BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE:
                return "unavailable";
            default:
                return "notSupported";
        }
    }

    private String supportJSON(String policy) throws JSONException {
        Context context = applicationContext();
        KeyguardManager keyguard =
                (KeyguardManager) context.getSystemService(Context.KEYGUARD_SERVICE);
        boolean deviceSecure = keyguard != null && keyguard.isDeviceSecure();
        int status = BiometricManager.from(context)
                .canAuthenticate(authenticatorsForPolicy(policy));
        JSONObject value = new JSONObject();
        value.put("policy", policy);
        value.put("canAuthenticate", status == BiometricManager.BIOMETRIC_SUCCESS);
        value.put("reason", reasonForManagerStatus(status, policy, deviceSecure));
        value.put("biometryType", "unknown");
        value.put("deviceCredentialSetup", deviceSecure);
        return envelope(value).toString();
    }

    private static int authenticatorsForPolicy(String policy) {
        switch (policy) {
            case POLICY_STRONG:
                return BiometricManager.Authenticators.BIOMETRIC_STRONG;
            case POLICY_DEVICE_OWNER:
                return BiometricManager.Authenticators.BIOMETRIC_WEAK
                        | BiometricManager.Authenticators.DEVICE_CREDENTIAL;
            case POLICY_WEAK:
            default:
                return BiometricManager.Authenticators.BIOMETRIC_WEAK;
        }
    }

    private static String reasonForManagerStatus(
            int status, String policy, boolean deviceSecure) {
        switch (status) {
            case BiometricManager.BIOMETRIC_SUCCESS:
                return "ok";
            case BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED:
                if (POLICY_DEVICE_OWNER.equals(policy) && !deviceSecure) {
                    return "noDeviceCredential";
                }
                return "notEnrolled";
            case BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE:
                return "noHardware";
            case BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE:
            case BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED:
                return "unavailable";
            default:
                return "unknown";
        }
    }

    private static String outcomeForErrorCode(int errorCode) {
        switch (errorCode) {
            case BiometricPrompt.ERROR_USER_CANCELED:
            case BiometricPrompt.ERROR_NEGATIVE_BUTTON:
                return "userCancel";
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
            case BiometricPrompt.ERROR_HW_NOT_PRESENT:
                return "noHardware";
            case BiometricPrompt.ERROR_HW_UNAVAILABLE:
                return "unavailable";
            case BiometricPrompt.ERROR_UNABLE_TO_PROCESS:
                return "failed";
            default:
                return "unknown";
        }
    }

    private void complete(Callback callback, String code, String message, String policy) {
        promptActive.set(false);
        callback.invoke(outcomeJSON(code, message, policy));
    }

    private void completeSignature(Callback callback, String code, String message,
            String keyId, @Nullable String signature) {
        promptActive.set(false);
        callback.invoke(signatureJSON(code, message, keyId, signature));
    }

    private static String outcomeJSON(String code, String message, String policy) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("message", message == null ? "" : message);
            value.put("policy", policy);
            return envelope(value).toString();
        } catch (JSONException error) {
            return "{\"error\":\"Unable to encode the biometric result\"}";
        }
    }

    private static String keyJSON(String code, String message,
            @Nullable String keyId, @Nullable String scope,
            @Nullable String publicKey, String securityLevel,
            String attestationType, @Nullable JSONArray certificates) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("message", message == null ? "" : message);
            if (keyId != null) value.put("keyId", keyId);
            if (scope != null) value.put("scope", scope);
            if (publicKey != null) value.put("publicKey", publicKey);
            value.put("securityLevel", securityLevel);
            value.put("attestationType", attestationType);
            value.put("attestationCertificates",
                    certificates == null ? new JSONArray() : certificates);
            return envelope(value).toString();
        } catch (JSONException error) {
            return "{\"error\":\"Unable to encode the biometric key result\"}";
        }
    }

    private static String deleteJSON(String code, String message, String keyId) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("message", message == null ? "" : message);
            value.put("keyId", keyId);
            return envelope(value).toString();
        } catch (JSONException error) {
            return "{\"error\":\"Unable to encode the biometric delete result\"}";
        }
    }

    private static String signatureJSON(String code, String message,
            String keyId, @Nullable String signature) {
        try {
            JSONObject value = new JSONObject();
            value.put("code", code);
            value.put("message", message == null ? "" : message);
            value.put("keyId", keyId);
            if (signature != null) value.put("signature", signature);
            return envelope(value).toString();
        } catch (JSONException error) {
            return "{\"error\":\"Unable to encode the biometric signature result\"}";
        }
    }

    private static JSONObject envelope(JSONObject value) throws JSONException {
        JSONObject result = new JSONObject();
        result.put("error", "");
        result.put("value", value);
        return result;
    }

    private static String errorJSON(String message) {
        try {
            JSONObject result = new JSONObject();
            result.put("error", message);
            return result.toString();
        } catch (JSONException error) {
            return "{\"error\":\"Unable to encode the biometric error\"}";
        }
    }

    private KeyStore loadedKeyStore() throws Exception {
        KeyStore keyStore = KeyStore.getInstance(ANDROID_KEYSTORE);
        keyStore.load(null);
        return keyStore;
    }

    private static KeyPair generateSigningKey(
            String alias, @Nullable byte[] attestationChallenge) throws Exception {
        KeyPairGenerator generator =
                KeyPairGenerator.getInstance("EC", ANDROID_KEYSTORE);
        KeyGenParameterSpec.Builder builder = new KeyGenParameterSpec.Builder(
                alias, KeyProperties.PURPOSE_SIGN | KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(new ECGenParameterSpec("secp256r1"))
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                    0, KeyProperties.AUTH_BIOMETRIC_STRONG);
        } else {
            builder.setUserAuthenticationValidityDurationSeconds(-1);
        }
        if (attestationChallenge != null) {
            builder.setAttestationChallenge(attestationChallenge);
        }
        generator.initialize(builder.build());
        return generator.generateKeyPair();
    }

    private static String securityLevel(PrivateKey privateKey) {
        try {
            KeyFactory factory = KeyFactory.getInstance(
                    privateKey.getAlgorithm(), ANDROID_KEYSTORE);
            KeyInfo info = factory.getKeySpec(privateKey, KeyInfo.class);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                int level = info.getSecurityLevel();
                if (level == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT
                        || level == KeyProperties.SECURITY_LEVEL_STRONGBOX) {
                    return "secureHardware";
                }
                if (level == KeyProperties.SECURITY_LEVEL_SOFTWARE) return "software";
                return "unknown";
            }
            // The legacy method is absent from the API 36 compile surface but
            // remains available on pre-31 devices where getSecurityLevel does
            // not exist.
            Method legacy = KeyInfo.class.getMethod("isInsideSecurityHardware");
            Object result = legacy.invoke(info);
            return Boolean.TRUE.equals(result) ? "secureHardware" : "software";
        } catch (Throwable ignored) {
            return "unknown";
        }
    }

    private static JSONArray certificateChain(
            KeyStore keyStore, String alias, boolean includeSingle) throws Exception {
        JSONArray encoded = new JSONArray();
        Certificate[] chain = keyStore.getCertificateChain(alias);
        if (chain == null || (!includeSingle && chain.length <= 1)) return encoded;
        for (Certificate certificate : chain) {
            encoded.put(Base64.encodeToString(certificate.getEncoded(), Base64.NO_WRAP));
        }
        return encoded;
    }

    private static boolean hasAndroidKeyAttestation(Certificate certificate) {
        return certificate instanceof X509Certificate
                && ((X509Certificate) certificate).getExtensionValue(
                        "1.3.6.1.4.1.11129.2.1.17") != null;
    }

    private void deleteAliasQuietly(String alias) {
        try {
            KeyStore keyStore = loadedKeyStore();
            if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias);
        } catch (Throwable ignored) {
            // Best-effort cleanup after a failed or invalidated key operation.
        }
    }

    private static String aliasForKeyId(String keyId) {
        return KEY_ALIAS_PREFIX + requireKeyId(keyId);
    }

    private static String scopeFromKeyId(String keyId) {
        String normalized = requireKeyId(keyId);
        return normalized.substring(0, normalized.lastIndexOf('~'));
    }

    private static String requireKeyId(String value) {
        String normalized = value == null ? "" : value.trim();
        if (!KEY_ID_PATTERN.matcher(normalized).matches()) {
            throw new IllegalArgumentException("Biometric keyId is invalid");
        }
        return normalized;
    }

    private static String requireScope(String value) {
        String normalized = value == null ? "" : value.trim();
        if (!SCOPE_PATTERN.matcher(normalized).matches()) {
            throw new IllegalArgumentException("Biometric key scope is invalid");
        }
        return normalized;
    }

    private static byte[] decodeCanonicalBase64(
            String value, String label, int minimum, int maximum) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty() || normalized.length() % 4 != 0
                || !BASE64_PATTERN.matcher(normalized).matches()) {
            throw new IllegalArgumentException(label + " must be canonical standard Base64");
        }
        byte[] decoded;
        try {
            decoded = Base64.decode(normalized, Base64.NO_WRAP);
        } catch (IllegalArgumentException error) {
            throw new IllegalArgumentException(label + " must be canonical standard Base64");
        }
        if (!Base64.encodeToString(decoded, Base64.NO_WRAP).equals(normalized)) {
            throw new IllegalArgumentException(label + " must be canonical standard Base64");
        }
        if (decoded.length < minimum || decoded.length > maximum) {
            throw new IllegalArgumentException(
                    label + " decoded length must be " + minimum + ".." + maximum);
        }
        return decoded;
    }

    private static void validateSigningPayload(byte[] payload, String keyId) {
        byte[] key = keyId.getBytes(StandardCharsets.US_ASCII);
        int headerLength = SIGNING_DOMAIN.length + key.length + 1;
        int minimumLength = headerLength + 32 + 16;
        int maximumLength = headerLength + 32 + 64;
        if (payload.length < minimumLength || payload.length > maximumLength) {
            throw new IllegalArgumentException("Biometric signing payload has invalid length");
        }
        for (int index = 0; index < SIGNING_DOMAIN.length; index++) {
            if (payload[index] != SIGNING_DOMAIN[index]) {
                throw new IllegalArgumentException("Biometric signing payload has invalid domain");
            }
        }
        for (int index = 0; index < key.length; index++) {
            if (payload[SIGNING_DOMAIN.length + index] != key[index]) {
                throw new IllegalArgumentException("Biometric signing payload has mismatched keyId");
            }
        }
        if (payload[headerLength - 1] != 0) {
            throw new IllegalArgumentException("Biometric signing payload has invalid key boundary");
        }
    }

    private static String parsePolicyOptions(String optionsJSON) throws JSONException {
        JSONObject json = new JSONObject(optionsJSON == null ? "{}" : optionsJSON);
        return requirePolicy(json.optString("policy", POLICY_WEAK));
    }

    private static String parseKeyIdOptions(String optionsJSON) throws JSONException {
        JSONObject json = new JSONObject(optionsJSON == null ? "{}" : optionsJSON);
        return requireKeyId(json.optString("keyId"));
    }

    private static String requirePolicy(String value) {
        if (POLICY_WEAK.equals(value) || POLICY_STRONG.equals(value)
                || POLICY_DEVICE_OWNER.equals(value)) {
            return value;
        }
        throw new IllegalArgumentException("Biometric authentication policy is invalid");
    }

    /** Uncompressed EC point: 0x04 || X(32) || Y(32). */
    private static byte[] rawPoint(ECPublicKey publicKey) {
        byte[] raw = new byte[65];
        raw[0] = 0x04;
        copyPadded(publicKey.getW().getAffineX().toByteArray(), raw, 1, 32);
        copyPadded(publicKey.getW().getAffineY().toByteArray(), raw, 33, 32);
        return raw;
    }

    private static void copyPadded(byte[] source, byte[] destination,
            int offset, int length) {
        int start = Math.max(0, source.length - length);
        int count = source.length - start;
        int pad = length - count;
        System.arraycopy(source, start, destination, offset + pad, count);
    }

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
        int length = der[index + 1] & 0xff;
        if (length == 0 || index + 2 + length > der.length) {
            throw new IllegalArgumentException("Malformed ECDSA signature");
        }
        return length;
    }

    private static byte[] stripSignByte(byte[] der, int offset, int length) {
        int start = offset;
        int count = length;
        while (count > 0 && der[start] == 0x00) {
            start++;
            count--;
        }
        if (count > 32) throw new IllegalArgumentException("Malformed ECDSA signature");
        byte[] value = new byte[count];
        System.arraycopy(der, start, value, 0, count);
        return value;
    }

    @Nullable
    private FragmentActivity resolveFragmentActivity() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        while (context instanceof ContextWrapper) {
            if (context instanceof FragmentActivity) return (FragmentActivity) context;
            context = ((ContextWrapper) context).getBaseContext();
        }
        return null;
    }

    private Context applicationContext() {
        Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
        if (context == null && mContext != null) context = mContext.getApplicationContext();
        if (context == null) throw new IllegalStateException("Biometric has no host context");
        return context;
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }

    private static String requireText(JSONObject json, String name, int maximum) {
        String value = json.optString(name, "").trim();
        if (value.isEmpty()) {
            throw new IllegalArgumentException("Biometric " + name + " must not be empty");
        }
        if (value.length() > maximum) {
            throw new IllegalArgumentException("Biometric " + name + " is too long");
        }
        return value;
    }

    @Nullable
    private static String optionalText(JSONObject json, String name, int maximum) {
        String value = json.optString(name, "").trim();
        if (value.isEmpty()) return null;
        if (value.length() > maximum) {
            throw new IllegalArgumentException("Biometric " + name + " is too long");
        }
        return value;
    }

    private static class PromptOptions {
        final String title;
        final String reason;
        @Nullable final String subtitle;
        @Nullable final String cancelButtonText;
        final String policy;

        PromptOptions(JSONObject json, boolean includePolicy) {
            title = requireText(json, "title", 200);
            reason = requireText(json, "reason", 500);
            subtitle = optionalText(json, "subtitle", 200);
            cancelButtonText = optionalText(json, "cancelButtonText", 60);
            policy = includePolicy
                    ? requirePolicy(json.optString("policy", POLICY_WEAK))
                    : POLICY_STRONG;
        }

        static PromptOptions parse(String optionsJSON, boolean includePolicy)
                throws JSONException {
            return new PromptOptions(
                    new JSONObject(optionsJSON == null ? "{}" : optionsJSON),
                    includePolicy);
        }
    }

    private static final class KeyCreateOptions {
        final String scope;
        @Nullable final byte[] attestationChallenge;

        KeyCreateOptions(String scope, @Nullable byte[] attestationChallenge) {
            this.scope = scope;
            this.attestationChallenge = attestationChallenge;
        }

        static KeyCreateOptions parse(String optionsJSON) throws JSONException {
            JSONObject json = new JSONObject(optionsJSON == null ? "{}" : optionsJSON);
            String scope = requireScope(json.optString("scope"));
            String encoded = json.optString("attestationChallenge", "").trim();
            byte[] challenge = encoded.isEmpty() ? null
                    : decodeCanonicalBase64(encoded,
                            "Biometric attestationChallenge", 16, 128);
            return new KeyCreateOptions(scope, challenge);
        }
    }

    private static final class SignOptions extends PromptOptions {
        final String keyId;
        final byte[] payload;

        SignOptions(JSONObject json) {
            super(json, false);
            keyId = requireKeyId(json.optString("keyId"));
            payload = decodeCanonicalBase64(json.optString("payload"),
                    "Biometric signing payload", 1, 256);
            validateSigningPayload(payload, keyId);
        }

        static SignOptions parse(String optionsJSON) throws JSONException {
            return new SignOptions(
                    new JSONObject(optionsJSON == null ? "{}" : optionsJSON));
        }
    }
}
