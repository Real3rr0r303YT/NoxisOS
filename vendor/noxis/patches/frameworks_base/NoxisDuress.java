/*
 * Noxis OS – duress PIN
 * Copyright (C) 2026 Real3rr0r303YT – Made by 3rr0r303YT on TikTok
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Copied into frameworks/base/services/core/java/com/android/server/locksettings/
 * by tools/noxis_patch.py (p_duress), called from LockSettingsService.
 */

package com.android.server.locksettings;

import android.content.Context;
import android.os.Binder;
import android.os.IRecoverySystem;
import android.os.RecoverySystem;
import android.os.ServiceManager;
import android.os.SystemProperties;
import android.os.UserHandle;
import android.util.Base64;
import android.util.Slog;

import com.android.internal.widget.LockscreenCredential;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;

import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

/**
 * Duress PIN (like GrapheneOS): a second PIN / password, set in Noxis Guard. Entered on the
 * lock screen of the owner, it wipes the phone instead of unlocking - silently: the lock screen
 * only shows "wrong PIN", the phone restarts without any "factory reset" dialog, the recovery
 * wipes /data with its screen off (bootable/recovery patch: reason "noxis_duress" → stub UI)
 * and then powers the phone off.
 *
 * Safety:
 *  - Only a salted PBKDF2-SHA256 hash is stored, in locksettings.db (system only; reading it
 *    needs ACCESS_KEYGUARD_SECURE_STORAGE, a signature permission).
 *  - The real credential can never trigger it: Noxis Guard refuses a duress PIN equal to the
 *    current one, and setting a new lock credential that equals the duress PIN – or removing
 *    the lock – deletes the duress PIN ({@link #onCredentialChanged}).
 *  - Any error (no entry, unreadable entry, crypto failure) means "no match": a bug here can
 *    never lock anyone out, at worst the duress PIN does nothing.
 */
final class NoxisDuress {

    static final String KEY = "noxis_duress_v1";
    private static final String TAG = "NoxisDuress";
    private static volatile boolean sWiping;

    private NoxisDuress() {
    }

    /** True only if [credential] is the stored duress PIN of the owner (user 0). */
    static boolean matches(LockSettingsStorage storage, LockscreenCredential credential) {
        try {
            if (credential == null || credential.isNone()) return false;
            final String stored = storage.getString(KEY, null, UserHandle.USER_SYSTEM);
            if (stored == null || stored.isEmpty()) return false;
            final String[] p = stored.split(":");
            if (p.length != 4 || !"v1".equals(p[0])) return false;
            final byte[] salt = Base64.decode(p[1], Base64.NO_WRAP);
            final int iterations = Integer.parseInt(p[2]);
            final byte[] want = Base64.decode(p[3], Base64.NO_WRAP);
            if (iterations < 1000 || iterations > 1_000_000 || want.length < 16) return false;
            final byte[] got = hash(credential.getCredential(), salt, iterations, want.length * 8);
            return MessageDigest.isEqual(want, got);
        } catch (Throwable t) {
            Slog.w(TAG, "Duress check skipped", t);
            return false;
        }
    }

    private static byte[] hash(byte[] secret, byte[] salt, int iterations, int bits) throws Exception {
        final char[] chars = new String(secret, StandardCharsets.UTF_8).toCharArray();
        final PBEKeySpec spec = new PBEKeySpec(chars, salt, iterations, bits);
        try {
            return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();
        } finally {
            spec.clearPassword();
            Arrays.fill(chars, '\0');
        }
    }

    /** Recovery reads this reason and wipes with its screen off (bootable/recovery patch). */
    static final String REASON = "noxis_duress";

    /**
     * Silent wipe, off the binder thread, runs once:
     *  1. BCB = "--wipe_data --shutdown_after --reason=noxis_duress" (uncrypt service, like
     *     RecoverySystemService.rebootRecoveryWithCommand, but without PowerManager.reboot() -
     *     its ShutdownThread would show "Factory data reset" on the screen).
     *  2. Keystore keys deleted right away, like a normal forced wipe does.
     *  3. Reboot via init (sys.powerctl) - no dialog, no animation.
     * If the silent path fails, the normal (visible) wipe still runs: wiping beats hiding.
     */
    static void wipe(Context context) {
        if (sWiping) return;
        sWiping = true;
        new Thread(() -> {
            final long id = Binder.clearCallingIdentity();
            try {
                IRecoverySystem rs = IRecoverySystem.Stub.asInterface(
                        ServiceManager.getService(Context.RECOVERY_SERVICE));
                if (rs != null && rs.setupBcb("--wipe_data\n--shutdown_after\n--reason=" + REASON + "\n")) {
                    try {
                        android.security.AndroidKeyStoreMaintenance.deleteAllKeys();
                    } catch (Throwable t) {
                        // the recovery wipe removes /data anyway
                    }
                    SystemProperties.set("sys.powerctl", "reboot,recovery");
                    return;
                }
            } catch (Throwable t) {
                // fall through to the normal wipe
            } finally {
                Binder.restoreCallingIdentity(id);
            }
            try {
                RecoverySystem.rebootWipeUserData(context, true /* shutdown */, REASON,
                        true /* force */, false /* wipeEuicc */);
            } catch (Throwable t) {
                Slog.e(TAG, "Wipe failed", t);
                sWiping = false;
            }
        }, "NoxisDuressWipe").start();
    }

    /** New lock credential: drop the duress PIN if the lock is removed or equals it. */
    static void onCredentialChanged(LockSettingsStorage storage, LockscreenCredential credential,
            int userId) {
        try {
            if (userId != UserHandle.USER_SYSTEM) return;
            if (credential == null || credential.isNone() || matches(storage, credential)) {
                storage.removeKey(KEY, UserHandle.USER_SYSTEM);
            }
        } catch (Throwable t) {
            Slog.w(TAG, "Duress cleanup skipped", t);
        }
    }
}
