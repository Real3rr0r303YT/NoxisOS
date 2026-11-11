package com.noxis.guard;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public class GuardReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent intent) {
        String a = intent.getAction();
        if (a == null) return;
        if (a.startsWith("com.noxis.guard.")) {
            GuardController.get(ctx).onAlarm(a);
        }
        // BOOT_COMPLETED / LOCKED_BOOT_COMPLETED: GuardApp.onCreate hat bereits alles gestartet
    }
}
