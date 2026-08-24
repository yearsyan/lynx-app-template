package com.lynxapp.autolink.appinstaller;

import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;

import androidx.annotation.Nullable;
import androidx.core.content.FileProvider;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.security.MessageDigest;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.regex.Pattern;

/**
 * Privileged, opt-in Android self-update hand-off exported as AppInstaller.
 *
 * The source is copied into a narrow private staging directory before any
 * permission UI is considered. The staged APK must match the caller-provided
 * SHA-256, this host's package name, an exact newer version code and a signer
 * accepted by the currently installed app. Only then is its FileProvider URI
 * handed to the system package installer.
 */
@LynxNativeModule(name = AppInstallerModule.NAME)
public final class AppInstallerModule extends LynxContextModule {
    public static final String NAME = "AppInstaller";

    private static final String APK_MIME_TYPE = "application/vnd.android.package-archive";
    private static final String AUTHORITY_SUFFIX = ".lynx.appinstaller.fileprovider";
    private static final String STAGING_PATH = "LynxFiles/updates";
    private static final long MAX_APK_BYTES = 1024L * 1024L * 1024L;
    private static final long STALE_APK_MILLIS = 24L * 60L * 60L * 1000L;
    private static final double MAX_SAFE_JS_INTEGER = 9_007_199_254_740_991D;
    private static final Pattern PACKAGE_NAME = Pattern.compile(
            "^[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)+$");
    private static final Pattern SHA_256 = Pattern.compile("^[0-9a-f]{64}$");

    private final Context applicationContext;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final AtomicBoolean launchInProgress = new AtomicBoolean(false);
    private volatile boolean destroyed = false;

    public AppInstallerModule(LynxContext context) {
        super(context);
        applicationContext = context.getApplicationContext();
    }

    @LynxMethod
    public void getCapabilities(Callback callback) {
        JavaOnlyMap value = new JavaOnlyMap();
        value.putBoolean("supported", true);
        value.putBoolean("permissionGranted", installPermissionGranted());
        callback.invoke(result(value, ""));
    }

