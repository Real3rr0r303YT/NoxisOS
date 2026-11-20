/*
 * Noxis Guard – duress PIN
 * Copyright (C) 2026 Real3rr0r303YT – Made by 3rr0r303YT on TikTok
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
package com.noxis.guard;

import android.content.Context;
import android.os.ServiceManager;
import android.util.Base64;

import com.android.internal.widget.ILockSettings;
import com.android.internal.widget.LockPatternUtils;
import com.android.internal.widget.LockscreenCredential;
import com.android.internal.widget.VerifyCredentialResponse;

import java.security.SecureRandom;
import java.util.Arrays;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

/**
 * Notfall-PIN: speichert nur einen gesalzenen PBKDF2-Hash in locksettings.db (nur System lesbar).
 * Geprüft wird er im System (LockSettingsService → NoxisDuress, Patch p_duress): Eingabe am
 * Sperrbildschirm löscht das Gerät. Das Format muss zu NoxisDuress.java passen.
 */
final class Duress {

    static final String KEY = "noxis_duress_v1";
    private static final int ITERATIONS = 20000;
    private static final int OWNER = 0;

    private Duress() {
    }

    private static ILockSettings lockSettings() {
        return ILockSettings.Stub.asInterface(ServiceManager.getService("lock_settings"));
    }

    static boolean isSet() {
        try {
            String s = lockSettings().getString(KEY, null, OWNER);
            return s != null && !s.isEmpty();
        } catch (Exception e) {
            return false;
        }
    }

    static boolean supported() {
        return ServiceManager.getService("lock_settings") != null;
    }

    /** Typ der Displaysperre: PIN, Passwort, Muster (= nicht möglich) oder keine. */
    static int lockType(Context c) {
        return new LockPatternUtils(c).getCredentialTypeForUser(OWNER);
    }

    /** Fehlertext oder null. Läuft NICHT auf dem UI-Thread (prüft die aktuelle PIN). */
    static String set(Context c, String current, String duress, String repeat) {
        int type = lockType(c);
        if (type == LockPatternUtils.CREDENTIAL_TYPE_PATTERN) {
            return "Mit einem Muster geht das nicht – stelle die Displaysperre auf PIN oder Passwort um.";
        }
        if (type != LockPatternUtils.CREDENTIAL_TYPE_PIN && type != LockPatternUtils.CREDENTIAL_TYPE_PASSWORD) {
            return "Richte zuerst eine Displaysperre (PIN oder Passwort) ein.";
        }
        boolean pin = type == LockPatternUtils.CREDENTIAL_TYPE_PIN;
        if (duress.length() < 4) return "Die Notfall-PIN braucht mindestens 4 Zeichen.";
        if (pin && !duress.matches("[0-9]+")) return "Deine Sperre ist eine PIN – die Notfall-PIN darf nur Ziffern haben.";
        if (!duress.equals(repeat)) return "Die beiden Notfall-PINs sind verschieden.";
        if (duress.equals(current)) return "Die Notfall-PIN muss sich von deiner echten PIN unterscheiden.";

        LockscreenCredential cred = pin ? LockscreenCredential.createPin(current)
                : LockscreenCredential.createPassword(current);
        try {
            VerifyCredentialResponse r = new LockPatternUtils(c).checkCredential(cred, OWNER, null);
            if (r == null || !r.isMatched()) return "Die aktuelle PIN ist falsch.";
        } finally {
            cred.zeroize();
        }

        byte[] salt = new byte[16];
        new SecureRandom().nextBytes(salt);
        char[] chars = duress.toCharArray();
        PBEKeySpec spec = new PBEKeySpec(chars, salt, ITERATIONS, 256);
        try {
            byte[] hash = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
            lockSettings().setString(KEY, "v1:" + Base64.encodeToString(salt, Base64.NO_WRAP) + ":"
                    + ITERATIONS + ":" + Base64.encodeToString(hash, Base64.NO_WRAP), OWNER);
            return null;
        } catch (Exception e) {
            return "Speichern fehlgeschlagen: " + e.getMessage();
        } finally {
            spec.clearPassword();
            Arrays.fill(chars, '\0');
        }
    }

    static boolean clear() {
        try {
            lockSettings().setString(KEY, "", OWNER);
            return true;
        } catch (Exception e) {
            return false;
        }
    }
}
