package com.noxis.guard;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.provider.Settings;
import android.graphics.Typeface;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

import java.util.List;

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

    @Override
    protected void onResume() {
        super.onResume();
        if (mList != null) render();   // Status nach Rückkehr aus Mullvad/Einstellungen aktualisieren
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

        statusCard();
        scanSection();

        header("Gerätesperre");
        choice("Automatischer Neustart", hoursLabel(Prefs.autoRebootHours(this)),
                "Startet das Gerät neu, wenn es so lange gesperrt war. Danach sind alle Daten wieder "
                        + "vollständig verschlüsselt (Zustand vor dem ersten Entsperren).",
                labels(REBOOT_H, true), indexOf(REBOOT_H, Prefs.autoRebootHours(this)),
                i -> mPrefs.edit().putInt(Prefs.AUTO_REBOOT_HOURS, REBOOT_H[i]).apply());
        duressRow();
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

        toggle("2G erlauben",
                "2G (GSM/EDGE) verschlüsselt schwach oder gar nicht und wird von IMSI-Catchern genutzt, "
                        + "um Geräte abzuhören. Aus = nur 4G/5G (und 3G, wo vorhanden). Notrufe gehen immer.",
                Prefs.allow2g(this), on -> {
                    mPrefs.edit().putBoolean(Prefs.ALLOW_2G, on).apply();
                    Hardening.apply2g(this, on);
                });

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

        links();
    }

    private void statusCard() {
        List<Status.Item> items = Status.check(this);
        int ok = Status.score(items);
        header("Schutzstatus");
        TextView score = text(ok + " von " + items.size() + " Schutzfunktionen aktiv", 20, true);
        score.setTextColor(ok == items.size() ? 0xFF7CFFB2 : 0xFFFFB27C);
        score.setPadding(dp(8), 0, dp(8), dp(8));
        mList.addView(score);
        for (Status.Item i : items) {
            TextView t = text((i.ok ? "✓  " : "!  ") + i.title + (i.ok ? "" : "\n     " + i.hint), 14, false);
            t.setAlpha(i.ok ? 0.75f : 1f);
            if (!i.ok) t.setTextColor(0xFFFFB27C);
            t.setPadding(dp(8), dp(4), dp(8), dp(4));
            mList.addView(t);
        }
    }

    /* ---------------- Virenscan ---------------- */

    private Scanner.Result mScan;
    private boolean mScanning;

    private void scanSection() {
        header("Virenscan");
        int sigs = Scanner.loadDb();
        String db = sigs > 0
                ? sigs + " ClamAV-Signaturen für Android" + (mScanVersion().isEmpty() ? "" : " · " + mScanVersion())
                : "Keine Signaturen im Image – nur Verhaltensprüfung";
        String summary;
        if (mScanning) {
            summary = "Prüfe Apps …";
        } else if (mScan == null) {
            summary = "Prüft alle installierten Apps. Neue Apps werden automatisch geprüft.\n" + db;
        } else {
            summary = mScan.apps + " Apps geprüft, " + mScan.findings.size() + " Funde\n" + db;
        }
        LinearLayout row = row("Jetzt prüfen", summary);
        row.addView(text("›", 22, false));
        row.setOnClickListener(v -> {
            if (mScanning) return;
            mScanning = true;
            render();
            new Thread(() -> {
                Scanner.Result r = Scanner.scanAll(this);
                runOnUiThread(() -> {
                    mScan = r;
                    mScanning = false;
                    render();
                });
            }, "noxis-scan").start();
        });
        mList.addView(row);
        if (mScan == null) return;
        if (mScan.findings.isEmpty()) {
            TextView t = text("✓  Nichts Verdächtiges gefunden", 14, false);
            t.setTextColor(0xFF7CFFB2);
            t.setPadding(dp(8), dp(4), dp(8), dp(4));
            mList.addView(t);
        }
        for (Scanner.Finding f : mScan.findings) {
            LinearLayout r = row((f.malware ? "✗  " : "!  ") + f.label, f.pkg + "\n" + f.reason);
            ((TextView) ((LinearLayout) r.getChildAt(0)).getChildAt(0))
                    .setTextColor(f.malware ? 0xFFFF6B6B : 0xFFFFB27C);
            r.addView(text("›", 22, false));
            r.setOnClickListener(v -> {
                try {
                    startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.fromParts("package", f.pkg, null)));
                } catch (RuntimeException e) { /* App schon weg */ }
            });
            mList.addView(r);
        }
    }

    private static String mScanVersion() {
        return Scanner.versionLabel();
    }

    private void links() {
        header("Weitere Schutzbereiche");
        link("Netzwerkzugriff pro App", "App antippen → Mobile Daten & WLAN → Netzwerkzugriff",
                new Intent(Settings.ACTION_APPLICATION_SETTINGS));
        link("Standard-Apps (Browser, Telefon)", "Empfohlen: IronFox als Browser, NothingCall als Telefon",
                new Intent(Settings.ACTION_MANAGE_DEFAULT_APPS_SETTINGS));
        link("Systemupdates", "Noxis-Updates von GitHub, signiert mit deinem Schlüssel",
                getPackageManager().getLaunchIntentForPackage("org.lineageos.updater"));
        if (Hardening.installed(this, Prefs.MULLVAD)) {
            link("Mullvad VPN öffnen", "Konto, Server, Verbindung",
                    getPackageManager().getLaunchIntentForPackage(Prefs.MULLVAD));
        }
    }

    /* ---------------- Notfall-PIN (Duress) ---------------- */

    private void duressRow() {
        if (!Duress.supported()) return;
        boolean on = Duress.isSet();
        LinearLayout row = row("Notfall-PIN (löscht alles)", (on ? "An" : "Aus")
                + "\nEine zweite PIN: wer sie am Sperrbildschirm eingibt, löscht das Gerät heimlich – "
                + "es zeigt nur „falsche PIN“, startet neu, löscht ohne Anzeige und schaltet sich aus. "
                + "Für den Notfall, wenn du entsperren musst.");
        row.addView(text("›", 22, false));
        row.setOnClickListener(v -> duressDialog(on));
        mList.addView(row);
    }

    private void duressDialog(boolean on) {
        boolean pin = Duress.lockType(this) == com.android.internal.widget.LockPatternUtils.CREDENTIAL_TYPE_PIN;
        int input = android.text.InputType.TYPE_CLASS_NUMBER | android.text.InputType.TYPE_NUMBER_VARIATION_PASSWORD;
        if (!pin) input = android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_PASSWORD;
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(20), dp(8), dp(20), 0);
        android.widget.EditText cur = field(box, "Aktuelle PIN / Passwort", input);
        android.widget.EditText du = field(box, "Neue Notfall-PIN", input);
        android.widget.EditText rep = field(box, "Notfall-PIN wiederholen", input);
        TextView warn = text("Achtung: Diese PIN am Sperrbildschirm = ALLE Daten weg. "
                + "Ändern sich deine echte PIN auf die Notfall-PIN oder entfernst du die Sperre, "
                + "wird die Notfall-PIN automatisch gelöscht.", 13, false);
        warn.setTextColor(0xFFFFB27C);
        warn.setPadding(0, dp(12), 0, 0);
        box.addView(warn);
        AlertDialog.Builder b = new AlertDialog.Builder(this)
                .setTitle("Notfall-PIN")
                .setView(box)
                .setPositiveButton("Speichern", (d, w) -> {
                    String c = cur.getText().toString(), n = du.getText().toString(), r = rep.getText().toString();
                    new Thread(() -> {
                        String err = Duress.set(this, c, n, r);
                        runOnUiThread(() -> {
                            new AlertDialog.Builder(this)
                                    .setTitle(err == null ? "Notfall-PIN aktiv" : "Nicht gespeichert")
                                    .setMessage(err == null ? "Eingabe am Sperrbildschirm löscht das Gerät." : err)
                                    .setPositiveButton(android.R.string.ok, null).show();
                            render();
                        });
                    }).start();
                })
                .setNegativeButton(android.R.string.cancel, null);
        if (on) {
            b.setNeutralButton("Entfernen", (d, w) -> {
                Duress.clear();
                render();
            });
        }
        b.show();
    }

    private android.widget.EditText field(LinearLayout box, String hint, int input) {
        android.widget.EditText e = new android.widget.EditText(this);
        e.setHint(hint);
        e.setInputType(input);
        e.setSingleLine(true);
        box.addView(e);
        return e;
    }

    private void link(String title, String summary, Intent intent) {
        if (intent == null) return;
        LinearLayout row = row(title, summary);
        row.addView(text("›", 22, false));
        row.setOnClickListener(v -> {
            try { startActivity(intent); } catch (RuntimeException e) { /* Ziel fehlt */ }
        });
        mList.addView(row);
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
