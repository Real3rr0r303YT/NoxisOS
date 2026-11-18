// SPDX-License-Identifier: GPL-3.0-or-later
// Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
package com.noxis.guard;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.Uri;
import android.provider.Settings;

import java.util.List;

/** Prüft jede neu installierte oder aktualisierte App sofort und meldet Treffer. */
final class ScanWatcher {
    private static final String CHANNEL = "scan";

    private ScanWatcher() {}

    static void start(Context ctx) {
        NotificationManager nm = ctx.getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "Virenscan",
                NotificationManager.IMPORTANCE_HIGH));
        IntentFilter f = new IntentFilter();
        f.addAction(Intent.ACTION_PACKAGE_ADDED);
        f.addAction(Intent.ACTION_PACKAGE_REPLACED);
        f.addDataScheme("package");
        ctx.registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                Uri d = i.getData();
                if (d == null) return;
                String pkg = d.getSchemeSpecificPart();
                // REPLACED kommt zusätzlich zu ADDED – nur einmal prüfen
                if (Intent.ACTION_PACKAGE_ADDED.equals(i.getAction())
                        && i.getBooleanExtra(Intent.EXTRA_REPLACING, false)) return;
                PendingResult pr = goAsync();
                new Thread(() -> {
                    try {
                        List<Scanner.Finding> f = Scanner.scanPackage(c, pkg);
                        if (!f.isEmpty()) alert(c, f.get(0));
                    } finally {
                        pr.finish();
                    }
                }, "noxis-scan").start();
            }
        }, f, Context.RECEIVER_EXPORTED);   // Paket-Broadcasts kommen vom System
    }

    private static void alert(Context ctx, Scanner.Finding f) {
        Intent info = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.fromParts("package", f.pkg, null)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        PendingIntent pi = PendingIntent.getActivity(ctx, f.pkg.hashCode(), info,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification n = new Notification.Builder(ctx, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_warning)
                .setContentTitle((f.malware ? "Schadsoftware: " : "Verdächtig: ") + f.label)
                .setStyle(new Notification.BigTextStyle().bigText(f.reason + "\nAntippen → App-Info → Deinstallieren"))
                .setContentText(f.reason)
                .setContentIntent(pi)
                .setAutoCancel(true)
                .build();
        ctx.getSystemService(NotificationManager.class).notify(f.pkg.hashCode(), n);
    }
}
