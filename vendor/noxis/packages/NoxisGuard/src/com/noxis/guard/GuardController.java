package com.noxis.guard;

import android.app.AlarmManager;
import android.app.KeyguardManager;
import android.app.PendingIntent;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.hardware.usb.UsbManager;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.net.NetworkRequest;
import android.net.wifi.WifiManager;
import android.os.PowerManager;
import android.os.SystemClock;
import android.util.Log;

import java.util.HashSet;
import java.util.Set;

/**
 * Kernlogik von Noxis Guard:
 *  - Auto-Neustart nach X Stunden im gesperrten Zustand (zurück in BFU, Schlüssel aus dem RAM)
 *  - USB-C im gesperrten Zustand nur Laden (keine Datenverbindung)
 *  - WLAN / Bluetooth automatisch aus, wenn X Minuten nicht verbunden
 */
final class GuardController {
    static final String TAG = "NoxisGuard";
    static final String ACTION_REBOOT = "com.noxis.guard.REBOOT_CHECK";
    static final String ACTION_WIFI = "com.noxis.guard.WIFI_CHECK";
    static final String ACTION_BT = "com.noxis.guard.BT_CHECK";

    private static final int[] BT_PROFILES = {1 /* HEADSET */, 2 /* A2DP */, 21 /* HEARING_AID */, 22 /* LE_AUDIO */};
    private static GuardController sInstance;

    private final Context mCtx;
    private final AlarmManager mAlarm;
    private final KeyguardManager mKeyguard;
    private final Set<Network> mWifiNetworks = new HashSet<>();

    static synchronized GuardController get(Context ctx) {
        if (sInstance == null) sInstance = new GuardController(ctx.getApplicationContext());
        return sInstance;
    }

    private GuardController(Context ctx) {
        mCtx = ctx;
        mAlarm = ctx.getSystemService(AlarmManager.class);
        mKeyguard = ctx.getSystemService(KeyguardManager.class);
    }

    void start() {
        try {
            mKeyguard.addKeyguardLockedStateListener(mCtx.getMainExecutor(), this::onLockChanged);
        } catch (RuntimeException e) {
            Log.e(TAG, "Keyguard-Listener nicht verfügbar", e);
        }
        onLockChanged(mKeyguard.isDeviceLocked());

        IntentFilter f = new IntentFilter();
        f.addAction(WifiManager.WIFI_STATE_CHANGED_ACTION);
        f.addAction(BluetoothAdapter.ACTION_STATE_CHANGED);
        f.addAction(BluetoothAdapter.ACTION_CONNECTION_STATE_CHANGED);
        mCtx.registerReceiver(new BroadcastReceiver() {
            @Override
            public void onReceive(Context c, Intent i) {
                if (WifiManager.WIFI_STATE_CHANGED_ACTION.equals(i.getAction())) scheduleWifiCheck();
                else scheduleBtCheck();
            }
        }, f, Context.RECEIVER_NOT_EXPORTED);

        ConnectivityManager cm = mCtx.getSystemService(ConnectivityManager.class);
        NetworkRequest req = new NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build();
        cm.registerNetworkCallback(req, new ConnectivityManager.NetworkCallback() {
            @Override
            public void onAvailable(Network n) {
                synchronized (mWifiNetworks) { mWifiNetworks.add(n); }
                cancel(ACTION_WIFI);
            }

            @Override
            public void onLost(Network n) {
                synchronized (mWifiNetworks) { mWifiNetworks.remove(n); }
                scheduleWifiCheck();
            }
        });
        scheduleWifiCheck();
        scheduleBtCheck();
        Log.i(TAG, "Noxis Guard aktiv");
    }

    /* ---------------- Sperrzustand ---------------- */

    void onLockChanged(boolean locked) {
        if (locked) {
            if (Prefs.usbLock(mCtx)) setUsbData(false);
            scheduleReboot();
        } else {
            setUsbData(true);
            cancel(ACTION_REBOOT);
            Hardening.applyVpnOnce(mCtx);
            Hardening.apply2g(mCtx, Prefs.allow2g(mCtx));
        }
    }

