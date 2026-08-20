package com.lynxapp.autolink.audioplayer;

import android.content.Context;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.annotation.Nullable;

import com.lynx.jsbridge.LynxContextModule;
import com.lynx.jsbridge.LynxMethod;
import com.lynx.jsbridge.LynxNativeModule;
import com.lynx.react.bridge.Callback;
import com.lynx.react.bridge.JavaOnlyArray;
import com.lynx.react.bridge.JavaOnlyMap;
import com.lynx.react.bridge.ReadableMap;
import com.lynx.tasm.behavior.LynxContext;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.FileNotFoundException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Pattern;

/**
 * Local-file audio playback backed by MediaPlayer. Every player operation is
 * serialized onto the main looper (MediaPlayer needs one) and events flow
 * back to JS as `audioPlayer` global events. Audio focus is managed per
 * player according to its usage; ambient players never take focus.
 */
@LynxNativeModule(name = AudioPlayerModule.NAME)
public final class AudioPlayerModule extends LynxContextModule {
    public static final String NAME = "AudioPlayer";
    public static final String EVENT_NAME = "audioPlayer";

    private static final Pattern PLAYER_ID = Pattern.compile("^[A-Za-z0-9._-]{1,128}$");
    private static final int DEFAULT_PROGRESS_INTERVAL_MS = 250;
    private static final float DUCK_FACTOR = 0.2f;

    private static final String STATE_LOADING = "loading";
    private static final String STATE_PAUSED = "paused";
    private static final String STATE_PLAYING = "playing";
    private static final String STATE_STOPPED = "stopped";

    private static final String USAGE_MEDIA = "media";
    private static final String USAGE_AMBIENT = "ambient";
    private static final String USAGE_ALARM = "alarm";
    private static final String USAGE_NOTIFICATION = "notification";

    private final Map<String, PlayerHandle> players = new ConcurrentHashMap<>();
    private final AudioManager audioManager;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private volatile boolean destroyed = false;

    public AudioPlayerModule(LynxContext context) {
        super(context);
        Context appContext = context != null ? context.getApplicationContext() : null;
        this.audioManager = appContext != null
                ? (AudioManager) appContext.getSystemService(Context.AUDIO_SERVICE)
                : null;
    }

    @LynxMethod
    public void create(ReadableMap options, Callback callback) {
        String id = orEmpty(options.hasKey("id") ? options.getString("id") : null);
        String uri = orEmpty(options.hasKey("uri") ? options.getString("uri") : null);
        String usage = orEmpty(options.hasKey("usage") ? options.getString("usage") : null);
        boolean autoPlay = options.hasKey("autoPlay") && !options.isNull("autoPlay")
                && options.getBoolean("autoPlay");
        int progressIntervalMs = options.hasKey("progressIntervalMs") && !options.isNull("progressIntervalMs")
                ? options.getInt("progressIntervalMs")
                : DEFAULT_PROGRESS_INTERVAL_MS;

        if (destroyed) {
            callback.invoke("AudioPlayer host has been destroyed");
            return;
        }
        if (!PLAYER_ID.matcher(id).matches()) {
            callback.invoke("Invalid AudioPlayer ID");
            return;
        }
        if (players.containsKey(id)) {
            callback.invoke("AudioPlayer ID already exists");
            return;
        }
        Uri parsed = Uri.parse(uri);
        String scheme = parsed.getScheme() == null ? "" : parsed.getScheme();
        if (!scheme.equalsIgnoreCase("file") && !scheme.equalsIgnoreCase("content")) {
            callback.invoke("AudioPlayer only supports local file:// or content:// sources");
            return;
        }
        if (isFileUri(parsed) && !new File(parsed.getPath()).canRead()) {
            callback.invoke("file-not-found: " + uri);
            return;
        }
        if (!isValidUsage(usage)) {
            callback.invoke("Invalid AudioPlayer usage");
            return;
        }
        if (progressIntervalMs < 50 || progressIntervalMs > 10_000) {
            callback.invoke("progressIntervalMs must be between 50 and 10000");
            return;
        }

        mainHandler.post(() -> {
            if (destroyed || players.containsKey(id)) {
                callback.invoke(destroyed
                        ? "AudioPlayer host has been destroyed"
                        : "AudioPlayer ID already exists");
                return;
            }
            PlayerHandle handle = new PlayerHandle(id, parsed, usage, autoPlay, progressIntervalMs);
            players.put(id, handle);
            if (!handle.prepare(callback)) {
                players.remove(id);
            }
        });
    }

