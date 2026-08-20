package com.lynxapp.autolink.localnotification;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Fires the delayed notifications scheduled through AlarmManager. The
 * receiver re-checks the notification switch, so a notification disabled
 * between scheduling and delivery is dropped instead of crashing.
 */
public final class ScheduledNotificationReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        String id = intent.getStringExtra(LocalNotificationPresenter.EXTRA_ID);
        String title = intent.getStringExtra(LocalNotificationPresenter.EXTRA_TITLE);
        String body = intent.getStringExtra(LocalNotificationPresenter.EXTRA_BODY);
        if (id == null || title == null) {
            return;
        }
        LocalNotificationPresenter.post(
                context,
                id,
                title,
                body == null ? "" : body,
                intent.getBooleanExtra(LocalNotificationPresenter.EXTRA_SOUND, true));
    }
}
