// SPDX-License-Identifier: GPL-3.0-or-later
// Noxis OS – Copyright (C) 2026 3rr0r (Real3rr0r303YT) – Made by 3rr0r303YT on TikTok
package com.noxis.guard;

import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.InstallSourceInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.provider.Settings;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Virenscan ohne Internet:
 *  1. ClamAV-Signaturen (nur Android-Malware, "Andr.*"): MD5, SHA-1 und SHA-256 jeder installierten
 *     App werden mit der Datenbank aus /product/etc/noxis/av verglichen. Die Datenbank kommt
 *     beim Bauen von ClamAV (noxis.sh apps) und wird mit jedem Noxis-Update neu.
 *  2. Verhaltensmuster: Bedienungshilfe, Geräteadministrator, Benachrichtigungszugriff und die
 *     typische Rechte-Kombination von Banking-Trojanern (SMS + Overlay + App-Installation).
 * Signaturen erkennen nur bekannte Schadsoftware – die Muster fangen auch neue ein.
 */
final class Scanner {
    static final String DB_DIR = "/product/etc/noxis/av";

    static final class Finding {
        final String pkg, label, reason;
        final boolean malware;   // true = Signaturtreffer, false = verdächtiges Muster
        Finding(String pkg, String label, String reason, boolean malware) {
            this.pkg = pkg; this.label = label; this.reason = reason; this.malware = malware;
        }
    }

    static final class Result {
        final List<Finding> findings = new ArrayList<>();
        int apps;
        int signatures;
        String dbVersion = "";
    }

    private static final Set<String> TRUSTED_INSTALLERS = new HashSet<>(Arrays.asList(
            "org.fdroid.fdroid", "com.aurora.store", "com.android.vending",
            "org.fdroid.basic", "com.looker.droidify", "dev.imranr.obtainium"));

    private static final String[][] IDX = {{"android_md5.idx", "16"}, {"android_sha1.idx", "20"},
            {"android_sha256.idx", "32"}};
    private static int sCount = -1;
    private static String sVersion = "";

    private Scanner() {}

    /**
     * Zählt die Signaturen. Die Datenbank wird nicht geladen: die Dateien sind sortierte
     * Datensätze fester Länge (Hash + 4 Byte Namensnummer) und werden direkt durchsucht –
     * Hunderttausende Hashes kosten so keinen Arbeitsspeicher.
     */
    static synchronized int loadDb() {
        if (sCount >= 0) return sCount;
        int n = 0;
        for (String[] i : IDX) {
            File f = new File(DB_DIR, i[0]);
            if (f.canRead()) n += (int) (f.length() / (Integer.parseInt(i[1]) + 4));
        }
        try (BufferedReader r = new BufferedReader(new FileReader(new File(DB_DIR, "VERSION")))) {
            String v = r.readLine();
            sVersion = v == null ? "" : v.trim();
        } catch (IOException e) {
            sVersion = "";
        }
        sCount = n;
        return n;
    }

    /** Binäre Suche; Namensnummer oder -1. */
    private static int lookup(String file, int size, byte[] hash) {
        File f = new File(DB_DIR, file);
        if (!f.canRead()) return -1;
        int rec = size + 4;
        try (RandomAccessFile raf = new RandomAccessFile(f, "r")) {
            long lo = 0, hi = raf.length() / rec - 1;
            byte[] buf = new byte[rec];
            while (lo <= hi) {
                long mid = (lo + hi) >>> 1;
                raf.seek(mid * rec);
                raf.readFully(buf);
                int c = 0;
                for (int i = 0; i < size && c == 0; i++) c = (buf[i] & 0xFF) - (hash[i] & 0xFF);
                if (c == 0) {
                    return ((buf[size] & 0xFF) << 24) | ((buf[size + 1] & 0xFF) << 16)
                            | ((buf[size + 2] & 0xFF) << 8) | (buf[size + 3] & 0xFF);
                }
                if (c < 0) lo = mid + 1; else hi = mid - 1;
            }
        } catch (IOException e) {
            Log.w(GuardController.TAG, "Signaturen nicht lesbar: " + f, e);
        }
        return -1;
    }

    private static String name(int id) {
        try (BufferedReader r = new BufferedReader(new FileReader(new File(DB_DIR, "android.names")))) {
            String line;
            for (int i = 0; (line = r.readLine()) != null; i++) if (i == id) return line;
        } catch (IOException e) {
            // Name egal, der Treffer zählt
        }
        return "Andr.Malware";
    }

    static synchronized String versionLabel() {
        return sVersion;
    }