    @LynxMethod
    public void play(String id, Callback callback) {
        withHandle(id, callback, handle -> handle.play(callback));
    }

    @LynxMethod
    public void pause(String id, Callback callback) {
        withHandle(id, callback, handle -> handle.pause(callback));
    }

    @LynxMethod
    public void seek(String id, int positionMs, Callback callback) {
        withHandle(id, callback, handle -> handle.seek(positionMs, callback));
    }

    @LynxMethod
    public void stop(String id, Callback callback) {
        withHandle(id, callback, handle -> handle.stop(callback));
    }

    @LynxMethod
    public void release(String id, Callback callback) {
        mainHandler.post(() -> {
            PlayerHandle handle = players.get(id);
            if (handle == null) {
                callback.invoke("Unknown AudioPlayer ID");
                return;
            }
            players.remove(id);
            handle.release();
            callback.invoke("");
        });
    }

    @LynxMethod
    public void setRate(String id, double rate, Callback callback) {
        withHandle(id, callback, handle -> handle.setRate((float) rate, callback));
    }

    @LynxMethod
    public void setVolume(String id, double volume, Callback callback) {
        withHandle(id, callback, handle -> handle.setVolume((float) volume, callback));
    }

    @LynxMethod
    public void getProps(String id, Callback callback) {
        withHandle(id, callback, handle -> handle.getProps(callback));
    }

    @Override
    public void destroy() {
        destroyed = true;
        mainHandler.post(() -> {
            for (PlayerHandle handle : players.values()) {
                handle.release();
            }
            players.clear();
        });
    }

    private interface HandleOperation {
        void run(PlayerHandle handle);
    }

    private void withHandle(String id, Callback callback, HandleOperation operation) {
        mainHandler.post(() -> {
            PlayerHandle handle = players.get(id);
            if (handle == null) {
                callback.invoke("Unknown AudioPlayer ID");
                return;
            }
            operation.run(handle);
        });
    }

    private static boolean isFileUri(Uri uri) {
        String scheme = uri.getScheme();
        return scheme != null && scheme.equalsIgnoreCase("file");
    }

    private static boolean isValidUsage(String usage) {
        return usage.equals(USAGE_MEDIA) || usage.equals(USAGE_AMBIENT)
                || usage.equals(USAGE_ALARM) || usage.equals(USAGE_NOTIFICATION);
    }

