package com.lynxapp.autolink.downloadmanager;

import android.content.Context;
import android.net.Uri;
import android.util.AtomicFile;

import androidx.annotation.Nullable;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.ByteArrayOutputStream;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArraySet;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.locks.ReentrantLock;
import java.util.regex.Pattern;

import okhttp3.Call;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.ResponseBody;

/**
 * Process-wide download coordinator. It deliberately outlives an individual
 * LynxContext: a foreground service and a newly-created module can both attach
 * to the same tasks while the application process is alive.
 */
final class DownloadEngine {
    static final String EVENT_PROGRESS = "progress";
    static final String EVENT_STATE = "state";

    static final String STATE_QUEUED = "queued";
    static final String STATE_RUNNING = "running";
    static final String STATE_PAUSED = "paused";
    static final String STATE_COMPLETED = "completed";
    static final String STATE_FAILED = "failed";
    static final String STATE_CANCELLED = "cancelled";

    static final String MODE_IN_APP = "in-app";
    static final String MODE_ANDROID_FOREGROUND = "android-foreground-service";

    private static final long MAX_SAFE_JS_INTEGER = 9_007_199_254_740_991L;
    private static final int PERSISTENCE_VERSION = 1;
    private static final int MAX_METADATA_BYTES = 1024 * 1024;
    private static final int BUFFER_SIZE = 64 * 1024;
    private static final Pattern SAFE_ID = Pattern.compile("^[A-Za-z0-9._-]{1,128}$");
    private static final Pattern HEADER_NAME =
            Pattern.compile("^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    private static volatile DownloadEngine instance;

    interface Listener {
        void onDownloadEvent(String type, Snapshot snapshot);
    }

    static final class Options {
        final String id;
        final String url;
        final String fileName;
        final Map<String, String> headers;
        final int progressIntervalMs;
        final boolean persistProgress;
        final boolean foregroundService;
        final String notificationTitle;
        final String notificationText;

        Options(
                String id,
                String url,
                String fileName,
                Map<String, String> headers,
                int progressIntervalMs,
                boolean persistProgress,
                boolean foregroundService,
                String notificationTitle,
                String notificationText) {
            this.id = id;
            this.url = url;
            this.fileName = fileName;
            this.headers = Collections.unmodifiableMap(new LinkedHashMap<>(headers));
            this.progressIntervalMs = progressIntervalMs;
            this.persistProgress = persistProgress;
            this.foregroundService = foregroundService;
            this.notificationTitle = notificationTitle;
            this.notificationText = notificationText;
        }
    }

    static final class Snapshot {
        final String id;
        final String url;
        final String fileName;
        final String state;
        final String executionMode;
        final boolean persistProgress;
        final long bytesDownloaded;
        @Nullable final Long totalBytes;
        @Nullable final String fileUri;
        @Nullable final String error;
        final long createdAt;
        final long updatedAt;
        final String notificationTitle;
        final String notificationText;

        Snapshot(TaskRecord record) {
            id = record.options.id;
            url = record.options.url;
            fileName = record.options.fileName;
            state = record.state;
            executionMode = record.options.foregroundService
                    ? MODE_ANDROID_FOREGROUND
                    : MODE_IN_APP;
            persistProgress = record.options.persistProgress;
            bytesDownloaded = record.bytesDownloaded;
            totalBytes = record.totalBytes;
            fileUri = record.fileUri;
            error = record.error;
            createdAt = record.createdAt;
            updatedAt = record.updatedAt;
            notificationTitle = record.options.notificationTitle;
            notificationText = record.options.notificationText;
        }

        boolean usesForegroundService() {
            return MODE_ANDROID_FOREGROUND.equals(executionMode);
        }

        boolean isActive() {
            return STATE_QUEUED.equals(state) || STATE_RUNNING.equals(state);
        }

        JSONObject toJSON() throws JSONException {
            JSONObject value = new JSONObject();
            value.put("id", id);
            value.put("url", url);
            value.put("fileName", fileName);
            value.put("state", state);
            value.put("executionMode", executionMode);
            value.put("persistProgress", persistProgress);
            value.put("bytesDownloaded", bytesDownloaded);
            value.put("totalBytes", totalBytes == null ? JSONObject.NULL : totalBytes);
            value.put("fileUri", fileUri == null ? JSONObject.NULL : fileUri);
            value.put("error", error == null ? JSONObject.NULL : error);
            value.put("createdAt", createdAt);
            value.put("updatedAt", updatedAt);
            return value;
        }
    }

    private static final class TaskRecord {
        final Options options;
        final long createdAt;
        final ReentrantLock ioLock = new ReentrantLock();

        volatile String state = STATE_QUEUED;
        volatile long bytesDownloaded = 0L;
        @Nullable volatile Long totalBytes;
        @Nullable volatile String fileUri;
        @Nullable volatile String error;
        @Nullable volatile String rangeValidator;
        volatile long updatedAt;
        volatile long lastProgressEventAt = 0L;
        volatile int generation = 0;
        @Nullable volatile Call call;
        @Nullable volatile Future<?> future;

        TaskRecord(Options options) {
            this(options, System.currentTimeMillis());
        }

        TaskRecord(Options options, long createdAt) {
            this.options = options;
            this.createdAt = createdAt;
            this.updatedAt = createdAt;
        }
    }

    private final Context applicationContext;
    private final Map<String, TaskRecord> tasks = new ConcurrentHashMap<>();
    private final CopyOnWriteArraySet<Listener> listeners = new CopyOnWriteArraySet<>();
    private final ReentrantLock persistenceLock = new ReentrantLock();
    private final ExecutorService executor = Executors.newFixedThreadPool(3);
    private final OkHttpClient client = new OkHttpClient.Builder()
            .followRedirects(true)
            .followSslRedirects(true)
            .build();

    static DownloadEngine get(Context context) {
        DownloadEngine result = instance;
        if (result == null) {
            synchronized (DownloadEngine.class) {
                result = instance;
                if (result == null) {
                    result = new DownloadEngine(context.getApplicationContext());
                    instance = result;
                }
            }
        }
        return result;
    }

    private DownloadEngine(Context applicationContext) {
        this.applicationContext = applicationContext;
        loadPersistedTasks();
    }

    void addListener(Listener listener) {
        listeners.add(listener);
    }

    void removeListener(Listener listener) {
        listeners.remove(listener);
    }

    Snapshot enqueue(Options options) throws Exception {
        TaskRecord record = new TaskRecord(options);
        if (tasks.putIfAbsent(options.id, record) != null) {
            throw new IllegalArgumentException("Download task ID already exists");
        }
        try {
            persistTask(record);
        } catch (Exception error) {
            tasks.remove(options.id, record);
            throw error;
        }
        Snapshot queued = snapshot(record);
        notifyListeners(EVENT_STATE, queued);
        try {
            launch(record);
        } catch (Exception error) {
            tasks.remove(options.id, record);
            deletePersistedTaskQuietly(record);
            throw error;
        }
        return queued;
    }

    Snapshot pause(String id) throws Exception {
        TaskRecord record = requireTask(id);
        Call call;
        Future<?> future;
        Snapshot result;
        synchronized (record) {
            if (!STATE_QUEUED.equals(record.state) && !STATE_RUNNING.equals(record.state)) {
                throw new IllegalStateException("Download task is not running");
            }
            record.generation += 1;
            record.state = STATE_PAUSED;
            record.error = null;
            record.updatedAt = System.currentTimeMillis();
            call = record.call;
            future = record.future;
            result = new Snapshot(record);
        }
        if (call != null) call.cancel();
        if (future != null) future.cancel(true);
        persistTaskQuietly(record);
        notifyListeners(EVENT_STATE, result);
        return result;
    }

    Snapshot resume(String id) throws Exception {
        TaskRecord record = requireTask(id);
        Snapshot queued;
        synchronized (record) {
            if (!STATE_PAUSED.equals(record.state) && !STATE_FAILED.equals(record.state)) {
                throw new IllegalStateException("Only paused or failed downloads can resume");
            }
            record.state = STATE_QUEUED;
            record.error = null;
            record.fileUri = null;
            record.updatedAt = System.currentTimeMillis();
            queued = new Snapshot(record);
        }
        persistTaskQuietly(record);
        notifyListeners(EVENT_STATE, queued);
        try {
            launch(record);
        } catch (Exception failure) {
            fail(record, record.generation, messageOf(failure, "Unable to resume download"));
            throw failure;
        }
        return queued;
    }

    Snapshot cancel(String id) throws Exception {
        TaskRecord record = requireTask(id);
        Call call;
        Future<?> future;
        synchronized (record) {
            if (STATE_COMPLETED.equals(record.state)) {
                throw new IllegalStateException("Completed downloads cannot be cancelled");
            }
            if (STATE_CANCELLED.equals(record.state)) {
                return new Snapshot(record);
            }
            record.generation += 1;
            record.state = STATE_CANCELLED;
            record.error = null;
            record.fileUri = null;
            record.updatedAt = System.currentTimeMillis();
            call = record.call;
            future = record.future;
        }
        if (call != null) call.cancel();
        if (future != null) future.cancel(true);
        deletePartialAfterWorker(record);
        synchronized (record) {
            record.bytesDownloaded = 0L;
            Snapshot result = new Snapshot(record);
            persistTaskQuietly(record);
            notifyListeners(EVENT_STATE, result);
            return result;
        }
    }

    void remove(String id, boolean deleteFile) throws Exception {
        TaskRecord record = requireTask(id);
        Call call;
        Future<?> future;
        Snapshot cancelled = null;
        synchronized (record) {
            record.generation += 1;
            if (STATE_QUEUED.equals(record.state) || STATE_RUNNING.equals(record.state)) {
                record.state = STATE_CANCELLED;
                record.error = null;
                record.fileUri = null;
                record.updatedAt = System.currentTimeMillis();
                cancelled = new Snapshot(record);
            }
            call = record.call;
            future = record.future;
        }
        if (call != null) call.cancel();
        if (future != null) future.cancel(true);
        record.ioLock.lock();
        try {
            deleteIfExists(partialFile(record));
            if (deleteFile) deleteIfExists(destinationFile(record));
            deletePersistedTask(record);
            tasks.remove(id, record);
        } finally {
            record.ioLock.unlock();
        }
        if (cancelled != null) notifyListeners(EVENT_STATE, cancelled);
    }

    @Nullable Snapshot getTask(String id) {
        TaskRecord record = tasks.get(id);
        return record == null ? null : snapshot(record);
    }

    List<Snapshot> listTasks() {
        List<Snapshot> values = new ArrayList<>();
        for (TaskRecord record : tasks.values()) values.add(snapshot(record));
        values.sort(Comparator.comparingLong(value -> value.createdAt));
        return values;
    }

    boolean hasActiveForegroundTasks() {
        for (Snapshot value : listTasks()) {
            if (value.usesForegroundService() && value.isActive()) return true;
        }
        return false;
    }

    @Nullable Snapshot newestActiveForegroundTask() {
        Snapshot newest = null;
        for (Snapshot value : listTasks()) {
            if (!value.usesForegroundService() || !value.isActive()) continue;
            if (newest == null || value.updatedAt > newest.updatedAt) newest = value;
        }
        return newest;
    }

    void startFromForegroundService(String id) throws Exception {
        TaskRecord record = requireTask(id);
        if (!record.options.foregroundService) {
            throw new IllegalStateException("Download did not request foreground execution");
        }
        schedule(record);
    }

    void failToLaunch(String id, Throwable failure) {
        TaskRecord record = tasks.get(id);
        if (record == null) return;
        fail(record, record.generation, messageOf(failure, "Unable to start download"));
    }

    void pauseForegroundTasks(String message) {
        for (Snapshot value : listTasks()) {
            if (!value.usesForegroundService() || !value.isActive()) continue;
            try {
                Snapshot paused = pause(value.id);
                TaskRecord record = tasks.get(value.id);
                if (record != null) {
                    synchronized (record) {
                        record.error = message;
                        record.updatedAt = System.currentTimeMillis();
                        paused = new Snapshot(record);
                    }
                    persistTaskQuietly(record);
                    notifyListeners(EVENT_STATE, paused);
                }
            } catch (Throwable ignored) {
                // Best effort when Android times out a foreground dataSync service.
            }
        }
    }

    JSONArray snapshotsJSON() throws JSONException {
        JSONArray array = new JSONArray();
        for (Snapshot value : listTasks()) array.put(value.toJSON());
        return array;
    }

    private void launch(TaskRecord record) throws Exception {
        if (record.options.foregroundService) {
            DownloadForegroundService.begin(applicationContext, record.options.id);
        } else {
            schedule(record);
        }
    }

    private void schedule(TaskRecord record) {
        final int generation;
        synchronized (record) {
            if (!STATE_QUEUED.equals(record.state)) return;
            generation = ++record.generation;
            record.future = executor.submit(() -> run(record, generation));
        }
    }

    private void run(TaskRecord record, int generation) {
        record.ioLock.lock();
        try {
            if (!transitionToRunning(record, generation)) return;
            download(record, generation);
        } catch (Throwable failure) {
            if (isCurrentAndRunning(record, generation)) {
                fail(record, generation, messageOf(failure, "Download failed"));
            }
        } finally {
            synchronized (record) {
                if (record.generation == generation) {
                    record.call = null;
                    record.future = null;
                }
            }
            record.ioLock.unlock();
        }
    }

    private boolean transitionToRunning(TaskRecord record, int generation) {
        Snapshot running;
        synchronized (record) {
            if (record.generation != generation || !STATE_QUEUED.equals(record.state)) {
                return false;
            }
            record.state = STATE_RUNNING;
            record.error = null;
            record.updatedAt = System.currentTimeMillis();
            running = new Snapshot(record);
        }
        persistTaskQuietly(record);
        notifyListeners(EVENT_STATE, running);
        return true;
    }

    private void download(TaskRecord record, int generation) throws Exception {
        File partial = partialFile(record);
        File destination = destinationFile(record);
        ensureDirectory(partial.getParentFile());
        long offset = partial.isFile() ? partial.length() : 0L;
        if (offset > MAX_SAFE_JS_INTEGER) {
            deleteIfExists(partial);
            offset = 0L;
        }
        String validator = record.rangeValidator;
        if (offset > 0L && validator == null) offset = 0L;

        Request.Builder request = new Request.Builder()
                .url(record.options.url)
                .header("Accept-Encoding", "identity")
                .get();
        for (Map.Entry<String, String> header : record.options.headers.entrySet()) {
            request.addHeader(header.getKey(), header.getValue());
        }
        if (offset > 0L) {
            request.header("Range", "bytes=" + offset + "-");
            request.header("If-Range", validator);
        }

        Call call = client.newCall(request.build());
        synchronized (record) {
            if (record.generation != generation || !STATE_RUNNING.equals(record.state)) return;
            record.call = call;
        }

        try (Response response = call.execute()) {
            int status = response.code();
            if (status == 416 && offset > 0L) {
                Long rangeTotal = unsatisfiedRangeTotal(response.header("Content-Range"));
                if (rangeTotal != null && rangeTotal == offset) {
                    complete(record, generation, partial, destination, offset);
                    return;
                }
            }
            if (!response.isSuccessful()) {
                throw new IOException("HTTP " + status + " " + response.message());
            }

            if (status == 206) {
                Long rangeStart = contentRangeStart(response.header("Content-Range"));
                if (rangeStart == null || rangeStart != offset) {
                    throw new IOException("Server returned an invalid Content-Range");
                }
            }
            boolean append = offset > 0L && status == 206;
            if (!append) offset = 0L;
            if (!append) record.rangeValidator = responseValidator(response);
            ResponseBody body = response.body();
            if (body == null) throw new IOException("Download response had no body");
            Long total = totalBytes(response, body, offset, append);
            updateProgress(record, generation, offset, total, true);

            try (InputStream input = body.byteStream();
                 OutputStream output = new FileOutputStream(partial, append)) {
                byte[] buffer = new byte[BUFFER_SIZE];
                long downloaded = offset;
                while (true) {
                    if (!isCurrentAndRunning(record, generation)) return;
                    int count = input.read(buffer);
                    if (count < 0) break;
                    if (count == 0) continue;
                    if (count > MAX_SAFE_JS_INTEGER - downloaded) {
                        throw new IOException("Download exceeds the JavaScript safe integer limit");
                    }
                    if (total != null && count > total - downloaded) {
                        throw new IOException("Downloaded byte count exceeded Content-Length");
                    }
                    output.write(buffer, 0, count);
                    downloaded += count;
                    updateProgress(record, generation, downloaded, total, false);
                }
                output.flush();
            }

            if (!isCurrentAndRunning(record, generation)) return;
            long downloaded = partial.length();
            if (total != null && downloaded != total) {
                throw new IOException("Downloaded byte count did not match Content-Length");
            }
            complete(record, generation, partial, destination, downloaded);
        }
    }

    @Nullable
    private Long totalBytes(Response response, ResponseBody body, long offset, boolean append)
            throws IOException {
        Long fromRange = contentRangeTotal(response.header("Content-Range"));
        long value;
        if (fromRange != null) {
            value = fromRange;
        } else {
            long contentLength = body.contentLength();
            if (contentLength < 0L) return null;
            value = append ? offset + contentLength : contentLength;
        }
        if (value < 0L || value > MAX_SAFE_JS_INTEGER) {
            throw new IOException("Invalid or unsupported Content-Length");
        }
        return value;
    }

    @Nullable
    private static Long contentRangeTotal(@Nullable String value) {
        if (value == null) return null;
        int slash = value.lastIndexOf('/');
        if (slash < 0 || slash == value.length() - 1) return null;
        String total = value.substring(slash + 1).trim();
        if ("*".equals(total)) return null;
        try {
            return Long.parseLong(total);
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    @Nullable
    private static Long contentRangeStart(@Nullable String value) {
        if (value == null) return null;
        String normalized = value.trim();
        if (!normalized.startsWith("bytes ")) return null;
        int dash = normalized.indexOf('-', 6);
        int slash = normalized.lastIndexOf('/');
        if (dash < 0 || slash < dash) return null;
        try {
            return Long.parseLong(normalized.substring(6, dash).trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    @Nullable
    private static String responseValidator(Response response) {
        String etag = response.header("ETag");
        if (etag != null) {
            etag = etag.trim();
            if (!etag.isEmpty() && !etag.startsWith("W/")) return etag;
        }
        String lastModified = response.header("Last-Modified");
        if (lastModified == null || lastModified.trim().isEmpty()) return null;
        return lastModified.trim();
    }

    @Nullable
    private static Long unsatisfiedRangeTotal(@Nullable String value) {
        if (value == null || !value.trim().startsWith("bytes */")) return null;
        return contentRangeTotal(value);
    }

    private void updateProgress(
            TaskRecord record,
            int generation,
            long downloaded,
            @Nullable Long total,
            boolean force) {
        Snapshot progress = null;
        synchronized (record) {
            if (record.generation != generation || !STATE_RUNNING.equals(record.state)) return;
            record.bytesDownloaded = downloaded;
            record.totalBytes = total;
            record.updatedAt = System.currentTimeMillis();
            long now = record.updatedAt;
            if (force || now - record.lastProgressEventAt >= record.options.progressIntervalMs) {
                record.lastProgressEventAt = now;
                progress = new Snapshot(record);
            }
        }
        if (progress != null) {
            persistTaskQuietly(record);
            notifyListeners(EVENT_PROGRESS, progress);
        }
    }

    private void complete(
            TaskRecord record,
            int generation,
            File partial,
            File destination,
            long downloaded) throws Exception {
        if (!isCurrentAndRunning(record, generation)) return;
        deleteIfExists(destination);
        moveFile(partial, destination);
        Snapshot completed;
        synchronized (record) {
            if (record.generation != generation || !STATE_RUNNING.equals(record.state)) {
                deleteIfExists(destination);
                return;
            }
            record.bytesDownloaded = downloaded;
            if (record.totalBytes == null) record.totalBytes = downloaded;
            record.fileUri = Uri.fromFile(destination).toString();
            record.state = STATE_COMPLETED;
            record.error = null;
            record.updatedAt = System.currentTimeMillis();
            completed = new Snapshot(record);
        }
        persistTaskQuietly(record);
        notifyListeners(EVENT_STATE, completed);
    }

    private void fail(TaskRecord record, int generation, String message) {
        Snapshot failed;
        synchronized (record) {
            if (record.generation != generation
                    || STATE_PAUSED.equals(record.state)
                    || STATE_CANCELLED.equals(record.state)
                    || STATE_COMPLETED.equals(record.state)) {
                return;
            }
            record.state = STATE_FAILED;
            record.error = message;
            record.updatedAt = System.currentTimeMillis();
            failed = new Snapshot(record);
        }
        persistTaskQuietly(record);
        notifyListeners(EVENT_STATE, failed);
    }

    private boolean isCurrentAndRunning(TaskRecord record, int generation) {
        return record.generation == generation && STATE_RUNNING.equals(record.state);
    }

    private Snapshot snapshot(TaskRecord record) {
        synchronized (record) {
            return new Snapshot(record);
        }
    }

    private TaskRecord requireTask(String id) {
        TaskRecord record = tasks.get(id);
        if (record == null) throw new IllegalArgumentException("Unknown download task ID");
        return record;
    }

    private void notifyListeners(String type, Snapshot snapshot) {
        for (Listener listener : listeners) {
            try {
                listener.onDownloadEvent(type, snapshot);
            } catch (Throwable ignored) {
                // A stale Lynx context or notification must not stop the transfer.
            }
        }
    }

    private void loadPersistedTasks() {
        File directory = taskMetadataDirectory();
        File[] files = directory.listFiles((parent, name) -> name.endsWith(".json"));
        if (files == null) return;
        for (File file : files) {
            try {
                JSONObject value = new JSONObject(readMetadata(file));
                TaskRecord record = restoreTask(value);
                if (!file.getName().equals(record.options.id + ".json")) {
                    throw new IOException("Persisted task file name does not match its ID");
                }
                if (tasks.putIfAbsent(record.options.id, record) == null) {
                    persistTaskQuietly(record);
                }
            } catch (Throwable ignored) {
                file.delete();
            }
        }
    }

    private TaskRecord restoreTask(JSONObject value) throws Exception {
        if (value.getInt("version") != PERSISTENCE_VERSION
                || !value.getBoolean("persistProgress")) {
            throw new IOException("Unsupported persisted download task");
        }
        String id = value.getString("id");
        String url = value.getString("url");
        String fileName = value.getString("fileName");
        int interval = value.getInt("progressIntervalMs");
        boolean foreground = value.getBoolean("androidForegroundService");
        String notificationTitle = value.getString("notificationTitle");
        String notificationText = value.getString("notificationText");
        if (!SAFE_ID.matcher(id).matches() || !isSafeFileName(fileName)
                || !isSafeURL(url) || interval < 100 || interval > 10_000
                || notificationTitle.isEmpty() || notificationTitle.length() > 80
                || notificationText.isEmpty() || notificationText.length() > 160) {
            throw new IOException("Invalid persisted download task");
        }

        JSONObject headerValues = value.getJSONObject("headers");
        if (headerValues.length() > 64) throw new IOException("Too many persisted headers");
        Map<String, String> headers = new LinkedHashMap<>();
        java.util.Iterator<String> headerNames = headerValues.keys();
        while (headerNames.hasNext()) {
            String name = headerNames.next();
            String headerValue = headerValues.getString(name);
            String lower = name.toLowerCase(java.util.Locale.ROOT);
            if (!HEADER_NAME.matcher(name).matches() || isReservedHeader(lower)
                    || headerValue.length() > 8192
                    || headerValue.indexOf('\r') >= 0 || headerValue.indexOf('\n') >= 0) {
                throw new IOException("Invalid persisted download header");
            }
            headers.put(name, headerValue);
        }

        long createdAt = safePersistedLong(value, "createdAt");
        long updatedAt = safePersistedLong(value, "updatedAt");
        long bytesDownloaded = safePersistedLong(value, "bytesDownloaded");
        Long totalBytes = value.isNull("totalBytes")
                ? null
                : safePersistedLong(value, "totalBytes");
        String state = value.getString("state");
        if (!isKnownState(state)) throw new IOException("Invalid persisted task state");

        Options options = new Options(
                id,
                url,
                fileName,
                headers,
                interval,
                true,
                foreground,
                notificationTitle,
                notificationText);
        TaskRecord record = new TaskRecord(options, createdAt);
        record.state = state;
        record.bytesDownloaded = bytesDownloaded;
        record.totalBytes = totalBytes;
        record.updatedAt = Math.max(createdAt, updatedAt);
        if (!value.isNull("rangeValidator")) {
            String validator = value.getString("rangeValidator");
            if (validator.isEmpty() || validator.length() > 8192
                    || validator.indexOf('\r') >= 0 || validator.indexOf('\n') >= 0) {
                throw new IOException("Invalid persisted range validator");
            }
            record.rangeValidator = validator;
        }
        if (!value.isNull("error")) {
            String error = value.getString("error");
            record.error = error.length() > 4096 ? error.substring(0, 4096) : error;
        }

        File partial = partialFile(record);
        File destination = destinationFile(record);
        if (STATE_COMPLETED.equals(record.state)) {
            if (destination.isFile()) {
                long length = safeFileLength(destination);
                record.bytesDownloaded = length;
                record.totalBytes = length;
                record.fileUri = Uri.fromFile(destination).toString();
                record.error = null;
            } else {
                record.state = STATE_FAILED;
                record.bytesDownloaded = partial.isFile() ? safeFileLength(partial) : 0L;
                record.totalBytes = null;
                record.fileUri = null;
                record.error = "Downloaded file is missing";
                record.updatedAt = System.currentTimeMillis();
            }
        } else if (STATE_CANCELLED.equals(record.state)) {
            deleteIfExists(partial);
            record.bytesDownloaded = 0L;
            record.fileUri = null;
        } else {
            record.bytesDownloaded = partial.isFile() ? safeFileLength(partial) : 0L;
            record.fileUri = null;
            if (STATE_QUEUED.equals(record.state) || STATE_RUNNING.equals(record.state)) {
                record.state = STATE_PAUSED;
                record.error = null;
                record.updatedAt = System.currentTimeMillis();
            }
        }
        if (record.totalBytes != null && record.totalBytes < record.bytesDownloaded) {
            record.totalBytes = null;
        }
        return record;
    }

    private void persistTask(TaskRecord record) throws Exception {
        if (!record.options.persistProgress) return;
        String encoded = persistedTaskJSON(record).toString();
        persistenceLock.lock();
        try {
            File destination = taskMetadataFile(record.options.id);
            ensureDirectory(destination.getParentFile());
            AtomicFile atomicFile = new AtomicFile(destination);
            FileOutputStream output = null;
            try {
                output = atomicFile.startWrite();
                output.write(encoded.getBytes(StandardCharsets.UTF_8));
                output.flush();
                output.getFD().sync();
                atomicFile.finishWrite(output);
                output = null;
            } catch (Throwable failure) {
                if (output != null) atomicFile.failWrite(output);
                if (failure instanceof Exception) throw (Exception) failure;
                throw new IOException("Unable to persist download task", failure);
            }
        } finally {
            persistenceLock.unlock();
        }
    }

    private void persistTaskQuietly(TaskRecord record) {
        try {
            persistTask(record);
        } catch (Throwable ignored) {
            // The active transfer remains usable; a later state/progress write retries.
        }
    }

    private JSONObject persistedTaskJSON(TaskRecord record) throws JSONException {
        synchronized (record) {
            JSONObject value = new JSONObject();
            value.put("version", PERSISTENCE_VERSION);
            value.put("id", record.options.id);
            value.put("url", record.options.url);
            value.put("fileName", record.options.fileName);
            value.put("headers", new JSONObject(record.options.headers));
            value.put("progressIntervalMs", record.options.progressIntervalMs);
            value.put("persistProgress", true);
            value.put("androidForegroundService", record.options.foregroundService);
            value.put("notificationTitle", record.options.notificationTitle);
            value.put("notificationText", record.options.notificationText);
            value.put("state", record.state);
            value.put("bytesDownloaded", record.bytesDownloaded);
            value.put("totalBytes", record.totalBytes == null ? JSONObject.NULL : record.totalBytes);
            value.put("error", record.error == null ? JSONObject.NULL : record.error);
            value.put("rangeValidator",
                    record.rangeValidator == null ? JSONObject.NULL : record.rangeValidator);
            value.put("createdAt", record.createdAt);
            value.put("updatedAt", record.updatedAt);
            return value;
        }
    }

    private void deletePersistedTask(TaskRecord record) throws IOException {
        if (!record.options.persistProgress) return;
        persistenceLock.lock();
        try {
            deleteIfExists(taskMetadataFile(record.options.id));
        } finally {
            persistenceLock.unlock();
        }
    }

    private void deletePersistedTaskQuietly(TaskRecord record) {
        try {
            deletePersistedTask(record);
        } catch (Throwable ignored) {
            // Enqueue already failed; leave no in-memory task behind.
        }
    }

    private String readMetadata(File file) throws IOException {
        AtomicFile atomicFile = new AtomicFile(file);
        try (InputStream input = atomicFile.openRead();
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                if (count > 0) output.write(buffer, 0, count);
                if (output.size() > MAX_METADATA_BYTES) {
                    throw new IOException("Persisted download metadata is too large");
                }
            }
            if (output.size() == 0) {
                throw new IOException("Persisted download metadata is empty");
            }
            return output.toString(StandardCharsets.UTF_8.name());
        }
    }

    private File taskMetadataDirectory() {
        return new File(new File(applicationContext.getFilesDir(), "LynxFiles"),
                "download-manager/tasks");
    }

    private File taskMetadataFile(String id) {
        return new File(taskMetadataDirectory(), id + ".json");
    }

    private static long safePersistedLong(JSONObject value, String name) throws Exception {
        long result = value.getLong(name);
        if (result < 0L || result > MAX_SAFE_JS_INTEGER) {
            throw new IOException("Invalid persisted " + name);
        }
        return result;
    }

    private static long safeFileLength(File file) throws IOException {
        long length = file.length();
        if (length < 0L || length > MAX_SAFE_JS_INTEGER) {
            throw new IOException("Persisted download file is too large");
        }
        return length;
    }

    private static boolean isKnownState(String state) {
        return STATE_QUEUED.equals(state) || STATE_RUNNING.equals(state)
                || STATE_PAUSED.equals(state) || STATE_COMPLETED.equals(state)
                || STATE_FAILED.equals(state) || STATE_CANCELLED.equals(state);
    }

    private static boolean isSafeURL(String value) {
        if (value == null || value.length() > 8192 || value.indexOf(' ') >= 0) return false;
        String lower = value.toLowerCase(java.util.Locale.ROOT);
        return lower.startsWith("https://") || lower.startsWith("http://");
    }

    private static boolean isReservedHeader(String lower) {
        return lower.equals("accept-encoding") || lower.equals("connection")
                || lower.equals("content-length") || lower.equals("host")
                || lower.equals("if-range") || lower.equals("range")
                || lower.equals("transfer-encoding");
    }

    private static boolean isSafeFileName(String value) {
        if (value == null || value.isEmpty() || value.length() > 128
                || ".".equals(value) || "..".equals(value)
                || !value.equals(value.trim())
                || value.indexOf('/') >= 0 || value.indexOf('\\') >= 0) {
            return false;
        }
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            if (character < 0x20 || character == 0x7f) return false;
        }
        return true;
    }

    private File downloadsDirectory() {
        return new File(new File(applicationContext.getCacheDir(), "LynxFiles"), "downloads");
    }

    private File destinationFile(TaskRecord record) {
        return new File(downloadsDirectory(), record.options.id + "-" + record.options.fileName);
    }

    private File partialFile(TaskRecord record) {
        return new File(destinationFile(record).getPath() + ".part");
    }

    private void deletePartialAfterWorker(TaskRecord record) throws IOException {
        record.ioLock.lock();
        try {
            deleteIfExists(partialFile(record));
        } finally {
            record.ioLock.unlock();
        }
    }

    private static void ensureDirectory(@Nullable File directory) throws IOException {
        if (directory == null || (directory.isDirectory() || directory.mkdirs())) return;
        throw new IOException("Unable to create the download directory");
    }

    private static void deleteIfExists(File file) throws IOException {
        if (file.exists() && !file.delete()) {
            throw new IOException("Unable to delete " + file.getName());
        }
    }

    private static void moveFile(File source, File destination) throws IOException {
        if (source.renameTo(destination)) return;
        boolean copied = false;
        try (InputStream input = new FileInputStream(source);
             OutputStream output = new FileOutputStream(destination)) {
            byte[] buffer = new byte[BUFFER_SIZE];
            int count;
            while ((count = input.read(buffer)) >= 0) {
                if (count > 0) output.write(buffer, 0, count);
            }
            output.flush();
            copied = true;
        } finally {
            if (!copied) destination.delete();
        }
        if (!source.delete()) {
            destination.delete();
            throw new IOException("Unable to finalize the downloaded file");
        }
    }

    private static String messageOf(Throwable error, String fallback) {
        String message = error.getMessage();
        return message == null || message.trim().isEmpty() ? fallback : message;
    }
}