    /** Opens the Android 8+ per-app unknown-sources settings page. */
    @LynxMethod
    public void openPermissionSettings(Callback callback) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            callback.invoke("");
            return;
        }
        mainHandler.post(() -> {
            if (destroyed) return;
            try {
                Intent intent = new Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:" + applicationContext.getPackageName()));
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                applicationContext.startActivity(intent);
                callback.invoke("");
            } catch (Throwable error) {
                callback.invoke(messageOf(error, "Unable to open install-permission settings"));
            }
        });
    }

    /** Validates and stages a self-update, then launches the system installer. */
    @LynxMethod
    public void launchInstall(ReadableMap options, Callback callback) {
        if (destroyed) {
            callback.invoke(result(null, "AppInstaller host has been destroyed"));
            return;
        }
        final InstallRequest request;
        try {
            request = InstallRequest.parse(options);
        } catch (Throwable error) {
            callback.invoke(result(null, messageOf(error, "Invalid install request")));
            return;
        }
        if (!launchInProgress.compareAndSet(false, true)) {
            callback.invoke(result(null, "An AppInstaller launch is already in progress"));
            return;
        }
        try {
            executor.execute(() -> prepareAndLaunch(request, callback));
        } catch (Throwable error) {
            launchInProgress.set(false);
            callback.invoke(result(null, messageOf(error, "Unable to schedule APK validation")));
        }
    }

    @Override
    public void destroy() {
        destroyed = true;
        executor.shutdownNow();
    }

    private void prepareAndLaunch(InstallRequest request, Callback callback) {
        File staged = null;
        try {
            if (destroyed) {
                launchInProgress.set(false);
                return;
            }
            cleanupStaleAPKs();
            StagedAPK candidate = stage(request);
            staged = candidate.file;
            validateArchive(candidate, request);
            if (!installPermissionGranted()) {
                throw new IllegalStateException(
                        "Install permission is not granted; call openPermissionSettings() first");
            }
            File ready = staged;
            if (!mainHandler.post(() -> launchSystemInstaller(ready, callback))) {
                throw new IllegalStateException("Unable to schedule the system installer launch");
            }
            staged = null;
        } catch (Throwable error) {
            if (staged != null) staged.delete();
            launchInProgress.set(false);
            if (!destroyed) {
                callback.invoke(result(null, messageOf(error, "Unable to prepare APK install")));
            }
        }
    }

    private void launchSystemInstaller(File apk, Callback callback) {
        try {
            if (destroyed) {
                apk.delete();
                return;
            }
            Uri uri = FileProvider.getUriForFile(
                    applicationContext,
                    applicationContext.getPackageName() + AUTHORITY_SUFFIX,
                    apk);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, APK_MIME_TYPE);
            intent.setClipData(ClipData.newRawUri("APK", uri));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            applicationContext.startActivity(intent);
        } catch (Throwable error) {
            apk.delete();
            launchInProgress.set(false);
            callback.invoke(result(null, messageOf(error, "Unable to start system installer")));
            return;
        }
        launchInProgress.set(false);
        JavaOnlyMap value = new JavaOnlyMap();
        value.putString("status", "launched");
        callback.invoke(result(value, ""));
    }

    private StagedAPK stage(InstallRequest request) throws Exception {
        File directory = stagingDirectory();
        File destination = File.createTempFile("candidate-", ".apk", directory);
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        long bytes = 0;
        try (InputStream input = openSource(request.uri);
             FileOutputStream output = new FileOutputStream(destination)) {
            byte[] buffer = new byte[64 * 1024];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                if (Thread.currentThread().isInterrupted() || destroyed) {
                    throw new IOException("AppInstaller host has been destroyed");
                }
                if (count == 0) continue;
                bytes += count;
                if (bytes > MAX_APK_BYTES) {
                    throw new IOException("APK exceeds the 1 GiB staging limit");
                }
                digest.update(buffer, 0, count);
                output.write(buffer, 0, count);
            }
            output.getFD().sync();
        } catch (Throwable error) {
            destination.delete();
            throw error;
        }
        if (bytes == 0) {
            destination.delete();
            throw new IOException("APK source is empty");
        }
        String sha256 = hex(digest.digest());
        if (!sha256.equals(request.expectedSha256)) {
            destination.delete();
            throw new SecurityException("APK SHA-256 does not match expectedSha256");
        }
        return new StagedAPK(destination);
    }

    private InputStream openSource(String source) throws IOException {
        Uri uri = Uri.parse(source);
        String scheme = uri.getScheme();
        if (scheme == null || scheme.isEmpty()) {
            File file = new File(source);
            if (!file.isAbsolute()) {
                throw new IllegalArgumentException("APK path must be absolute");
            }
            return readableFile(file);
        }
        if (ContentResolver.SCHEME_FILE.equalsIgnoreCase(scheme)) {
            String path = uri.getPath();
            if (path == null || path.isEmpty()) {
                throw new IllegalArgumentException("APK file URI has no path");
            }
            return readableFile(new File(path));
        }
        if (ContentResolver.SCHEME_CONTENT.equalsIgnoreCase(scheme)) {
            InputStream input = applicationContext.getContentResolver().openInputStream(uri);
            if (input == null) {
                throw new IOException("Unable to open APK content URI");
            }
            return input;
        }
        throw new IllegalArgumentException("APK URI must use file:// or content://");
    }

    private static FileInputStream readableFile(File file) throws IOException {
        if (!file.isFile() || !file.canRead()) {
            throw new IOException("APK file is missing or unreadable");
        }
        return new FileInputStream(file);
    }

    @SuppressWarnings("deprecation")
    private void validateArchive(StagedAPK candidate, InstallRequest request) throws Exception {
        PackageManager manager = applicationContext.getPackageManager();
        int flags = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? PackageManager.GET_SIGNING_CERTIFICATES
                : PackageManager.GET_SIGNATURES;
        PackageInfo archive = manager.getPackageArchiveInfo(candidate.file.getAbsolutePath(), flags);
        if (archive == null || archive.packageName == null) {
            throw new IllegalArgumentException("Source is not a readable APK archive");
        }
        String hostPackage = applicationContext.getPackageName();
        if (!request.expectedPackageName.equals(hostPackage)) {
            throw new SecurityException("expectedPackageName must match the installed app");
        }
        if (!archive.packageName.equals(request.expectedPackageName)) {
            throw new SecurityException("APK package name does not match expectedPackageName");
        }

        long archiveVersion = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? archive.getLongVersionCode()
                : archive.versionCode;
        if (archiveVersion != request.expectedVersionCode) {
            throw new SecurityException("APK version code does not match expectedVersionCode");
        }

        PackageInfo installed = manager.getPackageInfo(hostPackage, flags);
        long installedVersion = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
                ? installed.getLongVersionCode()
                : installed.versionCode;
        if (archiveVersion <= installedVersion) {
            throw new SecurityException("APK version code must be newer than the installed app");
        }
        if (!signerAccepted(installed, archive)) {
            throw new SecurityException("APK signing certificate does not match the installed app");
        }
    }

    @SuppressWarnings("deprecation")
    private static boolean signerAccepted(PackageInfo installed, PackageInfo archive)
            throws Exception {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return digestSet(installed.signatures).equals(digestSet(archive.signatures));
        }
        if (installed.signingInfo == null || archive.signingInfo == null) return false;
        Set<String> installedActive = digestSet(
                installed.signingInfo.getApkContentsSigners());
        Set<String> archiveActive = digestSet(
                archive.signingInfo.getApkContentsSigners());
        if (installedActive.isEmpty() || archiveActive.isEmpty()) return false;
        if (installedActive.equals(archiveActive)) return true;

        // A valid signing-key rotation embeds the installed active signer in
        // the new archive's proof-of-rotation history. A plain APK signed only
        // with an old key does not satisfy this check.
        Signature[] archiveHistory = archive.signingInfo.hasMultipleSigners()
                ? archive.signingInfo.getApkContentsSigners()
                : archive.signingInfo.getSigningCertificateHistory();
        return digestSet(archiveHistory).containsAll(installedActive);
    }

    private static Set<String> digestSet(@Nullable Signature[] signatures) throws Exception {
        Set<String> result = new HashSet<>();
        if (signatures == null) return result;
        for (Signature signature : signatures) {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            result.add(hex(digest.digest(signature.toByteArray())));
        }
        return result;
    }

    private boolean installPermissionGranted() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O
                || applicationContext.getPackageManager().canRequestPackageInstalls();
    }

    private File stagingDirectory() throws IOException {
        File directory = new File(applicationContext.getCacheDir(), STAGING_PATH);
        if (!directory.isDirectory() && !directory.mkdirs()) {
            throw new IOException("Unable to create the APK staging directory");
        }
        return directory;
    }

    private void cleanupStaleAPKs() {
        try {
            File[] files = stagingDirectory().listFiles();
            if (files == null) return;
            long cutoff = System.currentTimeMillis() - STALE_APK_MILLIS;
            for (File file : files) {
                if (file.isFile() && file.lastModified() < cutoff) file.delete();
            }
        } catch (Throwable ignored) {
            // Cleanup is best effort and must not block a new validated update.
        }
    }

    private static JavaOnlyMap result(@Nullable JavaOnlyMap value, String error) {
        JavaOnlyMap envelope = new JavaOnlyMap();
        if (value == null) envelope.putNull("value");
        else envelope.putMap("value", value);
        envelope.putString("error", error);
        return envelope;
    }

    private static String hex(byte[] value) {
        StringBuilder result = new StringBuilder(value.length * 2);
        for (byte item : value) result.append(String.format(Locale.ROOT, "%02x", item & 0xff));
        return result.toString();
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }

    private static final class InstallRequest {
        final String uri;
        final String expectedPackageName;
        final long expectedVersionCode;
        final String expectedSha256;

        InstallRequest(
                String uri,
                String expectedPackageName,
                long expectedVersionCode,
                String expectedSha256) {
            this.uri = uri;
            this.expectedPackageName = expectedPackageName;
            this.expectedVersionCode = expectedVersionCode;
            this.expectedSha256 = expectedSha256;
        }

        static InstallRequest parse(@Nullable ReadableMap options) {
            if (options == null) throw new IllegalArgumentException("Install options are required");
            String uri = string(options, "uri").trim();
            String packageName = string(options, "expectedPackageName").trim();
            String sha256 = string(options, "expectedSha256").trim().toLowerCase(Locale.ROOT);
            double rawVersion = options.getDouble("expectedVersionCode");
            if (uri.isEmpty() || uri.length() > 8192) {
                throw new IllegalArgumentException("Install uri must be a non-empty string");
            }
            if (packageName.length() > 255 || !PACKAGE_NAME.matcher(packageName).matches()) {
                throw new IllegalArgumentException("Invalid expectedPackageName");
            }
            if (!Double.isFinite(rawVersion)
                    || rawVersion < 1
                    || rawVersion > MAX_SAFE_JS_INTEGER
                    || rawVersion != Math.rint(rawVersion)) {
                throw new IllegalArgumentException("expectedVersionCode must be a positive safe integer");
            }
            if (!SHA_256.matcher(sha256).matches()) {
                throw new IllegalArgumentException("expectedSha256 must be 64 hexadecimal characters");
            }
            return new InstallRequest(uri, packageName, (long) rawVersion, sha256);
        }

        private static String string(ReadableMap options, String key) {
            String value = options.getString(key);
            return value == null ? "" : value;
        }
    }

    private static final class StagedAPK {
        final File file;

        StagedAPK(File file) {
            this.file = file;
        }
    }
}
