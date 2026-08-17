package com.lynxapp.autolink.securestorage;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import androidx.annotation.Nullable;

import com.lynx.react.bridge.Callback;
import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.tasm.behavior.LynxContext;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.SecureRandom;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/**
 * Small-secret string storage. Values are sealed with an AES-256-GCM key
 * that lives in AndroidKeyStore and never leaves it; only the random IV and
 * the ciphertext are persisted, in the app's private preferences.
 */
@LynxNativeModule(name = SecureStorageModule.NAME)
public final class SecureStorageModule extends LynxContextModule {
    public static final String NAME = "SecureStorage";

    private static final String ANDROID_KEYSTORE = "AndroidKeyStore";
    private static final String KEY_ALIAS = "lynx.secure.storage.key";
    private static final String PREFS_NAME = "lynx.secure.storage";
    private static final int GCM_IV_BYTES = 12;
    private static final int GCM_TAG_BITS = 128;
    /** Keeps the store to small secrets; mirrored by the shared TS facade. */
    private static final int MAX_VALUE_CHARS = 64 * 1024;

    /** Keystore generation and cipher work runs off the Lynx thread. */
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    public SecureStorageModule(LynxContext context) {
        super(context);
    }

    @Override
    public void destroy() {
        executor.shutdownNow();
    }

    @LynxMethod
    public void setString(String key, String value, Callback callback) {
        if (!isValidKey(key)) {
            callback.invoke("Secure storage key must not be empty");
            return;
        }
        if (value == null || value.length() > MAX_VALUE_CHARS) {
            callback.invoke("Secure storage value is missing or too large");
            return;
        }
        final String entryKey = key;
        final byte[] plain = value.getBytes(StandardCharsets.UTF_8);
        executor.execute(() -> {
            try {
                byte[] iv = new byte[GCM_IV_BYTES];
                new SecureRandom().nextBytes(iv);
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.ENCRYPT_MODE, aesKey(),
                        new GCMParameterSpec(GCM_TAG_BITS, iv));
                byte[] sealed = cipher.doFinal(plain);
                byte[] blob = new byte[iv.length + sealed.length];
                System.arraycopy(iv, 0, blob, 0, iv.length);
                System.arraycopy(sealed, 0, blob, iv.length, sealed.length);
                boolean persisted = prefs().edit()
                        .putString(entryKey, Base64.encodeToString(blob, Base64.NO_WRAP))
                        .commit();
                callback.invoke(persisted ? "" : "Unable to persist the secure value");
            } catch (Throwable error) {
                callback.invoke(messageOf(error, "Unable to write the secure value"));
            }
        });
    }

    @LynxMethod
    public void getString(String key, @Nullable String defaultValue, Callback callback) {
        if (!isValidKey(key)) {
            callback.invoke(defaultValue);
            return;
        }
        final String entryKey = key;
        final String fallback = defaultValue;
        executor.execute(() -> {
            String encoded = prefs().getString(entryKey, null);
            if (encoded == null) {
                callback.invoke(fallback);
                return;
            }
            try {
                byte[] blob = Base64.decode(encoded, Base64.NO_WRAP);
                if (blob.length <= GCM_IV_BYTES) {
                    throw new IllegalStateException("Malformed secure entry");
                }
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.DECRYPT_MODE, aesKey(),
                        new GCMParameterSpec(GCM_TAG_BITS, blob, 0, GCM_IV_BYTES));
                byte[] plain = cipher.doFinal(blob, GCM_IV_BYTES, blob.length - GCM_IV_BYTES);
                callback.invoke(new String(plain, StandardCharsets.UTF_8));
            } catch (Throwable error) {
                // GCM verification fails when the entry was tampered with or
                // the Keystore key was wiped; both behave like missing data.
                callback.invoke(fallback);
            }
        });
    }

    @LynxMethod
    public void remove(String key, Callback callback) {
        if (!isValidKey(key)) {
            callback.invoke("Secure storage key must not be empty");
            return;
        }
        final String entryKey = key;
        executor.execute(() -> {
            boolean persisted = prefs().edit().remove(entryKey).commit();
            callback.invoke(persisted ? "" : "Unable to remove the secure value");
        });
    }

    /** Loads the storage key from AndroidKeyStore, generating it on first use. */
    private SecretKey aesKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance(ANDROID_KEYSTORE);
        keyStore.load(null);
        KeyStore.Entry entry = keyStore.getEntry(KEY_ALIAS, null);
        if (entry instanceof KeyStore.SecretKeyEntry) {
            return ((KeyStore.SecretKeyEntry) entry).getSecretKey();
        }
        KeyGenerator generator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE);
        generator.init(
                new KeyGenParameterSpec.Builder(
                        KEY_ALIAS,
                        KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                        .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                        .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                        .setKeySize(256)
                        .build());
        return generator.generateKey();
    }

    private SharedPreferences prefs() {
        Context context = mLynxContext != null ? mLynxContext : mContext;
        if (context == null) {
            throw new IllegalStateException("SecureStorage has no host context");
        }
        return context.getApplicationContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    private static boolean isValidKey(String key) {
        return key != null && !key.trim().isEmpty();
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