    private static String orEmpty(@Nullable String value) {
        return value == null ? "" : value;
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

    /**
     * Owns one MediaPlayer plus its focus request and progress ticker. All
     * methods run on the main looper.
     */
    private final class PlayerHandle {
        final String id;
        final Uri uri;
        final String usage;
        final int progressIntervalMs;

        MediaPlayer player;
        String state = STATE_LOADING;
        float userVolume = 1f;
        float desiredRate = 1f;
        boolean ducked = false;
        boolean pausedByFocus = false;
        boolean focusHeld = false;
        @Nullable AudioFocusRequest focusRequest;
        boolean released = false;
        boolean startOnPrepared;
        @Nullable Callback pendingCreate;
        private final Runnable progressTicker = new Runnable() {
            @Override
            public void run() {
                if (released || player == null || !STATE_PLAYING.equals(state)) {
                    return;
                }
                emitProgress();
                mainHandler.postDelayed(this, progressIntervalMs);
            }
        };

        PlayerHandle(String id, Uri uri, String usage, boolean autoPlay, int progressIntervalMs) {
            this.id = id;
            this.uri = uri;
            this.usage = usage;
            this.progressIntervalMs = progressIntervalMs;
            this.startOnPrepared = autoPlay;
        }

        /** Kicks off async prepare; the create callback fires when ready. */
        boolean prepare(Callback callback) {
            pendingCreate = callback;
            try {
                player = new MediaPlayer();
                player.setAudioAttributes(audioAttributesOf(usage));
                player.setDataSource(appContext(), uri);
                player.setOnPreparedListener(mp -> onPrepared());
                player.setOnCompletionListener(mp -> onCompletion());
                player.setOnErrorListener((mp, what, extra) -> onError(what, extra));
                player.prepareAsync();
                emitState(STATE_LOADING, null);
                return true;
            } catch (FileNotFoundException error) {
                finishPrepare("file-not-found: " + orEmpty(error.getMessage()));
                releaseInternal();
                return false;
            } catch (Throwable error) {
                String message = orEmpty(error.getMessage());
                finishPrepare(error instanceof SecurityException || error instanceof IllegalArgumentException
                        ? "read-failed: " + message
                        : "read-failed: Unable to open the audio source");
                releaseInternal();
                return false;
            }
        }

        private void onPrepared() {
            if (released) {
                return;
            }
            applyEffectiveVolume();
            if (startOnPrepared) {
                startOnPrepared = false;
                startPlayback(null);
            } else {
                state = STATE_PAUSED;
                emitState(STATE_PAUSED, null);
            }
            finishPrepare("");
        }

        private void finishPrepare(String error) {
            // Successful auto-play has already acquired focus in
            // startPlayback(); keep it until playback pauses, stops, ends, or
            // is released. Failed preparation never needs to retain focus.
            if (!error.isEmpty()) {
                releaseFocus();
            }
            Callback callback = pendingCreate;
            pendingCreate = null;
            if (callback != null) {
                callback.invoke(error);
            }
        }

        private void onCompletion() {
            if (released) {
                return;
            }
            stopTicker();
            releaseFocus();
            state = STATE_PAUSED;
            JavaOnlyMap payload = statePayload(STATE_PAUSED);
            payload.putInt("positionMs", durationMs());
            payload.putInt("durationMs", durationMs());
            emit(id, payload);
            JavaOnlyMap end = new JavaOnlyMap();
            end.putString("type", "end");
            emit(id, end);
        }

        private boolean onError(int what, int extra) {
            if (released) {
                return true;
            }
            String message = "Playback failed (" + what + "/" + extra + ")";
            if (pendingCreate != null) {
                finishPrepare("unsupported-format: " + message);
                releaseInternal();
                players.remove(id);
                return true;
            }
            stopTicker();
            releaseFocus();
            if (player != null && STATE_PLAYING.equals(state)) {
                state = STATE_PAUSED;
                emitState(STATE_PAUSED, null);
            }
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "error");
            payload.putString("error", message);
            emit(id, payload);
            return true;
        }

        void play(Callback callback) {
            if (released) {
                callback.invoke("AudioPlayer has been released");
                return;
            }
            if (STATE_PLAYING.equals(state)) {
                callback.invoke("");
                return;
            }
            if (STATE_LOADING.equals(state)) {
                callback.invoke("AudioPlayer is still loading");
                return;
            }
            if (STATE_STOPPED.equals(state)) {
                // MediaPlayer needs a fresh prepare after stop().
                startOnPrepared = true;
                state = STATE_LOADING;
                try {
                    player.prepareAsync();
                    emitState(STATE_LOADING, null);
                    callback.invoke("");
                } catch (Throwable error) {
                    startOnPrepared = false;
                    callback.invoke("read-failed: Unable to restart playback");
                }
                return;
            }
            pausedByFocus = false;
            startPlayback(callback);
        }

        void pause(Callback callback) {
            if (released || STATE_PAUSED.equals(state) || STATE_STOPPED.equals(state)) {
                callback.invoke(released ? "AudioPlayer has been released" : "");
                return;
            }
            if (STATE_LOADING.equals(state)) {
                startOnPrepared = false;
                callback.invoke("");
                return;
            }
            stopTicker();
            releaseFocus();
            player.pause();
            state = STATE_PAUSED;
            emitState(STATE_PAUSED, null);
            callback.invoke("");
        }

        void seek(int positionMs, Callback callback) {
            if (released) {
                callback.invoke("AudioPlayer has been released");
                return;
            }
            if (STATE_LOADING.equals(state) || STATE_STOPPED.equals(state) || player == null) {
                callback.invoke("AudioPlayer is not seekable in the " + state + " state");
                return;
            }
            int clamped = Math.max(0, Math.min(positionMs, Math.max(durationMs(), 0)));
            player.seekTo(clamped);
            JavaOnlyMap payload = statePayload(state);
            payload.putInt("positionMs", clamped);
            payload.putInt("durationMs", durationMs());
            emit(id, payload);
            callback.invoke("");
        }

        void stop(Callback callback) {
            if (released || STATE_STOPPED.equals(state)) {
                callback.invoke(released ? "AudioPlayer has been released" : "");
                return;
            }
            if (!STATE_LOADING.equals(state) && player != null) {
                stopTicker();
                releaseFocus();
                try {
                    player.stop();
                } catch (Throwable _error) {
                    // Stopping an unprepared player is not fatal for us.
                }
            }
            state = STATE_STOPPED;
            JavaOnlyMap payload = statePayload(STATE_STOPPED);
            payload.putInt("positionMs", 0);
            payload.putInt("durationMs", durationMs());
            emit(id, payload);
            callback.invoke("");
        }

        void setRate(float rate, Callback callback) {
            if (released) {
                callback.invoke("AudioPlayer has been released");
                return;
            }
            desiredRate = rate;
            applyRate();
            callback.invoke("");
        }

        void setVolume(float volume, Callback callback) {
            if (released) {
                callback.invoke("AudioPlayer has been released");
                return;
            }
            userVolume = volume;
            applyEffectiveVolume();
            callback.invoke("");
        }

        void getProps(Callback callback) {
            if (released || player == null) {
                callback.invoke("{\"error\":\"AudioPlayer is not available\"}");
                return;
            }
            try {
                JSONObject props = new JSONObject();
                props.put("state", state);
                props.put("positionMs", STATE_STOPPED.equals(state) ? 0 : player.getCurrentPosition());
                props.put("durationMs", durationMs());
                props.put("usage", usage);
                props.put("rate", (double) desiredRate);
                props.put("volume", (double) userVolume);
                callback.invoke(props.toString());
            } catch (JSONException error) {
                callback.invoke("{\"error\":\"AudioPlayer serialization failed\"}");
            }
        }

        void release() {
            if (released) {
                return;
            }
            released = true;
            Callback callback = pendingCreate;
            pendingCreate = null;
            if (callback != null) {
                callback.invoke("AudioPlayer has been released");
            }
            stopTicker();
            releaseFocus();
            releaseInternal();
        }

        private void releaseInternal() {
            released = true;
            if (player != null) {
                try {
                    player.release();
                } catch (Throwable _error) {
                    // Release is best-effort during teardown.
                }
                player = null;
            }
        }

        private void startPlayback(@Nullable Callback callback) {
            requestFocus();
            if (desiredRate != 1f) {
                applyRate();
            }
            player.start();
            state = STATE_PLAYING;
            emitState(STATE_PLAYING, null);
            mainHandler.postDelayed(progressTicker, progressIntervalMs);
            if (callback != null) {
                callback.invoke("");
            }
        }

        private void applyRate() {
            if (player == null || !STATE_PLAYING.equals(state)) {
                // setPlaybackParams() on a paused MediaPlayer implicitly
                // starts it; defer to the next start instead.
                return;
            }
            try {
                player.setPlaybackParams(player.getPlaybackParams().setSpeed(desiredRate));
            } catch (Throwable _error) {
                // Keep the previous rate if the platform rejects this one.
            }
        }

        private void applyEffectiveVolume() {
            if (player == null) {
                return;
            }
            float effective = ducked ? userVolume * DUCK_FACTOR : userVolume;
            player.setVolume(effective, effective);
        }

        private void requestFocus() {
            if (audioManager == null || focusHeld || USAGE_AMBIENT.equals(usage)) {
                return;
            }
            AudioFocusRequest request = new AudioFocusRequest.Builder(focusGainOf(usage))
                    .setAudioAttributes(audioAttributesOf(usage))
                    .setOnAudioFocusChangeListener(this::onFocusChange)
                    .setWillPauseWhenDucked(false)
                    .build();
            int result = audioManager.requestAudioFocus(request);
            if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                focusRequest = request;
                focusHeld = true;
            }
        }