    /** Alle Apps prüfen (Hintergrund-Thread!). */
    static Result scanAll(Context ctx) {
        Result res = new Result();
        res.signatures = loadDb();
        res.dbVersion = sVersion;
        PackageManager pm = ctx.getPackageManager();
        for (PackageInfo pi : pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)) {
            ApplicationInfo ai = pi.applicationInfo;
            if (ai == null) continue;
            boolean system = (ai.flags & (ApplicationInfo.FLAG_SYSTEM | ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0;
            // System-Apps stammen aus dem signierten Noxis-Image – nur Nutzer-Apps prüfen
            if (system) continue;
            res.apps++;
            scanOne(ctx, pi, res.findings);
        }
        return res;
    }

    /** Eine App prüfen, z. B. direkt nach der Installation. */
    static List<Finding> scanPackage(Context ctx, String pkg) {
        List<Finding> out = new ArrayList<>();
        loadDb();
        try {
            PackageInfo pi = ctx.getPackageManager().getPackageInfo(pkg, PackageManager.GET_PERMISSIONS);
            if (pi.applicationInfo != null) scanOne(ctx, pi, out);
        } catch (PackageManager.NameNotFoundException e) {
            // schon wieder weg
        }
        return out;
    }

    private static void scanOne(Context ctx, PackageInfo pi, List<Finding> out) {
        ApplicationInfo ai = pi.applicationInfo;
        String pkg = pi.packageName;
        String label = String.valueOf(ai.loadLabel(ctx.getPackageManager()));

        // 1. Signaturen
        List<String> files = new ArrayList<>();
        if (ai.sourceDir != null) files.add(ai.sourceDir);
        if (ai.splitSourceDirs != null) files.addAll(Arrays.asList(ai.splitSourceDirs));
        for (String f : files) {
            String name = match(f);
            if (name != null) {
                out.add(new Finding(pkg, label, "Bekannte Schadsoftware: " + name, true));
                return;   // Treffer reicht, Muster nicht mehr nötig
            }
        }

        // 2. Muster
        Set<String> perms = new HashSet<>();
        if (pi.requestedPermissions != null) perms.addAll(Arrays.asList(pi.requestedPermissions));
        List<String> why = new ArrayList<>();

        String a11y = Settings.Secure.getString(ctx.getContentResolver(),
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES);
        if (a11y != null && a11y.contains(pkg + "/")) {
            why.add("Bedienungshilfe aktiv – kann den Bildschirm lesen und Eingaben machen");
        }
        DevicePolicyManager dpm = ctx.getSystemService(DevicePolicyManager.class);
        List<ComponentName> admins = dpm == null ? null : dpm.getActiveAdmins();
        if (admins != null) {
            for (ComponentName cn : admins) {
                if (pkg.equals(cn.getPackageName())) {
                    why.add("Geräteadministrator – lässt sich nicht einfach deinstallieren");
                    break;
                }
            }
        }
        String nl = Settings.Secure.getString(ctx.getContentResolver(), "enabled_notification_listeners");
        if (nl != null && nl.contains(pkg + "/")) {
            why.add("Liest alle Benachrichtigungen (auch Codes per SMS/Mail)");
        }
        boolean sms = perms.contains("android.permission.RECEIVE_SMS") || perms.contains("android.permission.READ_SMS");
        boolean overlay = perms.contains("android.permission.SYSTEM_ALERT_WINDOW");
        boolean install = perms.contains("android.permission.REQUEST_INSTALL_PACKAGES");
        if (sms && overlay) {
            why.add("SMS lesen + über andere Apps zeichnen – typisch für Banking-Trojaner");
        } else if (overlay && install) {
            why.add("Über andere Apps zeichnen + Apps installieren – typisch für Dropper");
        }

        if (!why.isEmpty()) {
            String installer = installer(ctx, pkg);
            if (installer == null || !TRUSTED_INSTALLERS.contains(installer)) {
                why.add("Nicht aus F-Droid/Aurora installiert");
            }
            out.add(new Finding(pkg, label, String.join("\n", why), false));
        }
    }

    private static String installer(Context ctx, String pkg) {
        try {
            InstallSourceInfo i = ctx.getPackageManager().getInstallSourceInfo(pkg);
            return i.getInitiatingPackageName() != null ? i.getInitiatingPackageName() : i.getInstallingPackageName();
        } catch (PackageManager.NameNotFoundException | RuntimeException e) {
            return null;
        }
    }

    /** MD5, SHA-1 und SHA-256 in einem Durchgang; Name der Malware oder null. */
    private static String match(String path) {
        if (loadDb() == 0) return null;
        try (InputStream in = new FileInputStream(path)) {
            MessageDigest md5 = MessageDigest.getInstance("MD5");
            MessageDigest sha1 = MessageDigest.getInstance("SHA-1");
            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            byte[] buf = new byte[1 << 16];
            int n;
            while ((n = in.read(buf)) > 0) {
                md5.update(buf, 0, n);
                sha1.update(buf, 0, n);
                sha256.update(buf, 0, n);
            }
            byte[][] d = {md5.digest(), sha1.digest(), sha256.digest()};
            for (int i = 0; i < IDX.length; i++) {
                int id = lookup(IDX[i][0], Integer.parseInt(IDX[i][1]), d[i]);
                if (id >= 0) return name(id);
            }
            return null;
        } catch (Exception e) {
            Log.w(GuardController.TAG, "Nicht prüfbar: " + path, e);
            return null;
        }
    }
}
