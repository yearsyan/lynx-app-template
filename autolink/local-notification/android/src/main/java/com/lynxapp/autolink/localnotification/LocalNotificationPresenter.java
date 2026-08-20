package com.lynxapp.autolink.localnotification;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import java.util.HashSet;
import java.util.Set;

/**
 * Posting and scheduling primitives shared by the Lynx module and the
 * alarm receiver. Notifications use one app-visible channel ("Lynx"),
 * the string notification id maps to {@code hashCode()} ints, and
 * scheduled ids are tracked in SharedPreferences so cancelAll can also
 * clear pending alarms after a process restart.
 */
public final class LocalNotificationPresenter {

    static final String CHANNEL_ID = "lynx.local";
    static final String NOTIFICATION_TAG = "lynx.local";
    static final String EXTRA_ID = "lynx.local.ID";
    static final String EXTRA_TITLE = "lynx.local.TITLE";
    static final String EXTRA_BODY = "lynx.local.BODY";
    static final String EXTRA_SOUND = "lynx.local.SOUND";

    private static final String PREFERENCES = "lynx.local.notification";
    private static final String KEY_SCHEDULED_IDS = "scheduled_ids";

    private LocalNotificationPresenter() {}

    static int stableId(String id) {
        return id.hashCode();
    }

    static boolean notificationsEnabled(Context context) {
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null || !manager.areNotificationsEnabled()) {
            return false;
        }
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = manager.getNotificationChannel(CHANNEL_ID);
            return channel == null || channel.getImportance() != NotificationManager.IMPORTANCE_NONE;
        }
        return true;
    }

    /** Posts the notification now; assumes the enablement gate passed. */
    static void post(Context context, String id, String title, String body, boolean sound) {
        // A fired alarm is no longer pending. This also prevents an immediate
        // replacement from being followed by an older delayed delivery.
        cancelSchedule(context, id);
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null || !notificationsEnabled(context)) {
            return;
        }
        manager.cancel(NOTIFICATION_TAG, stableId(id));
        ensureChannel(context, manager);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
                ? new Notification.Builder(context, CHANNEL_ID)
                : new Notification.Builder(context);
        builder.setSmallIcon(context.getApplicationInfo().icon)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true);
        if (sound) {
            builder.setDefaults(Notification.DEFAULT_SOUND);
        }
        manager.notify(NOTIFICATION_TAG, stableId(id), builder.build());
    }

    /**
     * Schedules delivery through AlarmManager so delayed notifications
     * survive the Lynx app being killed. Uses an exact alarm when the
     * platform allows it and falls back to the inexact window otherwise.
     */
    static void schedule(Context context, String id, String title, String body,
            boolean sound, long delayMs) {
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarms == null) {
            throw new IllegalStateException("AlarmManager is unavailable");
        }
        // Reusing an id replaces both a delivered notification and any older
        // pending alarm before the new schedule is installed.
        cancel(context, id);
        Intent intent = new Intent(context, ScheduledNotificationReceiver.class)
                .setAction("lynx.local.SCHEDULED")
                .putExtra(EXTRA_ID, id)
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_BODY, body)
                .putExtra(EXTRA_SOUND, sound);
        PendingIntent pending = PendingIntent.getBroadcast(
                context,
                stableId(id),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        long triggerAt = System.currentTimeMillis() + delayMs;
        boolean exactAllowed = Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms();
        if (exactAllowed) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
        } else {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending);
        }
        trackScheduled(context, id);
    }

    static void cancel(Context context, String id) {
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager != null) {
            manager.cancel(NOTIFICATION_TAG, stableId(id));
        }
        cancelSchedule(context, id);
    }

    private static void cancelSchedule(Context context, String id) {
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarms != null) {
            Intent intent = new Intent(context, ScheduledNotificationReceiver.class)
                    .setAction("lynx.local.SCHEDULED");
            alarms.cancel(PendingIntent.getBroadcast(
                    context,
                    stableId(id),
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
        }
        untrackScheduled(context, id);
    }

    static void cancelAll(Context context) {
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager != null) {
            manager.cancelAll();
        }
        AlarmManager alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (alarms != null) {
            for (String id : readScheduled(context)) {
                Intent intent = new Intent(context, ScheduledNotificationReceiver.class)
                        .setAction("lynx.local.SCHEDULED");
                alarms.cancel(PendingIntent.getBroadcast(
                        context,
                        stableId(id),
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE));
            }
        }
        preferences(context).edit().remove(KEY_SCHEDULED_IDS).apply();
    }

    private static void ensureChannel(Context context, NotificationManager manager) {
        if (Build.VERSION.SDK_INT < 26) {
            return;
        }
        NotificationChannel channel = manager.getNotificationChannel(CHANNEL_ID);
        if (channel != null) {
            return;
        }
        channel = new NotificationChannel(
                CHANNEL_ID,
                "Lynx",
                NotificationManager.IMPORTANCE_DEFAULT);
        channel.setDescription("Local notifications posted by Lynx pages");
        manager.createNotificationChannel(channel);
    }

    private static SharedPreferences preferences(Context context) {
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
    }

    private static Set<String> readScheduled(Context context) {
        return preferences(context).getStringSet(KEY_SCHEDULED_IDS, new HashSet<>());
    }

    private static void trackScheduled(Context context, String id) {
        Set<String> ids = new HashSet<>(readScheduled(context));
        ids.add(id);
        preferences(context).edit().putStringSet(KEY_SCHEDULED_IDS, ids).apply();
    }

    private static void untrackScheduled(Context context, String id) {
        Set<String> ids = new HashSet<>(readScheduled(context));
        if (ids.remove(id)) {
            preferences(context).edit().putStringSet(KEY_SCHEDULED_IDS, ids).apply();
        }
    }
}