        private void releaseFocus() {
            if (audioManager == null || !focusHeld) {
                return;
            }
            AudioFocusRequest request = focusRequest;
            focusRequest = null;
            focusHeld = false;
            ducked = false;
            pausedByFocus = false;
            if (request != null) {
                audioManager.abandonAudioFocusRequest(request);
            }
        }

        private void onFocusChange(int change) {
            if (released || player == null) {
                return;
            }
            switch (change) {
                case AudioManager.AUDIOFOCUS_LOSS:
                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT: {
                    if (STATE_PLAYING.equals(state)) {
                        pausedByFocus = true;
                        stopTicker();
                        player.pause();
                        state = STATE_PAUSED;
                        emitState(STATE_PAUSED, "pause");
                    }
                    break;
                }
                case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK: {
                    if (!ducked) {
                        ducked = true;
                        applyEffectiveVolume();
                        emitInterruption("duck");
                    }
                    break;
                }
                case AudioManager.AUDIOFOCUS_GAIN: {
                    if (ducked) {
                        ducked = false;
                        applyEffectiveVolume();
                        emitInterruption("unduck");
                    }
                    if (pausedByFocus && STATE_PAUSED.equals(state)) {
                        pausedByFocus = false;
                        startPlayback(null);
                    }
                    break;
                }
                default:
                    break;
            }
        }

