package com.lynxapp.autolink.downloadmanager;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.os.Build;
import android.os.IBinder;

import androidx.annotation.Nullable;

/** Optional Android dataSync foreground-service execution adapter. */
public final class DownloadForegroundService extends Service
        implements DownloadEngine.Listener {
    private static final String ACTION_BEGIN =
            "com.lynxapp.autolink.downloadmanager.BEGIN";
    private static final String EXTRA_TASK_ID = "taskId";
    private static final String CHANNEL_ID = "lynx_downloads";
    private static final int NOTIFICATION_ID = 0x4c594e58;

    private DownloadEngine engine;

    static void begin(Context context, String taskId) {
        Intent intent = new Intent(context, DownloadForegroundService.class);
        intent.setAction(ACTION_BEGIN);
        intent.putExtra(EXTRA_TASK_ID, taskId);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent);
        } else {
            context.startService(intent);
        }
    }

    @Override
    public void onCreate() {
        super.onCreate();
        engine = DownloadEngine.get(this);
        engine.addListener(this);
        createNotificationChannel();
    }

    @Override
    public int onStartCommand(@Nullable Intent intent, int flags, int startId) {
        String taskId = intent == null ? null : intent.getStringExtra(EXTRA_TASK_ID);
        DownloadEngine.Snapshot snapshot = taskId == null ? null : engine.getTask(taskId);
        startForeground(NOTIFICATION_ID, notificationFor(snapshot));
        if (taskId == null || !ACTION_BEGIN.equals(intent.getAction())) {
            stopIfIdle();
            return START_NOT_STICKY;
        }
        try {
            engine.startFromForegroundService(taskId);
        } catch (Throwable error) {
            engine.failToLaunch(taskId, error);
        }
        stopIfIdle();
        return START_NOT_STICKY;
    }

    @Override
    public void onDownloadEvent(String type, DownloadEngine.Snapshot snapshot) {
        if (!snapshot.usesForegroundService()) return;
        if (engine.hasActiveForegroundTasks()) {
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                DownloadEngine.Snapshot active = engine.newestActiveForegroundTask();
                manager.notify(NOTIFICATION_ID, notificationFor(active));
            }
        } else {
            stopIfIdle();
        }
    }

    @Override
    public void onTimeout(int startId, int foregroundServiceType) {
        engine.pauseForegroundTasks("Android ended the foreground dataSync time window");
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf(startId);
    }

    @Override
    public void onDestroy() {
        if (engine != null) engine.removeListener(this);
        super.onDestroy();
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void stopIfIdle() {
        if (engine != null && engine.hasActiveForegroundTasks()) return;
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    private Notification notificationFor(@Nullable DownloadEngine.Snapshot task) {
        String title = task == null ? "Preparing download" : task.notificationTitle;
        String text = task == null ? "Download in progress" : task.notificationText;
        Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new Notification.Builder(this, CHANNEL_ID)
                : new Notification.Builder(this);
        builder.setSmallIcon(notificationIcon())
                .setContentTitle(title)
                .setContentText(text)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setOnlyAlertOnce(true)
                .setOngoing(true);
        if (task != null && task.totalBytes != null && task.totalBytes > 0L) {
            long percentage = Math.min(100L, task.bytesDownloaded * 100L / task.totalBytes);
            builder.setProgress(100, (int) percentage, false);
        } else {
            builder.setProgress(0, 0, true);
        }
        return builder.build();
    }

    private int notificationIcon() {
        ApplicationInfo info = getApplicationInfo();
        return info.icon == 0 ? android.R.drawable.stat_sys_download : info.icon;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager manager = getSystemService(NotificationManager.class);
        if (manager == null) return;
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Downloads",
                NotificationManager.IMPORTANCE_LOW);
        channel.setDescription("Active app downloads");
        manager.createNotificationChannel(channel);
    }
}
