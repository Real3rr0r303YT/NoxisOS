package com.noxis.guard;

import android.content.Context;
import android.content.SharedPreferences;

/** Einstellungen von Noxis Guard (Device-Protected Storage, auch vor dem ersten Entsperren lesbar). */
final class Prefs {
    static final String AUTO_REBOOT_HOURS = "auto_reboot_hours";   // 0 = aus
    static final String USB_LOCK = "usb_charging_only_locked";      // boolean
    static final String WIFI_OFF_MIN = "wifi_auto_off_min";         // 0 = aus
    static final String BT_OFF_MIN = "bt_auto_off_min";             // 0 = aus
    static final String DNS = "private_dns";                        // "", "dns.quad9.net", ...
    static final String CONN_CHECK = "connectivity_check";          // boolean
    static final String HARDENED_V = "hardened_version";            // int
    static final String VPN_LOCKDOWN = "vpn_lockdown";              // boolean: Mullvad Always-on + Killswitch
    static final String VPN_APPLIED = "vpn_applied";                // boolean: beim ersten Entsperren gesetzt

    static final String MULLVAD = "net.mullvad.mullvadvpn";
    static final boolean DEF_VPN_LOCKDOWN = true;

    static final int DEF_AUTO_REBOOT_HOURS = 18;
    static final boolean DEF_USB_LOCK = true;
    static final int DEF_WIFI_OFF_MIN = 0;
    static final int DEF_BT_OFF_MIN = 0;
    static final String DEF_DNS = "dns.quad9.net";
    static final boolean DEF_CONN_CHECK = false;

    private Prefs() {}

    static SharedPreferences get(Context ctx) {
        Context dp = ctx.createDeviceProtectedStorageContext();
        return dp.getSharedPreferences("noxis_guard", Context.MODE_PRIVATE);
    }

    static int autoRebootHours(Context c) { return get(c).getInt(AUTO_REBOOT_HOURS, DEF_AUTO_REBOOT_HOURS); }
    static boolean usbLock(Context c) { return get(c).getBoolean(USB_LOCK, DEF_USB_LOCK); }
    static int wifiOffMin(Context c) { return get(c).getInt(WIFI_OFF_MIN, DEF_WIFI_OFF_MIN); }
    static int btOffMin(Context c) { return get(c).getInt(BT_OFF_MIN, DEF_BT_OFF_MIN); }
    static String dns(Context c) { return get(c).getString(DNS, DEF_DNS); }
    static boolean connCheck(Context c) { return get(c).getBoolean(CONN_CHECK, DEF_CONN_CHECK); }
    static boolean vpnLockdown(Context c) { return get(c).getBoolean(VPN_LOCKDOWN, DEF_VPN_LOCKDOWN); }
}