        private void emitInterruption(String interruption) {
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "state");
            payload.putString("state", state);
            payload.putInt("positionMs", positionOf());
            payload.putInt("durationMs", durationMs());
            payload.putString("interruption", interruption);
            emit(id, payload);
        }

        private void emitState(String newState, @Nullable String interruption) {
            JavaOnlyMap payload = statePayload(newState);
            if (interruption != null) {
                payload.putString("interruption", interruption);
            }
            emit(id, payload);
        }

        private void emitProgress() {
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "progress");
            payload.putString("state", state);
            payload.putInt("positionMs", positionOf());
            payload.putInt("durationMs", durationMs());
            emit(id, payload);
        }

        private JavaOnlyMap statePayload(String newState) {
            JavaOnlyMap payload = new JavaOnlyMap();
            payload.putString("type", "state");
            payload.putString("state", newState);
            payload.putInt("positionMs", positionOf());
            payload.putInt("durationMs", durationMs());
            return payload;
        }

        private void stopTicker() {
            mainHandler.removeCallbacks(progressTicker);
        }

        private int positionOf() {
            if (released || player == null || STATE_STOPPED.equals(state)) {
                return 0;
            }
            return player.getCurrentPosition();
        }

        private int durationMs() {
            if (released || player == null || STATE_LOADING.equals(state)) {
                return 0;
            }
            try {
                return player.getDuration();
            } catch (Throwable _error) {
                return 0;
            }
        }

        private Context appContext() {
            Context context = mLynxContext != null ? mLynxContext.getApplicationContext() : null;
            if (context == null) {
                throw new IllegalStateException("AudioPlayer module has no host context");
            }
            return context;
        }
    }

    private static AudioAttributes audioAttributesOf(String usage) {
        int usageFlag = android.media.AudioAttributes.USAGE_MEDIA;
        int contentType = android.media.AudioAttributes.CONTENT_TYPE_MUSIC;
        if (USAGE_ALARM.equals(usage)) {
            usageFlag = android.media.AudioAttributes.USAGE_ALARM;
        } else if (USAGE_NOTIFICATION.equals(usage)) {
            usageFlag = android.media.AudioAttributes.USAGE_NOTIFICATION;
            contentType = android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION;
        }
        return new AudioAttributes.Builder()
                .setUsage(usageFlag)
                .setContentType(contentType)
                .build();
    }

    private static int focusGainOf(String usage) {
        if (USAGE_ALARM.equals(usage)) {
            return AudioManager.AUDIOFOCUS_GAIN_TRANSIENT;
        }
        if (USAGE_NOTIFICATION.equals(usage)) {
            return AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK;
        }
        return AudioManager.AUDIOFOCUS_GAIN;
    }
}
