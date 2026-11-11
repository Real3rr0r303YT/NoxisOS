package com.noxis.guard;

import android.content.ContentResolver;
import android.content.Context;
import android.content.pm.PackageManager;
import android.net.VpnManager;
import android.os.Process;
import android.telephony.TelephonyManager;
import android.provider.Settings;
import android.util.Log;

/** Gehärtete Systemstandards (einmal beim ersten Start, danach über die App änderbar). */
final class Hardening {
    private static final String TAG = "NoxisGuard";
    static final int VERSION = 2;

    /** GSM, GPRS, EDGE, CDMA, 1xRTT – wie der 2G-Schalter in den Android-Einstellungen. */
    static final long BITMASK_2G = TelephonyManager.NETWORK_TYPE_BITMASK_GSM
            | TelephonyManager.NETWORK_TYPE_BITMASK_GPRS | TelephonyManager.NETWORK_TYPE_BITMASK_EDGE
            | TelephonyManager.NETWORK_TYPE_BITMASK_CDMA | TelephonyManager.NETWORK_TYPE_BITMASK_1xRTT;

    private Hardening() {}

    static void applyOnce(Context ctx) {
        if (Prefs.get(ctx).getInt(Prefs.HARDENED_V, 0) >= VERSION) return;
        ContentResolver cr = ctx.getContentResolver();
        // WLAN: neue zufällige MAC-Adresse bei jeder Verbindung
        putGlobal(cr, "wifi_non_persistent_mac_randomization_force_enabled", 1);
        // Keine Hintergrund-Scans für Standortdienste
        putGlobal(cr, "wifi_scan_always_enabled", 0);
        putGlobal(cr, "ble_scan_always_enabled", 0);
        putGlobal(cr, "network_recommendations_enabled", 0);
        // Zeit nicht von Google
        putGlobalStr(cr, "ntp_server", "pool.ntp.org");
        // Sperrbildschirm: Inhalte von Benachrichtigungen verbergen
        putSecure(cr, "lock_screen_allow_private_notifications", 0);
        applyDns(ctx, Prefs.dns(ctx));
        applyConnectivityCheck(ctx, Prefs.connCheck(ctx));
        apply2g(ctx, Prefs.allow2g(ctx));
        Prefs.get(ctx).edit().putInt(Prefs.HARDENED_V, VERSION).apply();
        Log.i(TAG, "Gehärtete Standardwerte gesetzt (v" + VERSION + ")");
    }

    /** host leer = Private DNS aus (Netzwerk-DNS), sonst DNS-over-TLS über host. */
    static void applyDns(Context ctx, String host) {
        ContentResolver cr = ctx.getContentResolver();
        if (host == null || host.isEmpty()) {
            putGlobalStr(cr, "private_dns_mode", "opportunistic");
        } else {
            putGlobalStr(cr, "private_dns_specifier", host);
            putGlobalStr(cr, "private_dns_mode", "hostname");
        }
    }

    /** Mullvad als Always-on-VPN; lockdown = Verbindungen ohne VPN blockieren (Killswitch). */
    static boolean applyVpn(Context ctx, boolean enabled) {
        if (enabled && !installed(ctx, Prefs.MULLVAD)) {
            Log.w(TAG, "Mullvad nicht installiert – Always-on-VPN übersprungen");
            return false;
        }
        try {
            VpnManager vm = ctx.getSystemService(VpnManager.class);
            int user = Process.myUserHandle().getIdentifier();
            boolean ok = vm.setAlwaysOnVpnPackageForUser(user, enabled ? Prefs.MULLVAD : null, enabled, null);
            Log.i(TAG, "Always-on-VPN " + (enabled ? "Mullvad + Killswitch" : "aus") + (ok ? "" : " – abgelehnt"));
            return ok;
        } catch (RuntimeException e) {
            Log.e(TAG, "Always-on-VPN fehlgeschlagen", e);
            return false;
        }
    }

    /** Einmalig beim ersten Entsperren (VPN-Dienste brauchen einen entsperrten Benutzer). */
    static void applyVpnOnce(Context ctx) {
        if (Prefs.get(ctx).getBoolean(Prefs.VPN_APPLIED, false)) return;
        if (applyVpn(ctx, Prefs.vpnLockdown(ctx)) || !Prefs.vpnLockdown(ctx)) {
            Prefs.get(ctx).edit().putBoolean(Prefs.VPN_APPLIED, true).apply();
        }
    }

    static boolean installed(Context ctx, String pkg) {
        try {
            ctx.getPackageManager().getPackageInfo(pkg, 0);
            return true;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    /**
     * 2G sperren/erlauben (pro SIM in Telephony gespeichert). Wird bei jedem Entsperren erneut
     * angewendet, damit auch eine neue SIM sofort ohne 2G läuft. Notrufe sind davon ausgenommen.
     */
    static boolean apply2g(Context ctx, boolean allow) {
        try {
            TelephonyManager tm = ctx.getSystemService(TelephonyManager.class);
            if (tm == null) return false;
            long cur = tm.getAllowedNetworkTypesForReason(TelephonyManager.ALLOWED_NETWORK_TYPES_REASON_ENABLE_2G);
            long want = allow ? (cur | BITMASK_2G) : (cur & ~BITMASK_2G);
            if (want != cur) {
                tm.setAllowedNetworkTypesForReason(TelephonyManager.ALLOWED_NETWORK_TYPES_REASON_ENABLE_2G, want);
                Log.i(TAG, "2G " + (allow ? "erlaubt" : "gesperrt"));
            }
            return true;
        } catch (RuntimeException e) {
            Log.w(TAG, "2G-Einstellung nicht möglich", e);
            return false;
        }
    }

    /** false = keine Verbindungsprüfung zu Google-Servern (captive_portal_mode 0). */
    static void applyConnectivityCheck(Context ctx, boolean enabled) {
        putGlobal(ctx.getContentResolver(), "captive_portal_mode", enabled ? 1 : 0);
    }

    private static void putGlobal(ContentResolver cr, String key, int v) {
        try { Settings.Global.putInt(cr, key, v); } catch (RuntimeException e) { Log.w(TAG, key, e); }
    }

    private static void putGlobalStr(ContentResolver cr, String key, String v) {
        try { Settings.Global.putString(cr, key, v); } catch (RuntimeException e) { Log.w(TAG, key, e); }
    }

    private static void putSecure(ContentResolver cr, String key, int v) {
        try { Settings.Secure.putInt(cr, key, v); } catch (RuntimeException e) { Log.w(TAG, key, e); }
    }
}
