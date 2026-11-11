package com.noxis.guard;

import android.content.ContentResolver;
import android.content.Context;
import android.provider.Settings;
import android.telephony.TelephonyManager;

import java.util.ArrayList;
import java.util.List;

/** Übersicht „Schutzstatus“: liest den echten Systemzustand, nicht nur die eigenen Einstellungen. */
final class Status {
    static final class Item {
        final String title;
        final boolean ok;
        final String hint;
        Item(String title, boolean ok, String hint) { this.title = title; this.ok = ok; this.hint = hint; }
    }

    private Status() {}

    static List<Item> check(Context ctx) {
        ContentResolver cr = ctx.getContentResolver();
        List<Item> l = new ArrayList<>();
        boolean vpn = Prefs.MULLVAD.equals(secureStr(cr, "always_on_vpn_app"))
                && secureInt(cr, "always_on_vpn_lockdown", 0) == 1;
        l.add(new Item("Mullvad-Killswitch", vpn,
                Hardening.installed(ctx, Prefs.MULLVAD) ? "Mullvad öffnen, anmelden, dann unten einschalten"
                        : "Mullvad VPN ist nicht installiert"));
        l.add(new Item("Privates DNS verschlüsselt", "hostname".equals(globalStr(cr, "private_dns_mode")),
                "Unter Netzwerk einen DNS-Anbieter wählen"));
        l.add(new Item("2G gesperrt", !twoGAllowed(ctx), "Unter Funk „2G erlauben“ ausschalten"));
        l.add(new Item("USB-Daten gesperrt, wenn gesperrt", Prefs.usbLock(ctx), "Unter Gerätesperre einschalten"));
        l.add(new Item("Automatischer Neustart", Prefs.autoRebootHours(ctx) > 0, "Unter Gerätesperre eine Zeit wählen"));
        l.add(new Item("Keine Google-Verbindungsprüfung", globalInt(cr, "captive_portal_mode", 1) == 0,
                "Unter Netzwerk „Verbindungsprüfung“ ausschalten"));
        l.add(new Item("Zufällige MAC-Adresse", globalInt(cr, "wifi_non_persistent_mac_randomization_force_enabled", 0) == 1,
                "Noxis Guard einmal neu starten"));
        l.add(new Item("Benachrichtigungen auf dem Sperrbildschirm verborgen",
                secureInt(cr, "lock_screen_allow_private_notifications", 1) == 0,
                "Einstellungen → Benachrichtigungen → Sperrbildschirm"));
        return l;
    }

    static int score(List<Item> items) {
        int n = 0;
        for (Item i : items) if (i.ok) n++;
        return n;
    }

    static boolean twoGAllowed(Context ctx) {
        try {
            TelephonyManager tm = ctx.getSystemService(TelephonyManager.class);
            if (tm == null) return true;
            long cur = tm.getAllowedNetworkTypesForReason(TelephonyManager.ALLOWED_NETWORK_TYPES_REASON_ENABLE_2G);
            return (cur & Hardening.BITMASK_2G) != 0;
        } catch (RuntimeException e) {
            return true;
        }
    }

    private static String secureStr(ContentResolver cr, String k) {
        try { return Settings.Secure.getString(cr, k); } catch (RuntimeException e) { return null; }
    }
    private static int secureInt(ContentResolver cr, String k, int d) {
        try { return Settings.Secure.getInt(cr, k, d); } catch (RuntimeException e) { return d; }
    }
    private static String globalStr(ContentResolver cr, String k) {
        try { return Settings.Global.getString(cr, k); } catch (RuntimeException e) { return null; }
    }
    private static int globalInt(ContentResolver cr, String k, int d) {
        try { return Settings.Global.getInt(cr, k, d); } catch (RuntimeException e) { return d; }
    }
}
