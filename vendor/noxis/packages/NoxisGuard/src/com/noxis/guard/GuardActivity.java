package com.noxis.guard;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

/** Einstellungsoberfläche im Stil der Android-Systemeinstellungen. */
public class GuardActivity extends Activity {

    private static final int[] REBOOT_H = {0, 8, 12, 18, 24, 36, 48, 72};
    private static final int[] OFF_MIN = {0, 2, 5, 10, 15, 30, 60, 120};
    private static final String[] DNS_HOSTS = {"dns.quad9.net", "dns.mullvad.net", "one.one.one.one", ""};
    private static final String[] DNS_NAMES = {"Quad9 (Standard)", "Mullvad", "Cloudflare", "Aus – Netzwerk-DNS"};

    private LinearLayout mList;
    private SharedPreferences mPrefs;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        mPrefs = Prefs.get(this);
        ScrollView sv = new ScrollView(this);
        mList = new LinearLayout(this);
        mList.setOrientation(LinearLayout.VERTICAL);
        mList.setPadding(dp(16), dp(24), dp(16), dp(32));
        sv.addView(mList);
        setContentView(sv);
        render();
    }

    private void render() {
        mList.removeAllViews();
        TextView title = text("Noxis Guard", 30, true);
        title.setPadding(dp(8), dp(24), dp(8), dp(4));
        mList.addView(title);
        TextView sub = text("Schutzfunktionen von Noxis OS", 14, false);
        sub.setAlpha(0.7f);
        sub.setPadding(dp(8), 0, dp(8), dp(16));
        mList.addView(sub);

        header("Gerätesperre");
        choice("Automatischer Neustart", hoursLabel(Prefs.autoRebootHours(this)),
                "Startet das Gerät neu, wenn es so lange gesperrt war. Danach sind alle Daten wieder "
                        + "vollständig verschlüsselt (Zustand vor dem ersten Entsperren).",
                labels(REBOOT_H, true), indexOf(REBOOT_H, Prefs.autoRebootHours(this)),
                i -> mPrefs.edit().putInt(Prefs.AUTO_REBOOT_HOURS, REBOOT_H[i]).apply());
        toggle("USB-C nur Laden, wenn gesperrt",
                "Blockiert Datenverbindungen über USB, solange das Gerät gesperrt ist.",
                Prefs.usbLock(this), on -> mPrefs.edit().putBoolean(Prefs.USB_LOCK, on).apply());

        header("Funk");
        choice("WLAN automatisch aus", minLabel(Prefs.wifiOffMin(this)),
                "Schaltet WLAN ab, wenn so lange keine Verbindung besteht.",
                labels(OFF_MIN, false), indexOf(OFF_MIN, Prefs.wifiOffMin(this)),
                i -> mPrefs.edit().putInt(Prefs.WIFI_OFF_MIN, OFF_MIN[i]).apply());
        choice("Bluetooth automatisch aus", minLabel(Prefs.btOffMin(this)),
                "Schaltet Bluetooth ab, wenn so lange kein Gerät verbunden ist.",
                labels(OFF_MIN, false), indexOf(OFF_MIN, Prefs.btOffMin(this)),
                i -> mPrefs.edit().putInt(Prefs.BT_OFF_MIN, OFF_MIN[i]).apply());

        header("Netzwerk");
        if (Hardening.installed(this, Prefs.MULLVAD)) {
            toggle("Mullvad: immer an + Killswitch",
                    "Gesamter Datenverkehr nur durch Mullvad. Ohne VPN-Verbindung kein Internet – "
                            + "auch nicht beim Start oder Netzwechsel.",
                    Prefs.vpnLockdown(this), on -> {
                        mPrefs.edit().putBoolean(Prefs.VPN_LOCKDOWN, on).apply();
                        Hardening.applyVpn(this, on);
                    });
        }
        int di = 0;
        for (int i = 0; i < DNS_HOSTS.length; i++) if (DNS_HOSTS[i].equals(Prefs.dns(this))) di = i;
        choice("Privates DNS (DNS-over-TLS)", DNS_NAMES[di],
                "Verschlüsselt DNS-Anfragen. Gilt für WLAN und Mobilfunk.",
                DNS_NAMES, di, i -> {
                    mPrefs.edit().putString(Prefs.DNS, DNS_HOSTS[i]).apply();
                    Hardening.applyDns(this, DNS_HOSTS[i]);
                });
        toggle("Verbindungsprüfung",
                "Prüft Netzwerke über connectivitycheck.gstatic.com (Google). Aus = keine Anfragen, "
                        + "dafür werden WLAN-Anmeldeseiten (Hotel, Bahn) nicht automatisch erkannt.",
                Prefs.connCheck(this), on -> {
                    mPrefs.edit().putBoolean(Prefs.CONN_CHECK, on).apply();
                    Hardening.applyConnectivityCheck(this, on);
                });
    }

    /* ---------------- Bausteine ---------------- */

    interface IntConsumer { void accept(int v); }
    interface BoolConsumer { void accept(boolean v); }

    private void header(String s) {
        TextView t = text(s, 13, true);
        t.setTextColor(0xFF7FA7FF);
        t.setPadding(dp(8), dp(24), dp(8), dp(8));
        mList.addView(t);
    }

    private void choice(String title, String value, String summary, String[] items, int sel, IntConsumer cb) {
        LinearLayout row = row(title, value + "\n" + summary);
        row.setOnClickListener(v -> new AlertDialog.Builder(this)
                .setTitle(title)
                .setSingleChoiceItems(items, sel, (d, which) -> {
                    cb.accept(which);
                    d.dismiss();
                    GuardController.get(this).applySettings();
                    render();
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show());
        mList.addView(row);
    }

    private void toggle(String title, String summary, boolean on, BoolConsumer cb) {
        LinearLayout row = row(title, summary);
        Switch sw = new Switch(this);
        sw.setChecked(on);
        sw.setClickable(false);
        sw.setFocusable(false);
        row.addView(sw);
        row.setOnClickListener(v -> {
            sw.setChecked(!sw.isChecked());
            cb.accept(sw.isChecked());
            GuardController.get(this).applySettings();
        });
        mList.addView(row);
    }

    private LinearLayout row(String title, String summary) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(8), dp(14), dp(8), dp(14));
        row.setMinimumHeight(dp(72));
        TypedValue tv = new TypedValue();
        getTheme().resolveAttribute(android.R.attr.selectableItemBackground, tv, true);
        row.setBackgroundResource(tv.resourceId);
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        col.addView(text(title, 17, false));
        TextView s = text(summary, 14, false);
        s.setAlpha(0.7f);
        col.addView(s);
        row.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        return row;
    }

    private TextView text(String s, int sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, sp);
        if (bold) t.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        return t;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }

    private static String hoursLabel(int h) { return h == 0 ? "Aus" : h + " Stunden"; }
    private static String minLabel(int m) { return m == 0 ? "Aus" : m + " Minuten"; }

    private static String[] labels(int[] vals, boolean hours) {
        String[] out = new String[vals.length];
        for (int i = 0; i < vals.length; i++) out[i] = hours ? hoursLabel(vals[i]) : minLabel(vals[i]);
        return out;
    }

    private static int indexOf(int[] a, int v) {
        for (int i = 0; i < a.length; i++) if (a[i] == v) return i;
        return 0;
    }

}