    void applySettings() {
        onLockChanged(mKeyguard.isDeviceLocked());
        cancel(ACTION_WIFI);
        cancel(ACTION_BT);
        scheduleWifiCheck();
        scheduleBtCheck();
    }

    private void setUsbData(boolean enabled) {
        try {
            UsbManager usb = mCtx.getSystemService(UsbManager.class);
            boolean ok = usb.enableUsbDataSignal(enabled);
            Log.i(TAG, "USB-Daten " + (enabled ? "an" : "aus") + (ok ? "" : " (nicht unterstützt)"));
        } catch (RuntimeException e) {
            Log.w(TAG, "USB-Datensteuerung fehlgeschlagen", e);
        }
    }

    private void scheduleReboot() {
        int h = Prefs.autoRebootHours(mCtx);
        if (h <= 0) { cancel(ACTION_REBOOT); return; }
        set(ACTION_REBOOT, h * 3_600_000L);
    }

    /* ---------------- WLAN / Bluetooth ---------------- */

    private void scheduleWifiCheck() {
        int m = Prefs.wifiOffMin(mCtx);
        if (m <= 0 || !wifiEnabled() || wifiConnected()) { cancel(ACTION_WIFI); return; }
        set(ACTION_WIFI, m * 60_000L);
    }

    private void scheduleBtCheck() {
        int m = Prefs.btOffMin(mCtx);
        if (m <= 0 || !btEnabled() || btConnected()) { cancel(ACTION_BT); return; }
        set(ACTION_BT, m * 60_000L);
    }

    private boolean wifiEnabled() {
        WifiManager w = mCtx.getSystemService(WifiManager.class);
        return w != null && w.isWifiEnabled();
    }

    private boolean wifiConnected() {
        synchronized (mWifiNetworks) { return !mWifiNetworks.isEmpty(); }
    }

    private BluetoothAdapter bt() {
        BluetoothManager m = mCtx.getSystemService(BluetoothManager.class);
        return m == null ? null : m.getAdapter();
    }

    private boolean btEnabled() {
        BluetoothAdapter a = bt();
        try { return a != null && a.isEnabled(); } catch (SecurityException e) { return false; }
    }

    private boolean btConnected() {
        BluetoothAdapter a = bt();
        if (a == null) return false;
        try {
            for (int p : BT_PROFILES) {
                if (a.getProfileConnectionState(p) == 2 /* STATE_CONNECTED */) return true;
            }
        } catch (SecurityException e) {
            return true; // im Zweifel nicht abschalten
        }
        return false;
    }

    /* ---------------- Alarme ---------------- */

    void onAlarm(String action) {
        if (ACTION_REBOOT.equals(action)) {
            if (mKeyguard.isDeviceLocked() && Prefs.autoRebootHours(mCtx) > 0) {
                Log.i(TAG, "Auto-Neustart: Gerät war zu lange gesperrt");
                mCtx.getSystemService(PowerManager.class).reboot("noxis-auto-reboot");
            }
        } else if (ACTION_WIFI.equals(action)) {
            if (Prefs.wifiOffMin(mCtx) > 0 && wifiEnabled() && !wifiConnected()) {
                Log.i(TAG, "WLAN-Auto-Aus");
                mCtx.getSystemService(WifiManager.class).setWifiEnabled(false);
            }
        } else if (ACTION_BT.equals(action)) {
            BluetoothAdapter a = bt();
            if (Prefs.btOffMin(mCtx) > 0 && a != null && btEnabled() && !btConnected()) {
                Log.i(TAG, "Bluetooth-Auto-Aus");
                a.disable();
            }
        }
    }

    private PendingIntent pi(String action) {
        Intent i = new Intent(action).setPackage(mCtx.getPackageName()).setClass(mCtx, GuardReceiver.class);
        return PendingIntent.getBroadcast(mCtx, action.hashCode(), i,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
    }

    private void set(String action, long delayMs) {
        mAlarm.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + delayMs, pi(action));
    }

    private void cancel(String action) {
        mAlarm.cancel(pi(action));
    }
}
